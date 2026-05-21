# Synapse Graph Skills (V3)：为 AI 编程助手打造的图拓扑工程记忆系统

> 从扁平文件到图拓扑，从单体 Agent 到独立 Skill——一人全栈开发者的"AI 外脑"进化到第三代。

---

## 一、痛点：你的 AI 助手比你更健忘

作为一个一人全栈开发者，你的日常大概是这样：

- 周一：写 auth 模块，接好了 JWT 登录接口
- 周二：切到支付模块，调通支付宝回调
- 周三：紧急修一个通知系统的 bug
- 周四：回到 auth，但 AI 已经忘了你周一做了什么

三个星期，三个模块来回切。每次切回来，你的 AI 编程助手要么：

1. **加载了无关记忆**——把通知系统的上下文也塞进来，浪费 token
2. **漏掉了关键依赖**——不知道改 auth 会影响支付模块的 token 校验
3. **产生幻觉**——模糊记忆导致"猜测"而非"精确回忆"

这就是 **context 崩溃**：模块越多，AI 能有效利用的上下文越少。

---

## 二、现有方案为什么不行

| 方案 | 问题 |
|------|------|
| **向量数据库 + RAG** | 太重了，个人开发者维护不起 Pinecone/Weaviate；语义检索有幻觉风险——"登录"和"注册"的向量很近，但改登录不该加载注册的上下文 |
| **全文 grep** | 关键词匹配不精确，跨模块依赖完全靠猜 |
| **全量加载** | 8 个模块还能忍，30 个模块的 context 直接爆炸 |
| **靠人记** | 三个星期后连你自己都不记得当时的细节了 |

**Synapse 的回答是：不做向量。不做 embedding。纯确定性图遍历。**

---

## 三、三代进化：从扁平文件到图拓扑 Skill

Synapse 记忆体系经历了三次迭代：

```
Synapse V1                Synapse-Solo V2           Synapse Graph Skills V3 ← 当前
─────────────────        ──────────────────        ──────────────────────────────
形态：单脚本 + 配置        形态：单体 Agent 记忆        形态：四枚独立可安装 Skill
存储：扁平 Markdown        存储：扁平 Markdown         存储：图拓扑节点 + 显式依赖边
检索：全文 grep            检索：关键词 + 摘要匹配      检索：三层渐进式 + 受限 BFS
索引：无                   索引：简单摘要索引            索引：倒排 MAP（O(1) 查找）
边关系：无                 边关系：隐式（命名约定）      边关系：显式 depends_on / blocks
一致性：靠人记             一致性：靠人记               一致性：Hook 运行时强制
规模：~10 节点             规模：~15 节点               规模：30+ 节点（常数级 context）
```

**关键分叉点**：V1 和 V2 都是"扁平文件 + 全量/半全量加载"模型。模块数超过 15 之后，context 窗口被无关信息占满。V3 的图拓扑 + 受限 BFS 让检索成本与模块数**解耦**——这是根本性的架构变化。

---

## 四、V3 的四大核心创新

### 创新一：显式图拓扑，告别"猜关系"

V1/V2 中，模块之间的关系是**隐式**的——靠文件命名约定（`auth.md`、`payment.md`）或关键词重叠来暗示。AI 需要"猜测"哪些文件相关，猜错就加载了无关上下文。

V3 在每个节点的 YAML frontmatter 中声明**显式依赖边**：

```yaml
---
depends_on: [mod_auth-api, mod_user-account]  # 硬依赖：改我必看它
auto_linked: [mod_design-system]               # 软依赖：机器推断，参与遍历
tags: [auth, login, jwt]
aliases: [认证, 登录, signin, token验证]
---
```

三种边类型形成完整的依赖图：

| 边类型 | 语义 | 维护者 |
|--------|------|--------|
| `depends_on` | 确认的硬依赖——目标变了，本节点必受影响 | 人工确认 |
| `auto_linked` | 机器推断的软依赖——高置信度但未经人工确认 | `suggest_edges.sh` |
| `blocks` | 反向边——"谁依赖我？" | `generate_memory_map.sh` 自动计算 |

**"改 X 会影响哪些功能？"从 O(n) 的关键词猜测变成了 O(1) 的 MAP 查表。** 这是图拓扑相比扁平文件最本质的优势。

### 创新二：三层渐进式加载——永不"全量读取"

这是 V3 检索协议的核心。V1/V2 的典型行为是"把所有 `meta/*.md` 读一遍以防万一"。V3 强制执行严格的三层协议：

```
第 1 层：MEMORY_MAP 标签索引 + 摘要     (~200-500 tokens)
    ├── 匹配到节点，简单查询 → STOP
    │
第 2 层：完整目标节点                    (~500-1500 tokens/节点)
    ├── 简单任务（修按钮颜色）→ STOP
    │
第 3 层：受限 BFS（深度≤2，宽度≤5）     (~1000-4000 tokens)
    ├── Token 预算 > 15% context → 硬停止
    └── 永远不加载全部节点
```

**关键约束**：
- **深度 ≤ 2**：A→B→C，停在 C。不继续展开 D。
- **宽度 ≤ 5**：依赖超过 5 个？只加载声明顺序前 5 个。
- **Token 硬上限**：总消耗超过 context 窗口的 15%？立刻停止，报告用户。

30 个模块时，暴力加载需要把所有 30 个文件读一遍。受限 BFS 最多加载 2 + 5 + 5×5 = 32 个节点的**最坏情况**，实际场景通常在 2-10 个文件之间——**和 8 个模块时的表现几乎一样**。

### 创新三：Hook 运行时强制，不止于"文档规范"

V1/V2 的一致性靠"开发者记得遵守规范"——实际上没人记得。V3 把协议写进 Claude Code 的 **PreToolUse / PostToolUse / Stop hooks**，在运行时强制执行：

| Hook | 触发时机 | 行为 |
|------|----------|------|
| **PreToolUse** | 每次 AI 尝试读取文件 | 拦截读取请求，强制按协议顺序（MAP → 目标节点 → BFS） |
| **PostToolUse** | 每次 AI 写入文件后 | 自动检测跨模块引用，建议新增/更新边 |
| **Stop** | 会话结束时 | 重建 MEMORY_MAP、校验拓扑健康、检测源码漂移、输出变更摘要 |

**规则不再是一份"建议文档"——不遵守协议，AI 就根本读不到文件。**

Stop hook 的输出示例：

```
[doctor] Topology Health:
  ✓ 18 nodes: 14 active, 4 archived
  ✓ 23 effective_edges, 0 dead links
  ⚠ 1 oversized node: mod_payment.md (218 lines, >200)
  ⚠ 3 nodes flagged for drift (source changed, meta not updated)

[change-summary] Since last session:
  M meta/feat_login.md        (+2 Change Log entries)
  M meta/mod_auth-api.md      (updated Connection Points)
  M MEMORY_MAP.md             (auto-rebuilt)
```

### 创新四：连接点作为可验证的接口契约

V1/V2 的跨模块描述是自由文本："需要 auth API"——这对影响评估毫无用处。

V3 的连接点是**机器可验证的结构化契约**，带源码锚点：

```markdown
### To mod_payment
- **Endpoint**: POST /api/v1/payments/callback  <!-- @ref: src/payment/routes.ts:45 -->
- **Request**: `{ order_id: string, status: string, amount: number }`
- **Response**: `{ success: boolean, plan: string }`
- **Errors**: `402` Insufficient funds, `409` Duplicate order
- **Constraints**: Idempotent via `Idempotency-Key` header
```

`@ref: src/payment/routes.ts:45` 这个锚点让 `session-end.sh` 可以在每次会话结束时**自动检测源码是否已经偏离了记忆中的契约**（漂移检测）。发现漂移时发出警告，而不是等到出了问题才发现"记忆已经过时了"。

---

## 五、四枚独立 Skill：模块化架构

V3 以 **Skills** 形态发布为四枚独立可安装的模块。每枚 Skill 自包含全部所需脚本——装了就能用，不依赖其他 Skill：

```
synapse-graph-memory (核心检索引擎，始终加载)
├── 7 步决策树检索协议
├── 节点规范 + 5 条关键规则 + 16 种反模式
├── 11 个脚本 + 4 个 hooks（完整捆绑）
└── .skill 大小：66 KB

synapse-timeline              synapse-daily-note           synapse-init
(只读时间线查询)                (一行命令写入管线)            (项目冷启动向导)
. skill：5.5 KB               .skill：26 KB                .skill：43 KB
```

### Skill 1: synapse-graph-memory（核心检索引擎）

**触发词**："XX 做得怎么样了？"、"还差什么？"、"会影响哪些 feature？"

7 步决策树：查询分类 → MAP 标签索引查找 → 别名匹配回退 → 关键词索引兜底 → 目标节点加载 → 受限 BFS 展开 → 修改协议（写操作时检查 `blocks`）。

### Skill 2: synapse-timeline（时间线查询）

**触发词**："最近改了啥？"、"从 5 月 1 号之后的改动？"、"有哪些 open issues？"

单脚本（bash + 嵌入式 Python，227 行），支持 `--tag`、`--since`、`--recent N`、`--node`、`--issues` 过滤。

### Skill 3: synapse-daily-note（日常记录管线）

**触发词**："记录一下：接好了 POST /api/v1/auth/login"

一行命令跑完整条管线：`ingest`（NL→结构化 JSON）→ `suggest_edges`（自动检测跨模块边）→ `apply`（写入 meta/*.md）→ `rebuild MAP` → `doctor`（拓扑校验）。30 秒记一条，下次会话省 10 分钟。

### Skill 4: synapse-init（冷启动向导）

**触发词**："初始化记忆"、"给项目配 Synapse"

自动检测技术栈（Node/React/Python/FastAPI/Go/Rust/Java），从 `src/` 目录结构推断模块边界，生成骨架节点，注册 hooks。

---

## 六、评估数据：Skill 到底带来了什么？

在 8 节点 SaaS 测试项目（solo-saas）上使用 deepseek-v4-pro 进行评估：

| 指标 | 有 Skill | 无 Skill | 变化 |
|------|---------|----------|------|
| 平均读取文件数 | **8.0** | 13.0 | **-38%** |
| 无关文件数 | **0** | 4.5 | 核心优势 |
| 断言通过率 | **100%** | 62.5% | — |

**关键发现**：Skill 的核心优势不在于 token 节省（8 个节点时 token 差距很小），而在于**文件读取的精准度**——无 Skill 时 AI 会加载两个 MAP 格式、缓存文件、所有 meta 节点"以防万一"。节点数越多，精准度的差距越明显。

```
有 Skill：SKILL.md → MEMORY_MAP.md → feat_login → BFS(depth 1): mod_auth-api + mod_design-system
无 Skill：MEMORY_MAP.* → ALL 8 meta/*.md → README → 2 个 cache 文件
```

跨模块影响查询（"改 mod_user-account 会影响哪些功能？"）中，有 Skill 额外给出了**逐字段风险评估**（rename vs add vs delete 对 `active_plan_id`、`plan_expires_at`、`subscription_status` 的不同影响）——这是无 Skill 做不到的细粒度分析。

---

## 七、与常见方案的对比

| 方案 | Context 控制 | 跨模块感知 | 幻觉风险 | 运维成本 | 适合规模 |
|------|-------------|-----------|---------|---------|---------|
| **全量加载** | 差（O(n)） | 靠人 | 低 | 零 | ≤5 模块 |
| **向量 RAG** | 中（相似度截断） | 隐式（向量距离） | 高 | 高（向量库） | 大型团队 |
| **Synapse V1/V2** | 中（手动选择） | 隐式（命名约定） | 中 | 低 | ≤15 模块 |
| **Synapse V3** | 好（BFS 受限） | 显式（图拓扑） | 低 | 低（零依赖） | 30+ 模块 |

Synapse V3 的定位很明确：**为 1-3 人的小型团队/个人开发者设计，不需要运维向量数据库，不需要担心 embedding 漂移，图拓扑保证确定性。**

---

## 八、快速上手

### 1. 安装 Skill

```bash
# 复制到 Claude Code skills 目录
cp -r skills/synapse-graph-memory ~/.claude/skills/
cp -r skills/synapse-timeline ~/.claude/skills/
cp -r skills/synapse-daily-note ~/.claude/skills/
cp -r skills/synapse-init ~/.claude/skills/
```

### 2. 初始化项目记忆

```
用户：初始化记忆
```

Synapse 自动检测技术栈，扫描 `src/` 目录，为每个模块生成骨架节点。

### 3. 日常记录

```
用户：记录一下：接好了 POST /api/v1/auth/login，返回 JWT token，refresh token 存 httpOnly cookie
```

一行命令，30 秒完成全管线。

### 4. 查询状态

```
用户：登录功能做得怎么样了？
用户：还有什么没做完的？
用户：改 mod_user-account 会影响哪些功能？
用户：最近两天前端改了啥？
```

---

## 九、总结

Synapse Graph Skills (V3) 要解决的核心问题只有一个：**当你的 AI 编程助手面对 30 个模块时，它不应该把 30 个模块的上下文全部塞进 prompt。**

三个技术决策让它做到这一点：

1. **图拓扑 + 显式边** → "哪些模块相关"是可计算的问题，不是靠猜的
2. **三层渐进式 + 受限 BFS** → 读什么、读到哪一层、什么时候停，全有明确边界
3. **Hook 运行时强制** → 协议不被遵守 = 协议不存在

从 V1 的扁平文件，到 V2 的单体 Agent，再到 V3 的图拓扑 + Skills 架构——每一次迭代都在逼近同一个目标：

> **项目记忆的加载成本，不应该随模块数量线性增长。**

---

## 相关链接

- [GitHub 仓库](https://github.com/your-org/synapse-graph-skills)
- [架构文档](docs/architecture.md)
- [Skills 总览](docs/skills-overview.md)
- [使用指南](USAGE.md)
- [评估报告](EVAL_REPORT.md)

---

*本文由 Synapse Graph Skills 作者撰写，欢迎转载，请注明出处。*
