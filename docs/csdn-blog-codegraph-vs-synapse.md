# Synapse v1.4：站在 codegraph 肩膀上，给全栈个体户的轻量级"第二大脑"

> 先感谢 [Colby McHenry](https://github.com/colbymchenry) 和他的 [codegraph](https://github.com/colbymchenry/codegraph)。没有他的架构设计，synapse 的 SQLite 索引、增量同步、stale 检测不会这么快落地。本文讲的是：在 codegraph 的优秀地基上，我针对一个不同的用户场景做了什么不同的选择。

---

## 一、先讲清楚：codegraph 已经非常好了，为什么我还要再造一个轮子？

codegraph 解决了一个真问题。在没有它之前，Claude Code 探索代码要反复 `grep` → `glob` → `Read`，每次探索都烧掉上千 token。codegraph 用 tree-sitter 预解析 20+ 语言的 AST，把所有符号和调用关系存进 SQLite FTS5，一次 `codegraph_search("payment")` 就能拿到所有相关函数。

**它的效果是经过验证的**：7 个项目实测，平均省 35% 费用、减少 70% 工具调用。VS Code 仓库（~10k 文件）上省了 73% token。9.6k star 不是白来的。

但如果你的日常是这样的，codegraph 只能解决前半段：

```
周一：给 SaaS 产品 A 接好支付宝支付回调，写了 200 行后端逻辑
周二：切到客户项目 B，改 Landing Page 的响应式布局
周三：项目 B 的服务器崩了，紧急修了一整天
周四：回到产品 A，打开终端——
      你看着 Claude Code 问："支付做得怎么样了？"
      AI 说：让我看看代码……
      然后用了 20 分钟、烧了 8000 token 才把上周的上下文拼回来
```

**codegraph 能告诉 AI 哪个文件定义了 `payment_callback` 函数。但它回答不了这些问题**：

- 支付集成做到什么程度了？还差哪些接口没接？
- 当时为什么选支付宝 PC 扫码而不是 H5 支付？
- 回调接口为什么用 `Idempotency-Key` 做幂等而不是数据库锁？
- 改 `orders` 表的 `status` 字段会影响前端哪些页面？

这些答案**不在 AST 里**。codegraph 扫描了整座城市，知道每条路怎么走、每栋楼多高，但它不知道你上周二为什么在这条路上绕了三圈、以及那个路口的红绿灯最近坏了。

这就是 synapse 要解决的问题。它不是一个更好的 codegraph——它是**站在 codegraph 肩膀上、针对不同场景的另一种工具**。

---

## 二、核心差异：一个节点的定义

两个项目都用"图"来描述代码和项目。但节点的语义完全不同：

| | codegraph | synapse |
|---|---|---|
| **一个节点** | 一个代码符号（函数、类、方法、接口） | 一个工程知识单元（模块进度、接口契约、设计决策、待办） |
| **一条边** | 编译器级别的事实：calls / imports / inherits | 语义级别的依赖："这个模块坏了那个功能也会炸" |
| **图的来源** | tree-sitter 全自动解析，100% 客观 | 自动扫描骨架 + AI 建议 + 人确认（Markdown 可手改） |
| **回答的问题** | `PaymentService.refund()` 在哪被调用了？ | 支付做得怎么样了？改 orders 表会影响哪些页面？ |
| **安装即用** | 是，不需要人写任何东西 | 需要人在使用中逐步完善（v1.4 后 AI 会帮你写大部分） |

**打一个不太精确但好理解的比方**：codegraph 是代码的 Google Maps——自动测绘，精确到门牌号。synapse 是你在这座城市居住三个月后写的笔记——哪条巷子能抄近道，哪个路口必堵，哪家店周二休息。

---

## 三、量化一下：在什么场景下 synapse 比 codegraph 更对路

为了不空谈，我用一个真实的全栈个体户日常量化差距。

### 场景：周四早上，切回三天没碰的项目

你的项目有 30 个模块（15 张数据库表、8 组 API 路由、10 个前端页面、3 个部署单元）。

| 你想知道的事 | 只用 codegraph | 加上 synapse |
|-------------|---------------|-------------|
| 支付功能做到什么程度了？ | AI 需要 Read 15-20 个文件，推断进度 → ~5000 token，可能不准确 | 读 `MEMORY_MAP.md` 摘要 → ~200 token，精确 |
| 改 `orders` 表会影响什么？ | `codegraph_impact("orders")` 返回所有调用者 → ~1000 token，但只有代码调用链 | 查 `blocks` 反向边 → 直接拿到 `feat_payment`, `feat_invoice`, `feat_report`，含人工标注的影响说明 → ~500 token |
| 支付链路怎么通的？ | AI 需要自己拼：追踪 `ui_pay → api_payment → db_orders` → 多次工具调用 | `bfs_trace` 一次返回完整链路，含部署层 |
| 上次为什么选了这个方案？ | ❌ 代码不会告诉你 | `Key Decisions` 里写了："2026-05-20 选了支付宝 PC 扫码而非 H5，因为目标用户主要在桌面端" |
| 还有哪些没做完？ | ❌ 只能从 TODO 注释推断 | `Open Issues` 里写着："退款后是否允许重新支付？待产品确认" |

**token 节省**：上面的五个问题，纯 codegraph 方案大约需要 8000-12000 token 才能拼凑出答案（AI 需要反复 Read + 推断）。synapse 的三层渐进加载把需要的信息精确加载到 1500-3000 token——**省 60-75%**。

但这不是一个"谁更好"的数字。codegraph 省 token 是在代码探索阶段——"这个函数在哪？这个类谁继承的？"这些问题上 codegraph 比 grep 快 40 倍。synapse 省 token 是在**会话恢复**阶段——"上次做到哪了？为什么会这么设计？"这些问题 codegraph 从根本上就无法回答。

**两者解决的是不同环节的 token 浪费**——前段的代码探索（codegraph 擅长）+ 后段的工程上下文恢复（synapse 擅长）。

---

## 四、站在巨人肩上：从 codegraph 的架构设计中吸收了三个关键思路

codegraph 的架构设计非常干净，三项技术决策直接影响了 synapse v1.1-v1.2 的方向。这里必须给原作者 Colby McHenry 充分的 credit。

### 学到的第一点：SQLite FTS5 做索引层（v1.2）

codegraph 的 SQLite schema 设计得非常好——`nodes` 表存符号，`edges` 表存关系，每条边标注 provenance（`tree-sitter` vs `heuristic` vs `scip`）和 confidence。这个"信任信号"的思路直接被我抄了。

synapse v1.0 的索引是一份 JSON 文件（`MEMORY_MAP.json`），tag 查找靠 bash 线性扫描，关键词搜索靠正则。在 ~15 个节点时还能用，但到 30 节点时 `generate_memory_map.sh` 的 976 行 bash 代码已经很吃力了。

v1.2 参考 codegraph 的 schema，建了自己的 5 张表（`nodes` + `edges` + `cooccurrence` + `staleness` + `nodes_fts`），用 FTS5 做 BM25 全文排序。核心差异：我的 SQLite 是**缓存**——Markdown 文件才是 source of truth。删掉 `.synapse/cache/memory.db`，跑一次 `--full` 就能从 Markdown 节点重建。codegraph 的 SQLite 是唯一的真相源，因为它的数据来自 tree-sitter 解析——无法从别处重建。

30 节点实测的差距：

| 操作 | v1.0 (bash+grep) | v1.2 (SQLite FTS5) |
|------|-----------------|-------------------|
| Tag 查找 | ~120ms | ~5ms |
| 全文搜索 | ~200ms | ~5ms |
| Doctor 健康检查 | ~350ms | ~120ms |

### 学到的第二点：文件监控 + 增量同步（v1.2）

codegraph 用 OS 原生文件事件（FSEvents / inotify / ReadDirectoryChangesW）加 2 秒 debounce 实现代码变更的实时同步。这个设计优雅且高效。

synapse v1.0 的 drift 检测只在会话结束 hook 里跑——你中途改了源码，meta/ 节点不知道自己"过时"了，要等会话结束才报警。v1.2 参考了 codegraph 的思路，但做了简化：`watch.sh` 用 30 秒轮询（不是 daemon）比较文件 `mtime + size` hash，变动时在 SQLite `staleness` 表中标记受影响的节点。

**为什么没直接用 OS 原生事件？** 因为对目标用户（全栈个体户）来说，装一个常驻后台进程的心智负担和运维成本比 30 秒轮询高太多。一个 bash `sleep 30` 循环不占资源、不崩溃、不需要重启——这是"够用"胜过"完美"的刻意选择。

### 学到的第三点：源码符号提取（v1.1）

codegraph 的 tree-sitter 能解析 20+ 语言，这是它的核心技术护城河。这个我做不到——也不打算做——因为那需要引入 native 依赖，违背了 synapse "零安装"的底线。

但 codegraph 的"扫描源码 → 提取符号 → 建立索引"这条流水线的思路是对的。v1.1 做了轻量版：`source_scan.py` 用 Python `ast` 标准库解析 Python（精确），用正则做 JS/TS/Go（best-effort）。没有 tree-sitter 的覆盖率，但保持了零 pip 依赖，且提取的结果标注 `<!-- auto-detected, please verify -->` 供人审核。

**这三个学习让 synapse 从"只有概念"变成了"有关键性能指标"的项目。** 再次感谢 codegraph 的开源和 Colby 的架构设计。

---

## 五、v1.3-v1.4：codegraph 给不了的那些东西

如果说 v1.1-v1.2 是在学 codegraph 的长处，那 v1.3-v1.4 就是在做 codegraph 从设计上就不打算做的事。

### v1.3：全栈链路追踪

synapse 新增了 4 种工程语义节点——`db_`（数据库表）、`api_`（API 端点组）、`ui_`（前端页面）、`dep_`（部署单元）。加上原有的 3 种，7 种节点类型可以描述"从前端按钮到数据库事务"的完整链路。

`bfs_trace()` 实现了状态机 BFS：指定类型序列（如 `ui → api → db → dep`），自动找到所有符合序列的完整路径。允许多跳同类型（微服务网关场景）、允许跳级（API 直接调 Redis 不经过 DB）。回溯剪枝剃掉未到终点的死胡同。

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

codegraph 能告诉你 `PaymentService` 调用了 `OrderRepository`，但它不知道"支付链路"这个**业务概念**——因为"业务概念"不存在于 AST 里，它是人类对代码的组织方式的理解。synapse 的节点类型就是把这些"人理解的东西"结构化存下来。

### v1.4：AI 自主记忆写入

这是 v1.4 最大的变化，也是 codegraph 永远不需要的功能——因为 codegraph 的图全自动生成，不存在"人忘了写"的问题。但 synapse 的图有一部分**只能由人提供**——为什么选这个方案、还差什么没做、什么决策在等待确认。

v1.4 之前，人必须在 Claude Code 里主动说 `/记录一下`。忘了就是忘了。

v1.4 之后，AI 在对话中自主观察：你改了哪个文件（git diff）、在对话里说了什么决定（"就用 Redis 吧"）、提到了什么阻塞项（"退款逻辑还没写"）。会话结束时自动提取信号、按置信度分流（≥70% 自动写入，<70% 展示待确认）。

```
🧠 Synapse Session End

📝 Auto-Recorded:
  ✓ api_payment-routes: 新增 API 端点 POST /callback (95%)
  ✓ feat_login: 响应式断点 768→640px (90%)

⚠  Needs Review:
  1. [key_decision] 决定: Redis 做支付状态缓存 (85%)
```

---

## 六、MCP vs Skills：为什么选了 Skills 这条路

codegraph 用 MCP Server 实现，synapse 用 Claude Code Skills + Hooks 实现。这是两个不同的集成哲学：

| | codegraph (MCP) | synapse (Skills) |
|---|---|---|
| **安装步骤** | `npx @colbymchenry/codegraph` | `cp -r synapse-* ~/.claude/skills/` |
| **运行时依赖** | Node.js + npm 全局包 + 独立进程 | bash 4 + Python 3.8（stdlib only） |
| **跨 Agent** | Claude Code / Cursor / Codex / OpenCode 等 | Claude Code only |
| **数据可手改** | 不可（SQLite 唯一真相） | 可（Markdown 主存储，SQLite 缓存） |
| **协议约束** | AI 自己决定什么时候调用 MCP 工具 | Hook 运行时强制（PreToolUse 拦截 + Stop 校验） |

**选 Skills 不是因为它"更好"，是因为它更匹配目标用户的生活现实。**

全栈个体户的典型环境：一台笔记本，几个项目目录，没有 CI 服务器，没有团队。MCP 的跨 Agent 能力对他来说是用不到的重量——他只用 Claude Code。但 MCP 的代价他全得承担：装 Node.js、管理 npm 全局包、担心 MCP 进程挂了。

Skills 的哲学是"零安装、零进程、文件即数据"。最极端的情况下——AI 崩了、Hook 坏了、Python 没装——你还能用 Vim 打开 `meta/feat_payment.md` 手改一行。这种逃生舱在 MCP 架构下不存在。

---

## 七、v1.0 → v1.4 总览

| 版本 | 核心能力 | 关键新增 |
|------|---------|---------|
| v1.0 | 图拓扑 + 三层渐进加载 + Hook 强制协议 | 11 scripts, 4 hooks |
| v1.1 | 增量 MAP + 源码锚点预填 | `source_scan.py`, `--changed` |
| v1.2 | SQLite FTS5 + 实时 Stale 检测 | `db_init.py`, `db_index.py`, `watch.sh` |
| v1.3 | 全栈 7 种节点 + 链路追踪 BFS | `bfs_trace()`, `--fullstack`, `fullstack-node-spec.md` |
| v1.4 | AI 自主记忆写入 | `auto_observe.py`, `--auto-confirm`, session-end 自动分流 |

**系统规模变化**：从 v1.0 的 11 个脚本增长到 17 个。generate_memory_map.sh 从 976 行纯 bash 演进为 bash+SQLite 双层架构。Python 代码从 0 行增长到 ~700 行（全部 stdlib）。零 pip/npm 依赖的底线没破过。

---

## 八、局限与后续规划

说实话，synapse 目前的状态是**方向对、雏形有、但欠打磨**。和 codegraph 的 9.6k star 和 7 个项目的基准数据比起来，synapse 只有 30 节点的小规模测试和自己的日常使用验证。差距是客观的。

几个我已知的明显短板：

1. **源码符号提取的覆盖率不够**：只有 Python 是 AST 精确解析，JS/TS/Go 靠正则。codegraph 的 tree-sitter 20+ 语言覆盖面是我短期内无法企及的。后续考虑至少把 TS/JS 的 tree-sitter 加进来（Node.js 用户装 `tree-sitter` 不难），但保持其他语言的零依赖承诺。

2. **没有跨项目依赖追踪**：目前每个项目的记忆图是独立隔离的。如果有三个项目共享同一个 API 契约，改了一个项目的接口定义，另外两个项目感知不到。后续想做一个"跨项目 Connection Point 注册表"。

3. **auto_observe.py 的置信度系统太简单**：目前是硬编码的固定值（git diff = 90%、对话匹配 = 85% 等），没有根据匹配质量和历史准确率做动态调整。后续需要加贝叶斯或至少加权衰减。

4. **没有代码级调用链**：synapse 能追踪"这个 API 端点属于哪个模块"，但不能追踪"这个函数调了哪个函数"。这不是设计缺陷——是场景取舍——但对某些用户来说仍然是信息缺口。后续想做一个 codegraph→synapse 的桥接工具：用 codegraph 的 `codegraph_callers` 结果自动填充 synapse 的 Connection Points。

5. **可视化缺失**：目前图只有 Mermaid 文本输出。后续想做交互式 HTML 的链路高亮，stale 节点红色标记。

这些都不会是下个版本就全部解决的问题。synapse 的节奏是**在真实使用中迭代，而不是闭门做一个完美但没人用的东西**。

---

## 九、结语

codegraph 是代码的字典，synapse 是工程的笔记。字典不需要笔记的功能，笔记也长不出字典的精度。

站在 codegraph 这个优秀项目的基础上，synapse 针对"一个人同时维护多个项目、AI 是唯一同事"这个具体场景，做了四个版本的快速迭代。从一个概念验证变成了一个每天在自己项目里跑的工具。

如果你只需要"这个函数在哪被调用了"——codegraph 更好，直接装。

如果你经常遇到"上周做到哪了""改这个会不会炸""这项目还差什么"——synapse 可能对路。

如果你两个都装——它们不冲突，各干各的。我只是还没把桥搭好。

---

**GitHub**：[https://github.com/LameGz/synapse-graph-skills](https://github.com/LameGz/synapse-graph-skills)

**codegraph**：[https://github.com/colbymchenry/codegraph](https://github.com/colbymchenry/codegraph)（强烈推荐，去看看他的架构设计）

---

*本文由 Synapse Graph Skills 作者撰写。v1.4 于 2026-05-24 发布。欢迎转载，注明出处即可。*
