# Synapse Graph Skills

**面向全栈个体户的工程记忆系统。** 图拓扑记忆 + SQLite FTS5 + 全栈节点类型（DB → API → UI → Deploy）+ AI 自主写入——永不一次性加载全部记忆，永不忘记记录。

[English](README.md) | [使用指南](USAGE.md) | [架构文档](docs/architecture.md) | [Skills 总览](docs/skills-overview.md) | [演化日志](EVOLUTION.md)

---

## 演化历程

Synapse 历经四代演化，v1.1-v1.4 在 v1.0 图拓扑基础上新增了关键能力：

```
V1 (2024)           V2 (2025)          v1.0 (2026-05)      v1.1–v1.4 (2026-05) ← 当前
────────────────    ───────────────    ────────────────    ──────────────────────
扁平 Markdown        单体 Agent          4 Skill + 图拓扑     +SQLite +全栈 +自动写入
grep 搜索            关键词搜索          三层渐进 BFS          增量 MAP
无边关系              隐式边              显式边（3 种）        FTS5 BM25 搜索
~10 节点              ~15 节点            30+ 节点（常数级）    Stale 实时检测
                                                              AI 自主记忆写入
```

**v1.1** — 增量 MAP 更新 + `source_scan.py` AST 接口提取  
**v1.2** — SQLite FTS5 缓存 + `watch.sh` 实时 Stale 检测  
**v1.3** — 全栈 7 种节点类型 + `bfs_trace()` 链路追踪 + `init.sh --fullstack`  
**v1.4** — AI 自主记忆写入——不再需要手动 `/记录一下`

完整演化日志：[EVOLUTION.md](EVOLUTION.md)

---

## v1.1–v1.4 新特性

### SQLite FTS5 缓存（v1.2）

MEMORY_MAP 现在有 SQLite 做后端，全文搜索用 BM25 排序。Tag 查找、关键词搜索、亲和度计算从 bash grep 升级为 FTS5 索引查询。Markdown 文件仍是主存储——SQLite 是派生缓存。

```bash
generate_memory_map.sh --db      # 同步到 SQLite
query_timeline.sh --tag payment  # FTS5 查询，O(log n)
```

### 全栈节点类型（v1.3）

在 `mod_`（模块）和 `feat_`（功能）之外，新增四种节点类型覆盖完整技术栈：

| 类型 | 前缀 | 示例 |
|------|------|------|
| 数据库表 | `db_` | `db_orders`——字段、索引、外键关系 |
| API 端点组 | `api_` | `api_payment-routes`——按 router 文件分组的端点 |
| UI 页面 | `ui_` | `ui_checkout-page`——页面状态、API 调用 |
| 部署单元 | `dep_` | `dep_container-config`——环境变量桥接 |

```bash
init.sh --fullstack   # 扫描 DB schema + API 路由 + UI 页面 + 部署配置
```

### 链路追踪查询（v1.3）

问"支付链路从前端按钮到数据库怎么通的？"一次拿到完整链路：

```
ui_checkout-page → api_payment-routes → db_orders → dep_container-config
```

`bfs_trace()` 状态机 BFS，支持多跳同类型（微服务网关）、跳级遍历（直连 Redis 不经 DB），回溯剪枝去死胡同。

### AI 自主记忆写入（v1.4）

最大的 UX 变化：**你不再需要记住敲 `/记录一下`。** AI 在对话中观察文件变更和讨论内容，会话结束时自动生成记忆提案，高置信度（≥70%）条目静默写入。

```
🧠 Synapse Session End

📝 本次自动记录：
  ✓ api_payment-routes: 新增 API 端点 POST /callback (95%)
  ✓ feat_login: 响应式断点 768→640px (90%)

⚠  待确认：
  1. [key_decision] 决定: Redis 做支付状态缓存 (85%)
```

由 `auto_observe.py` 驱动——从 git diff + 对话文本中提取信号。

---

## 四个独立 Skill

每个 skill **独立可安装**，不需要全装，按需选择：

| Skill | 功能 | 安装场景 |
|-------|------|---------|
| **[synapse-graph-memory](synapse-graph-memory/)** | 核心引擎——检索协议 + 链路追踪 + 自主写入 | 所有场景必装 |
| **[synapse-timeline](synapse-timeline/)** | 只读时间线 & Open Issues 查询 | 想看"最近改了啥"、"还有哪些问题" |
| **[synapse-daily-note](synapse-daily-note/)** | NL→记忆写入管线 | 手动记录进度（v1.4 后可不用） |
| **[synapse-init](synapse-init/)** | 冷启动向导 | 为新项目或已有项目初始化记忆 |

---

## 快速开始

### 安装

```bash
cp -r synapse-graph-memory ~/.claude/skills/
```

### 初始化项目

```
用户：初始化记忆
```

自动检测技术栈、创建 `meta/` 骨架节点、注册 hooks。

全栈项目用：
```
用户：初始化记忆 --fullstack
```

四层扫描：DB schema → API 路由 → UI 页面 → 部署配置。

### 记录进度（手动或自动）

**手动（v1.0）**：
```
用户：记录一下：接好了 POST /api/v1/auth/login，返回 JWT token
```

**自动（v1.4）**：正常写代码、聊天就行。AI 自己观察、自己记。会话结束时看看自动写了什么即可。

### 查询状态

```
用户：支付做得怎么样了？
用户：改 orders 表会影响哪些页面？
用户：支付链路从前端到数据库怎么通的？
```

Synapse 精确加载需要的节点——MAP 先查，再目标节点，BFS 展开仅在必要时。

---

## 基准数据

### v1.0 基线（8 节点测试项目，deepseek-v4-pro）

| 指标 | 装 Skill | 不装 | 变化 |
|------|---------|------|------|
| 平均读取文件数 | **8.0** | 13.0 | **-38%** |
| 无关文件 | **0** | 4.5 | 核心优势 |
| 断言通过率 | **100%** | 62.5% | — |

### v1.2 SQLite 性能（30 节点测试）

| 操作 | v1.0 (bash+grep) | v1.2 (SQLite FTS5) | 加速 |
|------|-----------------|-------------------|------|
| Tag 查找 | ~120ms | ~5ms | **~24×** |
| 全文搜索 | ~200ms | ~5ms | **~40×** |
| Doctor 健康检查 | ~350ms | ~120ms | **~3×** |
| 全量 MAP 重建 | ~2.1s | ~1.6s | **~1.3×** |

### v1.4 自动观察准确率（模拟 50 会话）

| 信号类型 | 精确率 | 召回率 | 说明 |
|----------|--------|--------|------|
| 文件变更→Change Log | 92% | 88% | 后端路由/模型最准 |
| 对话→Key Decision | 78% | 65% | 中文模式更可靠 |
| 对话→Open Issue | 71% | 58% | 需扩展阻塞词库 |
| 新增 API→Connection Point | 98% | 95% | git diff 正则，近乎完美 |

30+ 模块时差距呈指数级扩大——暴力加载随模块数线性增长，受限 BFS 保持常数级。

---

## 仓库结构

```
synapse-graph-skills/
├── synapse-graph-memory/     # 核心引擎——检索、BFS、SQLite、自动写入
│   ├── SKILL.md              # 检索协议 + 自主写入规则
│   ├── references/           # 节点规范、补丁规则、全栈节点类型
│   └── scripts/              # 17 个脚本：MAP、doctor、watch、auto_observe 等
├── synapse-timeline/         # 只读时间线 & 问题查询
├── synapse-daily-note/       # NL → 记忆写入管线
├── synapse-init/             # 冷启动向导（薄 wrapper）
├── docs/                     # 架构、贡献指南、设计文档、实现计划
├── EVOLUTION.md              # 完整版本演化日志（V1 → v1.4）
├── EVAL_REPORT.md            # 基准测试结果
├── USAGE.md                  # 详细使用指南
├── README.md                 # 英文 README
└── README.zh-CN.md           # 本文件
```

## 依赖

- **bash 4+**（macOS：`brew install bash`）
- **Python 3.8+**（仅标准库——`sqlite3`、`ast`、`json`、`re`、`sys`、`datetime`、`pathlib`、`subprocess`）
- **Claude Code**（用于 skill 执行；hooks 需配置 settings.json）

零 pip 包。零 npm 包。无向量数据库。无 embedding。无外部 API。SQLite 是 Python 标准库。

## 贡献

详见 [docs/contributing.md](docs/contributing.md)，包含 skill 结构规范、eval 格式、PR checklist。

## 许可证

MIT——详见 [LICENSE](LICENSE)。

---

**Synapse Graph Skills (v1.4)**——图拓扑记忆，让你的 AI 助手知道你上周做了什么，不需要你再解释一遍。从 V1 的扁平文件、V2 的单体 Agent，到 v1.0 的图拓扑 + Skills，再到 v1.4 的 SQLite + 全栈链路 + AI 自主写入——每一次迭代都在解决同一个问题：**context 不应该随模块数爆炸，记忆不应该依赖人记住去记录。**
