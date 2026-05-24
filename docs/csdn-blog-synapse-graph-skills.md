# 一个人维护 5 个项目，AI 是我的"唯一同事"——给全栈个体户的图拓扑工程记忆系统

> 你不是在管理一个项目的多个模块。你是在管理多个项目，每个项目有十几个模块。你的 AI Agent 是你唯一的"同事"——它忘了，就没人能回答你了。

---

## 一、真实的场景：你不是在写一个项目，你是在同时维护好几个

先别急着看技术方案。花 30 秒看看这个场景你熟不熟悉：

```
上周一：给 SaaS 产品 A 接好支付宝支付回调，写了 200 行后端逻辑
上周二：切到客户项目 B，改 Landing Page 的响应式布局
上周三：客户 B 的服务器崩了，紧急修了一整天
上周四：回到产品 A，准备继续优化支付流程……
        但你和 AI 都忘了——那个回调接口的参数结构是什么来着？
上周五：外包项目 C 的甲方突然需求变更，要加一个报表导出功能
        你打开项目 C 的终端，AI 一脸茫然——上次碰这项目是三个星期前
```

**这不是"模块切换"的问题。这是"项目切换"的问题。**

一人公司 / 独立开发者 / 全栈个体户的日常不是在一个项目的 auth 和 payment 之间切来切去——**你是在完全不同的代码仓库之间反复横跳**。SaaS 产品 A 用 FastAPI + React，外包项目 B 用 Next.js + Prisma，工具项目 C 用 Go + HTMX。每个项目的技术栈完全不同，每个项目的进度完全独立。

而你的 AI Agent——不管是 Claude Code、Cursor 还是 GitHub Copilot——是你**唯一的"同事"**。

在公司里，你可以扭头问同事："哎，那个支付回调的参数结构是什么来着？""改 user 表会影响哪些功能？"但作为一个人，**你只能问 AI**。当 AI 也忘了的时候——你没有 Plan B。

---

## 二、市面上已经有很多"记忆工具"了，为什么它们解决不了你的问题？

你说得对，记忆相关的工具确实很多。但大多数不是为你这种场景设计的：

| 工具类型 | 代表产品 | 它解决什么问题 | 它为什么不适合你 |
|----------|---------|--------------|----------------|
| **AI 个人记忆** | Mem0、MemGPT、Letta | 让聊天机器人"记住你"——偏好、习惯、对话历史 | 设计目标是对话连续性，不是工程项目的模块依赖拓扑。它不知道什么是"跨模块影响" |
| **向量知识库** | Pinecone、Chroma、Weaviate、RAGFlow | 用语义搜索检索文档片段 | 运维成本对个人开发者是天价；向量相似度检索有幻觉——"用户表"和"订单表"的向量很近，但改用户表不需要加载订单表 |
| **团队 Wiki** | Notion、Confluence、飞书文档 | 让人类团队共享知识 | 设计给人类读的，不是给 AI 的 context window 用的。没有人会每次写代码前先去翻 Wiki——太慢了 |
| **项目级 AI 配置** | Cursor Rules、CLAUDE.md、.cursorrules | 给 AI 静态的项目背景信息 | 一个文件塞下所有项目信息的结局是：要么太简略没用，要么太长撑爆 context。而且不会自动更新——你上周改了支付逻辑，CLAUDE.md 不会自己跟着变 |
| **会话缓存** | Claude Code conversation cache | 恢复上次对话 | 恢复的是"对话"，不是"项目状态的增量更新"。不同项目间对话不互通 |

**核心矛盾**：现有工具要么为"大型团队"设计（太重），要么为"AI 记住你这个人"设计（场景不匹配），没有为"AI 记住你的多个项目的工程状态"设计的。

更具体地说：

- **Mem0 / Letta 等**解决的是"对话记忆"——AI 记住你叫张三，喜欢用 TypeScript，偏好函数式风格。但你的问题是"项目 C 的支付模块还差哪些接口没写完？"——这是**工程进度记忆**，不是**用户画像记忆**。
- **RAG / 向量库**解决的是"从大量文档中检索相关信息"。但你的问题不是"从文档中找到支付相关的段落"，而是"**精确**地知道改 `mod_user` 会影响 `feat_login` 和 `feat_subscription` 两个功能"——这是**确定性依赖关系**，不是**概率性语义相似度**。
- **CLAUDE.md / Cursor Rules** 解决的是"给 AI 一段静态背景介绍"。但你的项目在**不断变化**——每天都有新的接口被接好，新的 bug 被修掉。需要的是一个**会随时间更新的活记忆**，而不是一份写完之后再也不会改的 README。

---

## 三、Synapse Graph Skills 到底做了什么不同的事？

Synapse 是专门为这个场景设计的：

> **一个全栈开发者 × 多个项目 × AI Agent 是唯一队友 → 需要一种方式让 AI 精确记住每个项目的工程状态，在不同会话之间无缝衔接。**

它不是通用记忆，它是**工程记忆**——专门记住"项目的模块/功能做到什么程度了、模块之间怎么依赖的、改一个会影响哪些"。

### 如果用一句话说清楚

**Synapse 把每个项目变成一张"依赖关系地图"（图拓扑），AI 每次只需要按图索骥加载相关的几个节点，永远不需要把全部记忆塞进 context。**

```
你的其他项目                    当前正在操作的项目
     │                              │
     ├── 项目 A (SaaS 产品)          ├── meta/feat_payment.md
     ├── 项目 B (客户 Landing)       │   depends_on: [mod_alipay-sdk, mod_user-account]
     ├── 项目 C (外包后台)           │   blocks: [feat_subscription, feat_invoice]
     ├── 项目 D (开源工具)           │
     └── 项目 E (实验性项目)         │
                                     │
          每个项目独立拥有            AI 只加载项目 A 中与支付
          自己的 meta/ 记忆图        相关的 3-5 个节点，不会碰
                                     B/C/D/E 的任何记忆
```

**每个项目的记忆是独立隔离的**——你在项目 A 的终端里问"支付做得怎么样了？"，它只查项目 A 的记忆图，项目 B/C/D/E 的记忆文件根本不会被读到。

---

## 四、具体怎么运作的？一张图，三层加载

### 4.1 记忆不是一篇长文，而是一张图

传统的记忆方式是"写一篇 README，把项目信息全部塞进去"。Synapse 的做法完全不同——**每个模块/功能是一个独立的 Markdown 节点，节点之间用显式边连接**：

```yaml
---
# meta/feat_payment.md
depends_on: [mod_alipay-sdk, mod_user-account, mod_order]
auto_linked: [mod_notification, mod_invoice]
tags: [支付, 支付宝, 回调, payment]
aliases: [付款, 充值, pay, alipay]
summary: 支付宝 PC 扫码支付 + H5 支付，回调接口已完成，退款接口待接
---
```

三种边构成完整有向图：

| 边 | 含义 | "改 mod_order 接口签名"会发生什么？ |
|----|------|-------------------------------------|
| `depends_on` | 硬依赖：目标变了，我受影响 | feat_payment 因为依赖 mod_order，会被自动标记为"受影响" |
| `auto_linked` | 软依赖：机器推断的关系 | mod_notification 与订单相关，建议检查发送的订单通知是否兼容新签名 |
| `blocks`（自动计算） | 反向边：谁依赖我？ | 马上算出 mod_order 被 feat_payment、feat_invoice、feat_subscription 依赖 |

**"改这个会影响哪些功能？"不再靠猜——图已经算好了。**

### 4.2 三层渐进式加载：永远不"全量读一遍"

AI 面对记忆时的常见行为是"把所有 meta/*.md 读一遍以防遗漏"，这在 30 个模块时直接把 context 撑爆。Synapse 的三层协议强制精确加载：

```
第 1 层：倒排索引（MEMORY_MAP）           ~200-500 tokens
    └── 查标签/别名 → 找到目标节点名
        "支付做得怎么样了？" → 标签匹配"支付" → 锁定 feat_payment

第 2 层：目标节点完整内容                  ~500-1500 tokens
    └── 读了 feat_payment.md，知道回调已接好 → 够了？STOP

第 3 层：受限 BFS 展开（深度≤2，宽度≤5）   ~1000-4000 tokens
    └── "改支付会影响哪些功能？" → 查 blocks：feat_subscription + feat_invoice
        → 只加载这两个节点的 Connection Points → STOP
        → token 超过 context 的 15%？硬停止，报告用户
```

**30 个模块的项目，暴力加载读 30 个文件。受限 BFS 读 3-5 个。** 模块越多，差距越大。

### 4.3 Hook 强制遵守——规则不是建议，是约束

光写文档说"请按协议加载"是没用的，AI 在长会话中会慢慢偏离协议。Synapse 利用 Claude Code 的 Hook 机制把协议变成**运行时强制规则**：

| Hook | 它做了什么 | 没有它会怎样 |
|------|-----------|-------------|
| **PreToolUse** | AI 尝试读文件时拦截，强制 MAP→节点→BFS 顺序 | AI 一次读 30 个 meta 文件，context 爆炸 |
| **PostToolUse** | AI 写文件后自动检测是否产生了新的跨模块引用 | 新的依赖关系无人记录，图越来越不准 |
| **Stop** | 会话结束时重建索引、校验拓扑、检测漂移、输出变更 | 记忆与源码脱节，不打开项目就不知道记忆已经过时 |

**每次会话结束时自动执行**：

```
[doctor] Topology Health:
  ✓ 18 nodes active, 0 dead links, 0 orphans
  ⚠ 3 nodes flagged for drift: 源码改了但 meta/ 没更新
  ⚠ mod_payment.md 218 lines (>200), 建议拆分

[change-summary] 本次会话变更：
  M feat_payment.md    +1 Change Log
  M mod_alipay-sdk.md  更新 Connection Points
  M MEMORY_MAP.md      自动重建
```

你不需要手动维护——会话结束时它自己检查、自己报告。

### 4.4 连接点是可验证的契约，不是自由文本

传统方式写"需要支付 API"——这对影响分析毫无价值。Synapse 的连接点是**带源码锚点的结构化接口描述**：

```markdown
### To mod_alipay-sdk
- **调用**: POST /api/v1/payments/callback  <!-- @ref: src/payment/routes.ts:45 -->
- **入参**: `{ order_id: string, trade_no: string, total_amount: number }`
- **返回**: `{ success: boolean, out_trade_no: string }`
- **错误码**: `402` 余额不足, `409` 重复通知
- **约束**: 通过 `Idempotency-Key` 实现幂等，支付宝会重复发送通知
```

`@ref` 锚点让系统能在每次会话结束时检查：**源码中的接口还是记忆里记录的样子吗？** 不是，就报警——不等你踩坑才知道记忆已经过时了。

---

## 五、四枚独立 Skill——装几个用几个

Synapse 以 Claude Code Skills 形态发布，四个模块独立可安装：

```
synapse-graph-memory (66 KB)      ← 核心：检索引擎 + 7 步决策树
    ├── 什么时候触发？  "XX 做得怎么样了？"、"会影响哪些功能？"
    └── 包含哪些脚本？  11 个脚本 + 4 个 hook（完整捆绑，装了就能用）

synapse-timeline (5.5 KB)         ← 只读查询：时间线 + Open Issues
    ├── "最近改了啥？"、"有哪些没解决的问题？"
    └── 单脚本 227 行，bash + 嵌入式 Python

synapse-daily-note (26 KB)        ← 写入管线：一句话 → 自动更新记忆
    ├── "记录一下：接好了 POST /api/v1/auth/login"
    └── 全管线：NL 解析 → 边检测 → 写入 → 重建索引 → 拓扑校验

synapse-init (43 KB)              ← 冷启动向导：给任何项目一键配好记忆
    ├── "初始化记忆"
    └── 自动检测技术栈 → 扫描 src/ → 生成骨架节点 → 注册 hook
```

**去哪里装？**

```bash
# 从 GitHub 直接复制
git clone https://github.com/LameGz/synapse-graph-skills.git
cp -r synapse-graph-skills/synapse-graph-memory ~/.claude/skills/
cp -r synapse-graph-skills/synapse-timeline ~/.claude/skills/
cp -r synapse-graph-skills/synapse-daily-note ~/.claude/skills/
cp -r synapse-graph-skills/synapse-init ~/.claude/skills/
```

---

## 六、评估数据：对 AI Agent 的 context 效率有多大提升？

在 8 节点 SaaS 测试项目上使用 deepseek-v4-pro 评估：

| 指标 | 装 Skill | 不装 | 说明 |
|------|---------|------|------|
| 平均读取文件数 | **8.0** | 13.0 | 少读了 38% 的文件 |
| 无关文件加载 | **0** | 4.5 | 这是核心：不该读的绝对不读 |
| 断言通过率 | **100%** | 62.5% | AI 知道的信息是正确的 |

**不装 Skill 的 AI 行为**：MEMORY_MAP.* → 所有 8 个 meta/*.md → README → 2 个 cache 文件 → "以防万一"全读一遍

**装 Skill 后的 AI 行为**：SKILL.md → MEMORY_MAP.md → feat_login → BFS 展开 2 个直接依赖 → STOP

在 30+ 模块的项目中，这个差距是指数级的——因为不装 Skill 的 AI 会尝试把所有 30 个文件都读一遍，而受限 BFS 停在 3-5 个文件。

---

## 七、三段进化：这不是从零开始的点子，它已经打磨了三代

Synapse 解决这个问题走了三代：

```
V1 (2024)                V2 (2025 初)            V3 (2025.05) ← 当前
─────────────────        ─────────────────       ─────────────────────────
形态：单脚本              形态：单体 Agent 记忆     形态：四枚独立 Skill
存储：Markdown 扁片        存储：Markdown 扁片       存储：图拓扑 + 显式边
检索：grep 全文搜索        检索：关键词 + 摘要       检索：三层渐进式 + 受限 BFS
边关系：无                 边关系：隐式（命名约定）   边关系：显式 depends_on/blocks
一致性：靠开发者自律        一致性：靠开发者自律      一致性：Hook 运行时强制
规模上限：~10 节点          规模上限：~15 节点         规模上限：30+ 节点（常数级）
```

**V1→V2 的核心变化**：从脚本变成 Agent，自然语言交互替代了命令行。

**V2→V3 的核心变化**：从扁平文件变成图拓扑——这是质的飞跃。V2 的项目记忆在 ~15 个模块后就开始 context 爆炸；V3 用"显式图 + 受限 BFS"把加载成本和模块数量解耦。

---

## 八、适合谁？不适合谁？

### 适合你，如果你……

- 一个人同时维护 2 个以上的项目
- AI Agent（Claude Code / Cursor / Copilot）是你日常的主要编程搭档
- 经常在不同项目之间切换，切回来已经忘了上次做到哪了
- 项目的模块数在 10 个以上，全量塞进 context 不现实
- 不想折腾向量数据库 / RAG 那一套重型基础设施

### 不适合你，如果你……

- 你是大厂团队，有专门的文档 / Wiki / oncall —— 你不需要这个
- 你只有一个项目，且只有 3-5 个模块 —— 全量加载就够了
- 你不用 AI Agent 写代码 —— Synapse 是给 AI 读的，不是给你读的
- 你需要的是"对话记忆"（记住用户偏好、习惯）—— 那是 Mem0/Letta 的领域，不是 Synapse 的

---

## 九、30 秒快速上手

```bash
# 1. 安装
cp -r synapse-graph-skills/synapse-graph-memory ~/.claude/skills/
cp -r synapse-graph-skills/synapse-init ~/.claude/skills/

# 2. 在任意项目中初始化
# （在 Claude Code 中直接说）
用户：初始化记忆

# 3. 开始记录
用户：记录一下：接好了支付宝 PC 扫码支付，回调通知接口幂等处理完成

# 4. 下次打开项目时直接问
用户：支付做得怎么样了？
用户：改 mod_user 的套餐字段会影响哪些功能？
```

---

## 十、总结

一人全栈开发者的核心困境不是"不会写"，而是**"切回来忘了"**。你不是没有 AI 助手——你有，而且它能力很强。但每次打开新会话，它都是"一张白纸"，你花了 20 分钟才让它理解项目的上下文——这就是 **context 重建成本**。

现有记忆工具的对不上这个场景：Mem0 记住"你是什么样的人"，RAG 记住"文档里写了什么"，但没有人记住"**你的项目的工程状态**"——哪个接口接好了、哪个模块还差什么、模块之间怎么连在一起的。

Synapse 做的就是这件事：

> **每个项目一张图，AI 按图索骥加载，永远不把所有记忆塞进 context。**
>
> **你不止一个项目，你的 AI 是你唯一的同事——它不应该每次都从头开始了解你上周做了什么。**

---

- **GitHub**: [https://github.com/LameGz/synapse-graph-skills](https://github.com/LameGz/synapse-graph-skills)
- **架构文档**: [docs/architecture.md](docs/architecture.md)
- **Skills 总览**: [docs/skills-overview.md](docs/skills-overview.md)
- **使用指南**: [USAGE.md](USAGE.md)

---

*本文由 Synapse Graph Skills 作者撰写。欢迎转载，注明出处即可。*
