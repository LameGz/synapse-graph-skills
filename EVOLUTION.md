# Synapse Graph Skills — 版本演化日志

> 记录从 V3（当前）到后续版本的关键架构决策、吸收的外部知识、以及每次迭代的"为什么"。

---

## V3.0.0 — 2026-05-21（当前版本）

四枚独立 Skill 首次发布：

- **synapse-graph-memory**：核心检索引擎，7 步决策树 + 三层渐进加载 + 受限 BFS
- **synapse-timeline**：只读时间线 & Open Issues 查询
- **synapse-daily-note**：一句话 NL → 记忆写入全管线
- **synapse-init**：冷启动向导，自动检测技术栈 & 模块边界

**存储层**：Markdown 节点（meta/*.md）+ MEMORY_MAP.json 倒排索引 + MEMORY_MAP.md 可读索引。全量重建。

**Hook 体系**：PreToolUse（pre-read-check + pre-modify-check）、PostToolUse（post-tool-use）、Stop（session-end）。

**已知问题**：generate_memory_map.sh 976 行过于臃肿；MAP 全量重建性能不随节点数扩展；drift 检测只在会话结束时报警；人必须手动写记忆否则图是空的。

---

## V3.1.0 ✅ — 已实现（增量 MAP + 源码锚点自动发现）2026-05-24

### 背景

V3.0 的 `generate_memory_map.sh` 每次会话结束都**全量重建** MEMORY_MAP——重新解析所有 meta/*.md、重建 tag 索引、重算关键词、重算亲和度。这在 30 个节点时还好，但如果项目膨胀到 100+ 节点，每次重建的成本就不可忽略了。

同时，现有 `init.sh` 扫描 src/ 后只生成空骨架 mod_*.md，Connection Points 完全靠人填——这降低了初始体验和长期维护率。

### 变更

**1. 增量 MAP 更新**

- `generate_memory_map.sh` 新增 `--changed <node1> <node2>` 参数
- 只更新指定节点的索引条目：tag count、keyword index、affinity matrix
- `synapse_note.sh` 自动传递修改的节点名给 `--changed`
- session-end hook 默认使用增量模式；`--full` 保留用于每周全量校验

**为什么不是完全增量**：会话结束时仍会做一次 `--changed` 覆盖不到的全局检查（orphans、cycles、dead links），但这一部分只需遍历节点名和 frontmatter，不需要重建 tag/keyword 索引，成本是 O(n) 而不是 O(n²)。

**2. 源码锚点自动预填**

- `init.sh` 新增 `--scan-depth <n>` 参数（默认 2 级目录）
- 扫描 src/ 时，用 Python `ast` 标准库解析 `.py` 文件，提取函数/类签名
- 对 `.ts/.tsx` 文件用正则提取 `export function/class/const`
- 对 `.go` 文件用正则提取 `func` 声明
- 自动写入 mod_*.md 的 Connection Points 区域，带上 `@ref` 锚点
- 覆盖率目标：常见后端语言 ≥ 60% 的公共接口被自动发现

**为什么用正则而不是 tree-sitter**：保持零依赖。Python `ast` 标准库已覆盖 Python 精确解析；JS/TS/Go 用正则做 best-effort，标注 `<!-- auto-detected, please verify -->` 让人审核。

### 吸收来源

来自 [codegraph](https://github.com/colbymchenry/codegraph) 的设计启发：
- 增量化思想（codegraph 的 sync 只重索引变更文件）
- 语言感知的符号提取（codegraph 的 tree-sitter 提取函数/类/方法签名）

### 影响范围

- `scripts/generate_memory_map.sh`：新增 `--changed` 路径
- `scripts/init.sh`：新增源码扫描阶段
- `scripts/synapse_note.sh`：传递 `--changed` 参数
- `scripts/hooks/session-end.sh`：改用增量模式 + 周度全量校验
- `references/node-spec.md`：新增 auto-detected Connection Point 格式说明

---

## V3.2.0 ✅ — 已实现（SQLite 索引层 + 实时 Stale 标记）2026-05-24

### 背景

V3.1 的 `generate_memory_map.sh` 虽然支持增量了，但底层仍然是 bash 脚本解析 JSON 和 grep 文本——tag 索引、关键词提取、亲和度计算这些事 SQLite 的 FTS5 + BM25 做得更快更准。

同时，V3.0/V3.1 的 drift 检测只在会话结束时报警——你在会话中途改了源码，meta/ 节点不会知道自己已经 "stale" 了，直到会话结束 hook 才告诉你。这个反馈周期太长。

### 设计原则：SQLite 是缓存，不是主存储

**关键决策：Markdown 文件永远是 source of truth。SQLite 是从 Markdown 重建的派生缓存。**

```
meta/*.md（人类可读写，git 可追踪）
    │
    └── generate_memory_map.sh ──→ .synapse/cache/memory.db（SQLite 缓存）
                                      │
                                      ├── FTS5 全文索引（替代 grep 搜索）
                                      ├── tag 索引（替代 bash 关联数组）
                                      ├── affinity matrix（替代 JSON 共现矩阵）
                                      └── BM25 排序（替代硬编码计分）
```

**为什么这样做**：
- Markdown 文件可以用任何编辑器手动改——这是 "轻量化" 的核心承诺
- SQLite 崩溃了？删掉 `.synapse/cache/`，跑一次 `generate_memory_map.sh --full` 就重建
- git 不用追踪二进制数据库文件（已在 `.gitignore` 中排除 `.synapse/cache/`）
- Python 3 自带 `sqlite3` 模块——**不增加任何 pip/npm 依赖**，仍然零外部依赖

### 变更

**1. SQLite 索引层**

- 新增 `.synapse/cache/memory.db`（在 `.gitignore` 中）
- `generate_memory_map.sh` 输出目标新增 `--db`：同时写入 MEMORY_MAP.json + SQLite
- 数据库 schema：

```sql
-- 节点表（从 meta/*.md frontmatter 派生）
CREATE TABLE nodes (
    id TEXT PRIMARY KEY,          -- e.g. "feat_payment"
    type TEXT NOT NULL,           -- mod_ | feat_ | proj_
    status TEXT NOT NULL,         -- in-progress | stable | archived
    summary TEXT NOT NULL,
    depends_on TEXT,              -- JSON array
    auto_linked TEXT,             -- JSON array
    tags TEXT,                    -- JSON array
    aliases TEXT,                 -- JSON array
    updated TEXT NOT NULL,        -- ISO date
    file_path TEXT NOT NULL,      -- meta/feat_payment.md
    line_count INTEGER NOT NULL
);

-- 全文索引
CREATE VIRTUAL TABLE nodes_fts USING fts5(
    id, summary, tags, aliases,
    content='nodes', content_rowid='rowid'
);

-- 边表（从 depends_on / auto_linked 派生）
CREATE TABLE edges (
    source TEXT NOT NULL,
    target TEXT NOT NULL,
    kind TEXT NOT NULL,           -- depends_on | auto_linked | blocks
    PRIMARY KEY (source, target, kind)
);

-- 共现追踪（用于 auto_linked 置信度计算）
CREATE TABLE cooccurrence (
    node_a TEXT NOT NULL,
    node_b TEXT NOT NULL,
    touch_count INTEGER DEFAULT 1,
    last_touch TEXT NOT NULL,
    PRIMARY KEY (node_a, node_b)
);

-- Stale 标记（由文件监控填充）
CREATE TABLE staleness (
    node_id TEXT PRIMARY KEY,
    stale_since TEXT NOT NULL,
    reason TEXT NOT NULL,         -- "source file changed: src/payment/routes.ts"
    affected_refs TEXT            -- JSON array of @ref anchors that may be stale
);
```

- `query_timeline.sh` 新增 `--db` 标志，优先走 SQLite 查询（O(log n) vs 原来 grep 的 O(n)）
- SKILL.md 决策树的 Layer 1（MAP triage）改为优先查 SQLite FTS5，fallback 到 MEMORY_MAP.md

**2. 轻量文件监控（实时 Stale 标记）**

- 新增 `scripts/watch.sh`（独立脚本，手动启动或 hook 自动触发）
- 基于 `inotifywait`（Linux）/ `fswatch`（macOS）/ PowerShell `FileSystemWatcher`（Windows）
- 监控范围：src/**/*.{ts,py,go,js,rs,java}（从 proj_*.md 的技术栈信息自动选择扩展名）
- 行为：源码文件变更时，在 `staleness` 表中标记所有引用该文件的 meta/ 节点
- 会话中 Claude Code 查询时，SKILL.md 的 Layer 1 就能读到 "⚠ 3 nodes stale"——**不等会话结束**
- `watch.sh` 不是常驻后台进程——它是一个 **cron-compatible 轮询脚本**，间隔 30 秒轻扫一次

**轮询 vs 常驻的选择**：常驻进程需要进程管理（重启、崩溃恢复、端口占用），对个人开发者太重。30 秒轮询用 bash 的 `sleep 30; loop` 就够了，Claude Code 会话期间 AI 可以主动调用 `watch.sh --once` 做一次快照检查。

**3. 落地影响**

- `generate_memory_map.sh` 从 ~976 行降到 ~600 行（索引逻辑移到 SQLite）
- tag/keyword 搜索从 bash `grep` + `jq` 变成 `SELECT ... FROM nodes_fts WHERE nodes_fts MATCH ? ORDER BY bm25(nodes_fts, 0, 20, 5, 1, 2)` ——更准、更快
- 亲和度计算从 bash 关联数组 + JSON 写入变成 SQLite `cooccurrence` 表 UPDATE + SELECT
- `doctor.sh` 查询 dead links / orphans 从 bash 循环变成 SQL JOIN 一行查询

### 为什么这不违背"轻量化只做 Skills"

| 约束 | V3.0 | V3.2 |
|------|------|------|
| pip/npm 依赖 | 0 | 0（Python `sqlite3` 是标准库） |
| 外部进程依赖 | bash 4 + Python 3 | bash 4 + Python 3（不变） |
| 主存储可手改 | Markdown 文件 | Markdown 文件（不变） |
| 可删除重建 | 删 MEMORY_MAP.* → 跑脚本 | 删 `.synapse/cache/` → 跑脚本 |
| 新增二进制文件 | 无 | `.synapse/cache/memory.db`（gitignore） |
| 新增后台进程 | 无 | 无（watch.sh 是轮询，不是 daemon） |

底线：**Skills 的"轻"不在于是不是用了数据库，而在于用户不需要装任何新东西。** Python 的 `sqlite3` 跟 `json`、`re` 一样——开箱即用，但功能强一个数量级。

### 吸收来源

- [codegraph](https://github.com/colbymchenry/codegraph) 的 SQLite + FTS5 + BM25 全文搜索架构
- codegraph 的 OS 原生文件监控 + 增量同步机制
- codegraph 的 staleness/invalidation 思路（codegraph 用 content_hash 对比检测文件变更）

### 影响范围

- `scripts/generate_memory_map.sh`：重大重构，新增 `--db` 输出
- `scripts/watch.sh`：**新文件**
- `scripts/query_timeline.sh`：新增 SQLite 优先路径
- `scripts/doctor.sh`：改用 SQL JOIN 查询
- `scripts/hooks/session-end.sh`：增量 MAP + SQLite 更新
- `SKILL.md`（synapse-graph-memory）：Layer 1 优先查 SQLite
- `.gitignore`：新增 `.synapse/cache/`

---

## V3.3.0 ✅ — 已实现（单项目全栈记忆模式）2026-05-24

> 完整设计文档：[docs/superpowers/specs/2026-05-24-fullstack-memory-design.md](docs/superpowers/specs/2026-05-24-fullstack-memory-design.md)

### 背景

V3.0 的四枚独立 Skill + 多项目架构解决的是"一个人维护 5 个项目，切回来全忘了"的问题。但有一类用户需求更简单：**只维护 1-2 个项目，想要深度全栈记忆**——从数据库表结构 → API 路由 → 前端组件 → 部署配置，记住一整个项目的完整技术栈。

### 核心决策：路线 B —— 引擎扩展，不建新 Skill

经过 brainstorming 讨论（2026-05-24），否决了新建 `synapse-mono` skill 的方案（路线 A）。选择**在 `synapse-graph-memory` 核心引擎中扩展节点类型和初始化深度**。原因：

- 避免代码分叉——底层 BFS、写入管线、时间线查询完全不变
- 全栈只是"多了一种初始化深度 + 多了四种节点类型"
- `synapse-init/scripts/init.sh` 改为薄 wrapper（357 行 → 15 行），透传 `--fullstack` 到核心引擎
- 用户装完 `synapse-graph-memory` 就能用全栈模式，不需要额外安装

### 新增四种节点类型（粒度：混合策略 D）

| 类型 | 前缀 | 粒度 | 中小型项目估算 |
|------|------|------|-------------|
| database_table | `db_` | 一张表一个节点 | 10-30 |
| api_endpoint_group | `api_` | 一个 router 文件一组 endpoint | 5-15 |
| ui_page | `ui_` | 一个页面（含 Tab 级例外） | 5-20 |
| deployment | `dep_` | 一个部署单元（≤5 个） | 2-5 |

**四个补丁规则**（brainstorming 中确认的边界条件修正）：

1. **ui_ Tab 级例外**：当一个页面聚合了 3 个以上互不相关的业务域，且拆分后 `depends_on` 重叠度 < 30%，允许拆为 `ui_admin-user-tab`、`ui_admin-finance-tab`
2. **db_ 只列骨架字段**：Columns 表只列参与业务逻辑判断的字段（被 WHERE/JOIN/IF 引用），纯审计/时间戳/备注字段省略
3. **双向边只存正向**：`depends_on` YAML 是唯一写入点；反向边（`blocks`）由引擎自动计算，AI 只看不写。被动方 Markdown 中硬编码反向依赖时 `post-tool-use hook` 直接报错
4. **dep_ 是终端锚点**：不描述"怎么部署"，只记录"哪些东西在一个网络里互通，通过什么环境变量连起来"（Environment Bridges）

### 全栈初始化扫描（init.sh --fullstack）

四层 best-effort 扫描，只生成骨架（id/type/source/summary/tags），不填跨类型边：

| 层级 | 扫描目标 | 检测手段 | 准确率 |
|------|---------|---------|--------|
| 1 | DB Schema | Prisma / Django models / SQL / Go ent / TypeORM 正则提取 | 60-100% |
| 2 | API Routes | FastAPI / Express / Next.js / Gin / Axum 路由正则 | 70-95% |
| 3 | UI Pages | React pages / Vue views / SvelteKit 文件名 + 目录结构 | 55-65% |
| 4 | Deployment | Dockerfile / compose / k8s / .env.example | 70-100% |

Layer 3（UI）最不准——只生成节点骨架，不推断 depends_on。跨类型边由后续 `suggest_edges.sh` 和人补充。

### 链路追踪查询（BFS 引擎：状态机 + 回溯剪枝）

新增第三种 BFS 遍历模式。核心修正（brainstorming 中确认）：**不是简单的"当前 hop 过滤类型"，而是状态机序列约束 + 终态回溯剪枝**。

| 特性 | 实现 |
|------|------|
| 意图识别 | "支付链路怎么通的"、"这个按钮点下去经过了哪些接口" |
| BFS 方向 | 正向（沿 depends_on） |
| 类型约束 | 状态机序列 `ui → api → db → dep`（允许多跳同类型 + 跳级） |
| 参数 | depth≤4, width≤3, `--traverse-types ui,api,db,dep` |
| 终点条件 | 路径必须落在序列终态 |
| 剪枝 | 回溯剃掉未到终点的死胡同分支；零条到达时降级为"部分链路" + ⚠ 告警 |

`bfs_trace()` 是 `generate_memory_map.sh` 中的独立函数，不改现有 BFS 路径。

### 文件变更清单

**修改**：`SKILL.md`（+链路追踪意图）、`references/node-spec.md`（+全栈类型引用）、`references/critical-rules.md`（+四个补丁）、`generate_memory_map.sh`（+bfs_trace）、`init.sh`（+--fullstack + 四层扫描）、`doctor.sh`（+全栈校验）、`synapse-init/scripts/init.sh`（→薄 wrapper）

**新建**：`references/fullstack-node-spec.md`（独立全栈节点规范，按需加载）

**不改**：`synapse-timeline`、`synapse-daily-note`、`suggest_edges.sh`、`ingest_memory.py`、`apply_memory_proposal.py`

### 用户安装组合

```
组合一：单项目深度全栈
  安装: synapse-graph-memory
  初始化: /初始化记忆 → init.sh --fullstack 自动触发
  日常: /支付链路怎么通的  /改 orders 表会影响哪些页面

组合二：多项目模块依赖（V3.0 原有，不变）
  安装: synapse-graph-memory + timeline + daily-note + init
  初始化: /初始化记忆 → init.sh（现有逻辑）
  日常: /改X会影响什么  /最近改了啥  /记录一下
```

共用同一套引擎——区别仅在于 init 是否传 `--fullstack`。不传时行为与 V3.0 完全一致。

---

## V3.4.0 — 计划中（AI 自主记忆写入）

### 背景：为什么"人得写"是问题

Post-V3.3，synapse 的图拓扑引擎已经完整：SQLite 缓存、增量 MAP、4 种全栈节点、链路追踪 BFS。但**写入仍然依赖人的自觉**——你必须在 Claude Code 里主动说 `/记录一下`，记忆才会更新。忘了就是忘了。

实际会话中，AI 本来就知道一切：
- 你刚才改了哪个文件（PostToolUse hook 已捕获）
- 你在对话里做了什么决定（"就用 Redis 吧不用 RabbitMQ"）
- 当前话题聚焦在哪个模块/功能上（上下文中可推断）

缺的不是信息，是**一套让 AI 在对话结束时自动判断"哪些值得记、怎么记"的行为规则**。

### 核心思路：从"人触发"变成"AI 自主 + 人确认"

```
旧：你意识到"该记了" → 你手动 /记录一下 → AI 执行
新：对话自然发生 → AI 持续观察 → 会话结束时自动生成摘要 → 你扫一眼确认 / 自动写入
```

两种模式配合：

| 模式 | 触发条件 | 行为 |
|------|---------|------|
| **静默自动写（默认）** | 源码文件变更 + AI 能推断出"做了什么" | 会话结束时自动生成 proposal，**不打断**，人扫一眼 diff 确认 |
| **主动询问** | 无法判断的决策（"为什么选这个"）、跨模块影响不确定 | AI 在对话中自然发问："我刚才记录了你把 orders 表 status 扩展到了 5 态，对吗？" |

### 触发判断：什么值得自动记录？

AI 在会话中持续观察以下信号，每个信号带着"置信度 + 应该写入的目标节点"：

| 信号 | 来源 | 置信度 | 写入目标 |
|------|------|--------|---------|
| 文件被写入 | PostToolUse hook | 高（90%） | 对应 meta/ 节点 | Change Log |
| 人明确说"决定了" / "就这个方案" | 对话文本匹配 | 高（85%） | 对应模块节点 | Key Decisions |
| 接口签名变更 | `source_scan.py` 重新扫描 | 高（95%） | 对应 api_/mod_ 节点 | Connection Points |
| 新文件创建 | PostToolUse hook | 中（60%） | 可能的新节点 | 建议创建新 meta/ 节点 |
| 人说"还差" / "还没做" / "待确认" | 对话文本匹配 | 中（70%） | 对应节点 | Open Issues |
| 话题切换 | 关键词聚类 | 低（40%） | 上一个话题对应节点 | 建议记录"今天做到这" |
| 长时间讨论某个模块（>10 条消息） | 话题持续度 | 低（50%） | 该模块节点 | Change Log（"花了时间但可能没改代码"） |

### 实现方案

核心改动在三个地方：

**1. SKILL.md：新增 AI 自主写入行为规则**

在 SKILL.md 中新增一节，不是告诉人怎么用，是告诉 AI 自己该怎么做：

```markdown
## Autonomous Memory Writing (V3.4)

During conversation, YOU are responsible for keeping the memory graph up to date.
Do NOT wait for the user to say "/记录一下". Observe the conversation and act.

### When to write (auto-detect)

- **File changes**: After editing source files, infer what was done and update
  the corresponding meta/*.md Change Log.
- **Decisions**: When the user says "we'll use X" or "let's go with Y",
  record it as a Key Decision in the relevant node.
- **Blocked items**: When the user says "still need to" or "not yet",
  add to Open Issues.
- **New modules**: When a new directory/pattern emerges, suggest creating
  a new meta/ node via init.sh pattern detection.

### How to write

Call the standard pipeline — don't hand-edit nodes directly:
  synapse_note.sh --text "..." --edge-mode auto --yes

### When to ask (ambiguity)

Ask one brief confirmation before writing if:
- The target module is unclear (file touches 3 modules)
- The change is a design decision with long-term impact
- The user might disagree with the inference

Otherwise, write silently. Session-end hook will show the diff.
```

**2. session-end hook：自动提案 → 确认 → 写入**

在现有 hook 的末尾新增一段：

```
会话结束时：
  1. 收集本次会话中 AI 自动记录的 proposal（.synapse/auto-proposals/*.json）
  2. 展示合并后的变更摘要（哪些节点新增/修改了什么）
  3. 如果只有低置信度的自动记录（<70%），标注 ⚠ 请确认
  4. 高置信度的自动记录直接 apply，用户在下次会话可以 git diff meta/ 回看
```

**3. 新增 `auto_observe.py`：对话信号提取器**

一个 Python 脚本，从会话上下文中提取"值得记录"的信号：

```
输入：git diff（文件变更）+ 对话摘要（从 Claude 会话上下文中提取）
输出：JSON proposal，包含：
  - target_node: 推断的目标节点
  - change_type: change_log | key_decision | open_issue | connection_point
  - content: 自动生成的 Change Log 条目
  - confidence: 0-100
  - evidence: "为什么 AI 认为这值得记"（调试用）
```

不依赖外部 API —— 只用正则 + 关键词匹配 + git diff 解析。它是一个**建议引擎**，不是一个决策引擎。

### 用户感知

**改动前**：人必须记住说 `/记录一下`，不说就丢。忘了 3 天回来，AI 一脸茫然。

**改动后**：正常对话。AI 自己知道什么时候该记。会话结束时：

```
🧠 Synapse Session End

📝 Auto-Recorded:
  ✓ feat_login: 响应式断点 768→640px (Change Log)
  ✓ mod_design-system: 新增 <MobileNav> 组件 (Change Log + Connection Points)
  ⚠ db_orders: status 5 态扩展（推断自对话，请确认）

  → 2 条已自动写入，1 条待确认。git diff meta/ 查看详情。
```

人什么都不用做。想确认就点进文件看，不想确认就继续写代码。下次会话 AI 自动加载最新记忆。

### 与 codegraph 在此维度的比较

codegraph 不需要这个——它的图是 tree-sitter 自动解析的，不存在"人忘了写"。但也因此它**无法记录任何工程决策、进度、待办**——那些不在 AST 里。

synapse 3.4 做完后：**代码变更自动追踪（像 codegraph）+ 工程决策半自动记录（synapse 擅长的）。** 这就是"字典 + 笔记"的合体。

### 影响范围

- `SKILL.md`：新增 Autonomous Memory Writing 节
- `session-end hook`：新增自动提案收集 + 确认流程
- `auto_observe.py`：**新文件**，对话信号提取器
- `synapse_note.sh`：支持 `--auto-confirm` 跳过交互

### 风险

- AI 可能"过度记录"（每改一行都记）→ 用置信度阈值 + 去重
- AI 可能推断错误（"你改了 auth.py → 你一定在做登录"——实际你在修 token 刷新）→ 低置信度标 ⚠ 确认
- 会话上下文可能不够 → 依赖 git diff 做硬证据，对话做软证据

### 语言感知的 Connection Points 验证

目前 session-end hook 验证 @ref 锚点的方式是"检查文件+行号是否存在"——它验证结构，不验证语义。如果 `src/payment/routes.ts:45` 行号因为上面插了 import 而漂移了，它报 false positive；如果函数签名变了但行号没变，它漏报。

远期方案：
- Python 项目用 `ast` 标准库解析，精确验证函数签名是否与 Connection Points 中记录的一致
- TS/JS 项目用正则做 best-effort，标注置信度
- Go 项目用正则提取 func 声明
- 所有语言：如果行号找不到，尝试按函数名搜索（可能是代码移动了）

### 测试影响追踪

吸收 codegraph 的 `codegraph affected` 思路——pre-modify-check hook 不仅能告诉你"改 src/payment/routes.ts 会影响 meta/ 中哪些节点"，还能告诉你"哪些测试文件 import 了这个模块"。这对 TDD 流程的开发者价值很大。

### 链路可视化

在 `visualize.py`（当前只输出 Mermaid）的基础上，增加：
- 端到端链路高亮：选择一条完整链路（UI → API → DB），在图中高亮路径
- Stale 节点红色标记
- 交互式 HTML 输出（可选，不强制）

---

## 演化图谱总览

```
V1 (2024)               V2 (2025 初)            V3 (2025.05) ← 当前
────────────────        ────────────────         ──────────────────────────
形态：单脚本             形态：单体 Agent 记忆     形态：四枚独立 Skill
存储：扁片 Markdown      存储：扁片 Markdown       存储：图拓扑 + 显式边
检索：grep 全文          检索：关键词 + 摘要       检索：三层渐进 + 受限 BFS
边：无                   边：隐式（命名约定）       边：显式 depends_on/blocks
一致性：人肉             一致性：人肉              一致性：Hook 运行时强制
规模：~10 节点           规模：~15 节点             规模：30+ 节点（常数级）

        V3.1 ✅                V3.2 ✅                V3.3 ✅                V3.4 (计划)
        ────────────           ────────────           ──────────────────────  ──────────────────────────
        增量 MAP 更新           SQLite 缓存层           引擎扩展 4 种全栈节点    AI 自主记忆写入
        源码锚点预填            实时 Stale 标记         BFS 状态机 + 回溯剪枝    静默自动写 + 主动询问
        source_scan.py         watch.sh 轮询           init.sh --fullstack     auto_observe.py
        session-end 周度        FTS5 全文索引           db_/api_/ui_/dep_       会话结束自动提案
                                db_init/db_index        薄 wrapper              干掉"人得写"
```

---

*演化日志由项目作者维护。每个计划版本的具体排期取决于社区反馈和实际需求验证。*
