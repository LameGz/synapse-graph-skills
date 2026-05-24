# V3.3 单项目全栈记忆 — 设计文档

> 日期：2026-05-24 | 状态：已确认 | 来源：brainstorming 会话

---

## 概述

在 V3.0 四枚独立 Skill + 多项目架构的基础上，新增**单项目全栈记忆模式**。核心思路：扩展 `synapse-graph-memory`（核心引擎）的节点类型和初始化深度，让同一个引擎支持两种使用模式——多项目模块依赖查询 + 单项目端到端全栈链路追踪。

---

## 1. 架构决策

**选择：路线 B —— 引擎 Skill 扩展 + 薄 Wrapper，不建新 Skill。**

```
synapse-graph-memory/  (核心引擎，扩展现有文件)
├── SKILL.md                  ← 新增"链路追踪"查询模式
├── references/node-spec.md   ← 新增 db_/api_/ui_/dep_ 节点规范
├── references/fullstack-node-spec.md  ← 新建：独立的全栈节点规范
├── references/critical-rules.md       ← 扩展：补丁规则
└── scripts/
    ├── generate_memory_map.sh ← 新增 bfs_trace() + --traverse-types
    ├── init.sh                ← 新增 --fullstack + 四层扫描流水线
    └── doctor.sh              ← 新增全栈节点校验规则

synapse-init/  (薄 wrapper)
└── scripts/init.sh            ← 357 行 → 15 行，透传到核心引擎
```

**为什么不建新 Skill**：避免代码分叉。全栈只是"多了一种初始化深度 + 多了四种节点类型"，底层 BFS 引擎、写入管线、时间线查询完全不变。

---

## 2. 新增节点类型

四种新节点 + 现有三种节点 = 七种节点：

| 类型 | 前缀 | 粒度 | 中小型项目估算 |
|------|------|------|-------------|
| database_table | `db_` | 一张表一个节点 | 10-30 |
| api_endpoint_group | `api_` | 一个 router 文件一组 endpoint | 5-15 |
| ui_page | `ui_` | 一个页面（含子组件） | 5-20 |
| deployment | `dep_` | 一个部署单元 | 2-5 |

### 粒度补丁

- **ui_ Tab 级例外**：当一个页面聚合了 3 个以上互不相关的业务域，且拆分后 `depends_on` 列表重叠度 < 30%，允许拆为 `ui_admin-user-tab`、`ui_admin-finance-tab`。
- **db_ 只列骨架字段**：Columns 表只列参与了业务逻辑判断的字段（被 WHERE/JOIN/IF 引用）。审计/时间戳/备注字段省略。
- **dep_ 是终端锚点**：不描述"怎么部署"，只描述"哪些东西在一个网络里互通，通过什么环境变量连起来"。

### 双向边规则（补丁 3）

- **正向边**：`depends_on: [...]` YAML 头——唯一写入点，唯一真相源
- **反向边**：`## Connection Points` 中的展示文本——引擎自动反向注入，AI 只看不写，不参与拓扑计算
- **校验**：`doctor.sh` 校验时唯一权威来源是 `blocks` 字段（MAP 构建时计算），不是 Markdown 文本
- **拦截**：如果在被动方的 YAML 里也写了反向依赖，`post-tool-use hook` 直接报错

### 节点样例

**db_ 节点**：

```yaml
---
id: db_orders
type: database_table
engine: InnoDB
depends_on: []
auto_linked: [api_order-routes, feat_payment]
tags: [order, payment, transaction]
summary: 订单主表，记录每笔交易的状态和金额
---
## Columns (仅业务骨架字段，辅助字段省略)
| 列名 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK | |
| user_id | BIGINT | FK → users.id | |
| status | ENUM(...) | NOT NULL | 支付状态流转 |
| amount | DECIMAL(10,2) | NOT NULL | |
| ... | ... | (省略 12 个辅助字段) | |

## Connection Points
- **写入方**: api_order-routes (POST /orders, PUT /orders/:id/status)
- **读取方**: api_payment-routes, api_report-routes
```

**api_ 节点**：

```yaml
---
id: api_payment-routes
type: api_endpoint_group
framework: FastAPI
source: src/routes/payment.py
depends_on: [mod_alipay-sdk, db_orders, db_transactions]
auto_linked: [feat_payment, ui_checkout-page]
summary: 支付相关接口：扫码支付、回调通知、退款、查询
---
## Endpoints
| 方法 | 路径 | 说明 | 状态 |
|------|------|------|------|
| POST | /api/v1/payments/qr | 生成扫码支付二维码 | done |
| POST | /api/v1/payments/callback | 支付宝回调通知 | done |
| POST | /api/v1/payments/refund | 申请退款 | todo |

## Connection Points
- **读写**: db_orders (orders 表), db_transactions (transaction_log 表)
- **调用**: mod_alipay-sdk (支付宝 API 封装)
```

**ui_ 节点**：

```yaml
---
id: ui_checkout-page
type: ui_page
framework: React 18 + Tailwind
source: src/pages/Checkout.tsx
depends_on: [mod_design-system, api_payment-routes, api_cart-routes]
auto_linked: [feat_payment, db_orders]
summary: 结算页面：购物车清单 → 选择支付方式 → 扫码支付 → 等待回调
---
## States
- cart_loaded → payment_pending → payment_success | payment_failed | payment_timeout

## API 调用
- GET /api/v1/cart (页面加载)
- POST /api/v1/payments/qr (点击支付)
- GET /api/v1/payments/status/:order_id (轮询支付结果)
```

**dep_ 节点**：

```yaml
---
id: dep_container-config
type: deployment
depends_on: [db_orders, db_users]
auto_linked: [api_payment-routes]
tags: [docker, postgres, redis]
summary: 生产环境容器编排，app + postgres + redis 通过 docker-compose 网络互通
---
## Environment Bridges
| 变量 | 连接 | 说明 |
|------|------|------|
| DATABASE_URL | api_* → db_* | postgres://user:pass@postgres:5432/mydb |
| REDIS_URL | api_payment-routes → redis | redis://redis:6379/0 (支付状态缓存) |
```

---

## 3. 全栈初始化扫描（init.sh --fullstack）

**总原则**：初始化只生成骨架——id、type、source、summary、tags、空的 depends_on、粗粒度的表格。不填 Connection Points，不建跨类型边。初始化 = 免去从空白文件手写。

**四层扫描流水线**：

| 层级 | 扫描目标 | 源文件模式 | 提取方法 | 准确率 |
|------|---------|----------|---------|--------|
| 1 | DB Schema | Prisma / Django models / SQL / Go ent / TypeORM | 正则 + AST（Python stdlib） | 60-100% |
| 2 | API Routes | FastAPI / Express / Next.js / Go Gin / Rust Axum | 正则提取路由定义 | 70-95% |
| 3 | UI Pages | React pages / Vue views / SvelteKit routes | 文件名 + 目录结构 | 55-65% |
| 4 | Deployment | Dockerfile / compose / k8s / .env.example | 正则 + 配置文件解析 | 70-100% |

- Layer 3（UI）最不准——只生成节点骨架，不推断 depends_on
- Layer 4 提取 Environment Bridges（环境变量 → 连接关系）
- 扫描完成后打印摘要 + 待办清单

---

## 4. 链路追踪查询（BFS 引擎改造）

在现有影响查询（反向 fan-out）和依赖查询（正向 fan-out）之外，新增第三种遍历模式。

### 意图识别

SKILL.md STEP 1 新增意图：
- "支付链路怎么通的" → 链路追踪
- "这个按钮点下去经过了哪些接口" → 链路追踪

### 参数差异

| 参数 | 影响查询 | 链路追踪 |
|------|---------|---------|
| 方向 | 反向（沿 blocks） | 正向（沿 depends_on） |
| --traverse-types | 无 | `ui,api,db,dep` |
| depth | ≤2 | ≤4 |
| width | ≤5 | ≤3 |
| 终点条件 | 无 | 必须落在序列终态 |
| 结果后处理 | 无 | 回溯剪枝 |

### 状态机逻辑（替代严格步序）

```
BFS 队列元素: { node_id, depth, type_pos, path_to_here }
type_sequence = [ui, api, db, dep]

展开邻居时:
  neighbor_type = get_type(neighbor)
  valid_positions = [i for i in range(type_pos, len(type_sequence))
                     if type_sequence[i] == neighbor_type]
  if empty → 跳过
  next_pos = valid_positions[0]  # 最靠前的匹配位置（允许跳级和同类型多跳）

允许多跳: ui → api_A → api_B → db （微服务网关）
允许跳级: ui → api → dep （跳过 db，直接到部署层）
```

### 回溯剪枝

BFS 结束后：
1. 筛选 `path[-1]` 类型在终态集合中的路径
2. 按长度排序，取最短的 width 条
3. 如果零条到达终点 → 降级为"部分链路"模式 + ⚠ 告警

### 实现

- `generate_memory_map.sh` 中新增独立函数 `bfs_trace()`，不改现有 BFS 路径
- 两者共用同一个节点/边数据源，遍历方向和过滤逻辑各自独立

---

## 5. 文件变更清单

### 修改文件

| 文件 | 改动 |
|------|------|
| `synapse-graph-memory/SKILL.md` | STEP 1 新增链路追踪意图；STEP 4 新增链路追踪子协议 |
| `synapse-graph-memory/references/node-spec.md` | 新增四种全栈节点类型引用 |
| `synapse-graph-memory/references/critical-rules.md` | 新增补丁规则：双向边只存正向、db_骨架字段、ui_ Tab 例外 |
| `synapse-graph-memory/scripts/generate_memory_map.sh` | 新增 `bfs_trace()` + `--traverse-types` |
| `synapse-graph-memory/scripts/init.sh` | 新增 `--fullstack` + 四层扫描 |
| `synapse-graph-memory/scripts/doctor.sh` | 新增全栈节点校验规则 |
| `synapse-init/scripts/init.sh` | 357 行 → 15 行薄 wrapper |

### 新建文件

| 文件 | 说明 |
|------|------|
| `synapse-graph-memory/references/fullstack-node-spec.md` | 独立全栈节点规范，按需加载 |

### 不改文件

- `synapse-timeline` 全部
- `synapse-daily-note` 全部
- `suggest_edges.sh`（天然支持新节点类型）
- `ingest_memory.py`、`apply_memory_proposal.py`（数据格式不变）

---

## 6. 用户安装组合

```
组合一：单项目深度全栈
  安装: synapse-graph-memory
  初始化: /初始化记忆 → init.sh --fullstack
  日常: /支付链路怎么通的  /改 orders 表会影响哪些页面

组合二：多项目模块依赖（V3.0 原有）
  安装: synapse-graph-memory + timeline + daily-note + init
  初始化: /初始化记忆 → init.sh（现有逻辑）
  日常: /改X会影响什么  /最近改了啥  /记录一下
```

共用同一套引擎——区别仅在于 init 是否传 `--fullstack`。

---

## 7. 回退兼容

- 不传 `--fullstack` 时，init.sh 行为与 V3.0 完全一致
- 不传 `--traverse-types` 时，BFS 行为与 V3.0 完全一致
- 现有 mod_/feat_/proj_ 节点不受新节点类型影响
- MEMORY_MAP 格式向上兼容——新 type 值不影响旧查询
