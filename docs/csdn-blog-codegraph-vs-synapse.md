# Synapse Graph Skills v1.4 发布：从 codegraph 偷师，用 SQLite + AI 自主记忆给全栈个体户的"第二大脑"

> 如果你的 AI Agent 是你唯一的"同事"，它忘了一次，你就得从头解释一遍。codegraph 用 MCP 解决代码探索的效率问题，synapse 用 Skills 解决工程记忆的断层问题。这两个项目一个像字典，一个像笔记——而我把字典的索引技术装进了笔记里。

---

## 背景：codegraph 是什么，好在哪

[codegraph](https://github.com/colbymchenry/codegraph) 是 Colby McHenry 开发的预索引代码知识图谱，9.6k star，MCP Server 形态。它用 tree-sitter 解析 20+ 种语言的 AST，把所有函数/类/方法符号和调用关系写入 SQLite FTS5，然后通过 8 个 MCP 工具暴露给 Claude Code。

说人话：以前 AI 探索代码要 `grep` + `glob` + `Read` 反复踩坑，现在 `codegraph_search("payment")` 一个调用回来所有相关符号。

**基准数据**：7 个项目实测，平均省 35% 费用、减少 70% 工具调用。VS Code 仓库（~10k 文件）上省了 73% token。

**codegraph 的架构三板斧**：

1. **SQLite + FTS5 + BM25** — 全文搜索比 grep 快两个数量级，BM25 排序比字符串匹配准
2. **OS 原生文件监控** — FSEvents / inotify / ReadDirectoryChangesW，2 秒 debounce，代码改了什么图自动同步
3. **MCP Server** — stdio JSON-RPC，8 个工具，跨 Agent 通用（Claude Code / Cursor / Codex / OpenCode 都能用）

**但 codegraph 有一个它永远绕不过去的硬伤**：它只能告诉你代码**是什么**，永远回答不了**为什么**。为什么选 Redis 不选 RabbitMQ？支付回调的幂等为什么用 `Idempotency-Key` 而不是数据库锁？这些不在 AST 里。

---

## 本质区别：图的节点代表什么

很多人说"这两个项目都是图"。对，但图的**节点语义**完全不同：

| | codegraph | synapse-graph-skills |
|---|---|---|
| **一个节点** | 一个代码符号（函数、类、方法） | 一个工程知识单元（模块状态、接口契约、设计决策） |
| **一条边** | 编译器级别的事实（calls / imports / inherits） | 语义级别的依赖（"这个模块坏了那个也会坏"） |
| **图的来源** | tree-sitter 全自动解析，100% 客观 | 人写 + init.sh 扫描骨架 + AI 建议边 |
| **回答的问题** | "这个函数在哪被调用了？" | "支付做得怎么样了？""改 orders 表会影响哪些页面？" |
| **空项目可用** | 不可——没有源码就没有图 | 可——人可以写节点记录"为什么选这个方案" |

**打个比方**：codegraph 像是对一座城市做了精确的 3D 扫描——每栋楼多高、门牌号多少、路怎么通，全自动生成，分毫不差。synapse 像是你作为一个在这座城市生活过的人写的备忘录——"这栋楼后面那条小巷是近道，那个路口高峰期必堵，这家店老板周二不开门"。

---

## MCP vs Skills：两种集成哲学

这也是两个项目最外层的技术分歧：

| | codegraph (MCP) | synapse (Skills) |
|---|---|---|
| **安装** | `npx @colbymchenry/codegraph`（需 Node.js） | `cp -r synapse-* ~/.claude/skills/`（需 bash + Python） |
| **跨 Agent** | Claude Code / Cursor / Codex / OpenCode | Claude Code only |
| **轻量化** | Node.js 运行时 + npm 全局包 + MCP 进程管理 | 零 pip/npm 依赖，Python stdlib only |
| **数据可手改** | 不可——SQLite 是唯一真相源 | 可——Markdown 文件是 source of truth，SQLite 是缓存 |
| **协议执行** | MCP 工具调用（AI 自己决定什么时候调） | Skill + Hook（PreToolUse 拦截 + Stop 强制校验） |

**为什么我选了 Skills 而不是 MCP？**

目标用户是**全栈个体户**——一个人维护 5 个项目，Claude Code 是唯一同事。MCP 的跨 Agent 能力对他没用（他不用 Cursor），但 MCP 的代价（需要 Node.js、需要独立进程、SQLite 无法手改）他全得承担。

Skills 的哲学是"零安装、零进程、文件即数据"——你可以在 Vim 里打开 `meta/feat_payment.md` 直接改一行，改了之后 `generate_memory_map.sh` 自动重建索引。这种"紧急情况手改文件"的逃生舱，MCP 给不了。

---

## 从 codegraph 吸收了三个关键技术

codegraph 在三个维度上做得太好了，不学是傻子。v1.1-v1.2 直接把这三个思路搬了过来，但适配到了 Skills 体系里：

### 1. SQLite FTS5 + BM25（v1.2）

codegraph 用 SQLite 存所有符号，FTS5 做全文搜索。synapse v1.0 的 `generate_memory_map.sh` 用 bash grep + jq 解析 JSON——976 行，tag 查找走线性扫描，关键词搜索靠正则，性能在 30+ 节点后明显下降。

v1.2 新增了：

- **`db_init.py`**：建库脚本，5 张表（`nodes` / `edges` / `cooccurrence` / `staleness` / `nodes_fts`），FTS5 虚拟表做全文索引
- **`db_index.py`**：从 Markdown 节点文件读 frontmatter，写入 SQLite，支持 `--full` 和 `--changed <id>` 两种模式
- **`generate_memory_map.sh --db`**：双输出——MEMORY_MAP.json + SQLite 缓存一锅出

**关键设计**：SQLite 是缓存，不是主存储。Markdown 文件永远是 source of truth。删掉 `.synapse/cache/memory.db`，跑一次 `--full` 就能重建。Python 的 `sqlite3` 是标准库——不增加任何 pip 依赖。

**实测**（30 节点 fixture）：

| 操作 | v1.0 (bash+grep) | v1.2 (SQLite FTS5) |
|------|-----------------|-------------------|
| Tag 查找 | ~120ms | ~5ms |
| 全文搜索 | ~200ms | ~5ms |
| Doctor 健康检查 | ~350ms | ~120ms |
| 全量 MAP 重建 | ~2.1s | ~1.6s（含 SQLite 同步） |

### 2. 文件监控 + 实时 Stale 标记（v1.2）

codegraph 用 OS 原生文件事件做增量同步，代码改了图 2 秒内自动更新。

synapse v1.0 的 drift 检测只在会话结束时跑——你中途改了源码，meta/ 节点要等会话结束才知道自己"过时"了。v1.2 新增了 `watch.sh`：

- 30 秒轮询（不是 daemon，不是后台进程——一个 bash `sleep 30` 循环）
- 比较源码文件的 `mtime + size` hash 和上次快照
- 变动时在 SQLite `staleness` 表中标记受影响的 meta/ 节点
- 会话中 AI 查询时，Layer 1 MAP 就能读到 "⚠ 3 nodes stale"

**为什么不用常驻进程？** 因为目标用户不需要。30 秒轮询是 cron-compatible 的，AI 也能主动调 `watch.sh --once`。

### 3. 源码锚点自动提取（v1.1）

codegraph 用 tree-sitter 解析 20+ 语言的完整 AST。synapse v1.1 新增了 `source_scan.py`——不需要 tree-sitter，只用 Python `ast` 标准库解析 Python，用正则做 JS/TS/Go 的 best-effort：

- 提取函数名、签名、装饰器、行号
- 生成 `<!-- @ref: src/payment/routes.ts:45 -->` 锚点
- 16 种文件→节点映射规则（如 `src/routes/payment.py` → `api_payment-routes`）
- 集成到 `init.sh`，冷启动时自动跑

没有 tree-sitter 的覆盖率，但保持了**零依赖**——这在"轻量化"的约束下，是一个刻意的取舍。

---

## v1.3：全栈记忆——从"改哪个模块会炸"到"这条链路怎么通的"

v1.0 只有 3 种节点（`mod_` 模块 / `feat_` 功能 / `proj_` 项目总览）。对"改 X 会影响什么"这种问题够了。但全栈开发者问的是另一个维度的问题——"支付链路从前端按钮到数据库事务是怎么连的？"

v1.3 新增了 4 种全栈节点：

| 类型 | 前缀 | 粒度 | 示例 |
|------|------|------|------|
| 数据库表 | `db_` | 一张表一个节点 | `db_orders` |
| API 端点组 | `api_` | 一个 router 文件一组 | `api_payment-routes` |
| UI 页面 | `ui_` | 一个页面（含 Tab 例外） | `ui_checkout-page` |
| 部署单元 | `dep_` | 一个部署单位（≤5 个） | `dep_container-config` |

**链路追踪 BFS**（`bfs_trace()`）：状态机序列 `ui → api → db → dep`，允许多跳同类型（微服务网关：`api_A → api_B`）、允许跳级（`ui → api → dep`），回溯剪枝剃掉未到终点的死胡同。

```bash
$ generate_memory_map.sh --trace-from ui_checkout-page --traverse-types ui,api,db,dep
{
  "paths": [
    ["ui_checkout-page", "api_payment-routes", "db_orders", "dep_container-config"],
    ["ui_checkout-page", "api_cart-routes", "db_cart-items"]
  ],
  "partial": false
}
```

**`init.sh --fullstack`**：冷启动时四层扫描——Prisma/SQL schema → API 路由 → UI 页面目录 → Dockerfile/k8s/.env，一套命令生成全部骨架节点。

---

## v1.4：干掉"人得写"——AI 自主记忆写入

v1.0-v1.3 解决了**引擎能力**问题——图的存储、查询、链路追踪都完备了。但写入仍然靠人——你必须在 Claude Code 里主动说 `/记录一下`，记忆才会更新。

**这就是惰性天花板**：连续三天忙起来没记，图不会崩（`watch.sh` 会标记 stale），但**工程记忆的价值会衰减**——AI 知道表结构变了，但不知道为什么变、还有什么没做。

v1.4 的核心变化：**AI 在对话中自主观察，会话结束时自动写入**。

```
旧：你意识到"该记了" → 手动 /记录一下 → AI 执行
新：对话自然发生 → AI 观察 → 会话结束自动提案 → 高置信度静默写入
```

三个组件：

- **`auto_observe.py`**：对话信号提取器。从 git diff + 对话文本（中英文正则）中提取"值得记录"的信号，给每个信号标注置信度：git diff 变更 → 90%、对话中"决定了" → 85%、"还差/还没做" → 70%。输出 JSON proposal，包含 `target_node` / `change_type` / `content` / `confidence` / `evidence`。

- **`synapse_note.sh --auto-confirm`**：静默写入模式。AI 调这个标志，管线全程不弹交互提示。

- **`session-end hook` 增强**：每次会话结束自动收集所有 proposal，≥70% 置信度的自动 apply，<70% 的展示待确认列表：

```
🧠 Synapse Session End

📝 Auto-Recorded:
  ✓ api_payment-routes: 新增 API 端点 POST /callback (95%)
  ✓ feat_login: 响应式断点 768→640px (90%)

⚠  Needs Review:
  1. [key_decision] 决定: Redis 做支付状态缓存
     confidence: 85% | target: mod_payment
```

---

## v1.0 → v1.4 总览

| 版本 | 核心 | 关键文件 |
|------|------|---------|
| v1.0 | 图拓扑 + 三层渐进加载 + Hook 强制 | 11 scripts, 4 hooks |
| v1.1 | 增量 MAP + 源码锚点预填 | `source_scan.py`, `--changed` |
| v1.2 | SQLite FTS5 + 实时 Stale | `db_init.py`, `db_index.py`, `watch.sh` |
| v1.3 | 全栈 7 种节点 + 链路追踪 BFS | `bfs_trace()`, `--fullstack`, `fullstack-node-spec.md` |
| v1.4 | AI 自主记忆写入 | `auto_observe.py`, `--auto-confirm`, session-end 自动分流 |

**仓库**：[github.com/LameGz/synapse-graph-skills](https://github.com/LameGz/synapse-graph-skills)

---

## 结论：到底该用哪个？

这是我最常被问的问题。答案取决于你的场景：

**如果你现在就要装一个、马上见效**：codegraph。全自动，零维护，token 节省是客观可量化的。9.6k star 不是白来的。

**如果你的项目已经复杂到"改一个模块经常意外炸掉别的模块"，或者你受够了每次切项目回来 AI 一脸茫然**：synapse。它的记忆不是代码索引，是工程笔记——记录进度、决策、待办、链路依赖。

**理论上最强的组合**：codegraph 当底层（解析代码结构），synapse 当上层（记录设计意图）。synapse 的 `@ref` 锚点如果能直接引用 codegraph 的符号 ID——"这个设计决策关联到 `PaymentService.refund()` 这个函数"——那就是一个既有事实又有理解力的完整系统。

但这需要有人做桥。目前还没有。

---

*本文由 Synapse Graph Skills 作者撰写。v1.4 于 2026-05-24 发布。欢迎转载，注明出处即可。*

**GitHub**：[https://github.com/LameGz/synapse-graph-skills](https://github.com/LameGz/synapse-graph-skills)
