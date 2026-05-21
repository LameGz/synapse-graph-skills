# Synapse Graph Skills

**面向一人全栈开发者的工程记忆系统。** 基于图拓扑的分区上下文加载——永远不需要一次加载全部记忆。

[English](README.md) | [使用指南](USAGE.md) | [架构文档](docs/architecture.md) | [Skills 总览](docs/skills-overview.md)

---

## 与 Synapse / Synapse-Solo 的关系

Synapse Graph Skills 是 Synapse 记忆体系的**第三代**，以 **Skills 形态**完全重写，与前两代形成清晰的技术分叉：

```
Synapse (V1)            Synapse-Solo (V2)         Synapse Graph Skills (V3) ← 当前
─────────────────      ──────────────────       ──────────────────────────────
形态：单脚本 + 配置      形态：单体 Agent 记忆        形态：四枚独立可安装 Skill
存储：扁平 Markdown      存储：扁平 Markdown         存储：图拓扑 Markdown 节点 + 显式边
检索：全文 grep          检索：关键词 + 摘要匹配      检索：三层渐进式加载 + 受限 BFS
索引：无                 索引：简单摘要索引            索引：倒排索引 MEMORY_MAP（O(1) 查找）
边关系：无               边关系：隐式（靠命名约定）     边关系：显式（depends_on / auto_linked / blocks）
一致性：靠人记           一致性：靠人记                一致性：Hook 运行时强制 + doctor.sh 拓扑校验
规模上限：~10 节点        规模上限：~15 节点            规模上限：30+ 节点（BFS 受限，常数级 context）
```

**关键分叉点**：V1/V2 在模块数超过 15 之后都会遇到 context 爆炸问题——因为它们是"扁平文件 + 全文加载"模型。V3 的图拓扑 + 受限 BFS 让检索成本与模块数**解耦**，30 个模块和 8 个模块的 context 消耗几乎一样。

---

## 解决的问题

在 auth、支付、通知三个模块之间来回切了三个星期之后，你的 AI 助手要么加载了无关记忆，要么漏掉了关键的跨模块依赖。现有的方案（向量数据库、embedding、RAG）对个人开发者太重，而且会引入幻觉风险。

## 解决方案：图记忆 —— 四大创新点

Synapse V3 把项目知识建模为**带显式依赖边的 Markdown 节点**。以下是 V3 相比 V1/V2 的核心创新：

### 创新一：显式图拓扑，替代隐式命名约定

V1/V2 靠文件命名约定（如 `auth.md`、`payment.md`）暗示模块关系，AI 需要"猜测"哪些文件相关。V3 在每个节点的 frontmatter 中声明**显式依赖边**：

```yaml
depends_on: [mod_auth-api, mod_user-account]   # 硬依赖：改我必看它
auto_linked: [mod_design-system]                # 软依赖：机器推断
```

`blocks`（反向边）由脚本自动计算——"改 X 会影响哪些功能？"从 O(n) 的关键词猜测变成 O(1) 的 MAP 查表。

### 创新二：三层渐进式加载，永不"全量读取"

V1/V2 的典型行为是"把所有 meta/*.md 读一遍以防万一"。V3 强制执行三层协议：

```
第 1 层：MEMORY_MAP 标签索引 + 摘要     (~200-500 tokens)
    → 模糊问题？停在这里。
第 2 层：完整目标节点                    (~500-1500 tokens)
    → 简单任务？停在这里。
第 3 层：受限 BFS（深度 ≤2，宽度 ≤5）   (~1000-4000 tokens)
    → 跨模块？只加载必需的。
    → Token 预算 > 15% context？硬停止。
```

核心约束：**永远不加载全部节点**。这使得 30+ 模块时 BFS 仍保持常数级 context 消耗。

### 创新三：Hook 强制一致性，不止于文档

V1/V2 的一致性靠"开发者记得遵守规范"。V3 将协议写进 Claude Code hooks，在运行时强制执行：

| Hook | 时机 | 行为 |
|------|------|------|
| PreToolUse | 每次文件读取前 | 拦截读取，强制按协议顺序加载 |
| PostToolUse | 每次文件写入后 | 自动检测跨模块边，建议更新 |
| Stop | 会话结束时 | 重建 MAP、校验拓扑、检测漂移、输出变更摘要 |

规则不再是一份"建议文档"——不遵守协议就无法读到文件。

### 创新四：连接点作为可验证契约

V1/V2 的跨模块描述是自由文本（"需要 auth API"），对影响评估毫无用处。V3 的连接点是**带源码锚点的结构化契约**：

```markdown
### To mod_payment
- **Endpoint**: POST /api/v1/payments/callback  <!-- @ref: src/payment/routes.ts:45 -->
- **Request**: `{ order_id: string, status: string, amount: number }`
- **Response**: `{ success: boolean, plan: string }`
- **Errors**: `402` Insufficient funds, `409` Duplicate order
```

`@ref` 锚点使 `session-end.sh` 能自动检测源码是否已经偏离记忆中的契约（漂移检测）。

---

## 四个独立 Skill

每个 skill **独立可安装**，不需要全装，按需选择：

| Skill | 功能 | 安装场景 |
|-------|------|---------|
| **[synapse-graph-memory](skills/synapse-graph-memory/)** | 核心检索协议——7 步决策树 | 想问"XX 做得怎么样了？"并得到精确回答 |
| **[synapse-timeline](skills/synapse-timeline/)** | 只读时间线 & 问题查询 | 想看"最近改了啥"、"还有哪些 open issues" |
| **[synapse-daily-note](skills/synapse-daily-note/)** | 一行命令完成 NL→记忆 管线 | 用"记录一下：接好了登录接口"记录进度 |
| **[synapse-init](skills/synapse-init/)** | 项目冷启动向导 | 为新项目或已有项目初始化记忆系统 |

### Skill 架构

```
synapse-graph-memory (核心，始终加载)
├── 检索协议（决策树）
├── 节点规范 + 关键规则 + 反模式
└── 全部脚本 + hooks（完整捆绑）

synapse-timeline ───── synapse-daily-note ───── synapse-init
(只读查询)               (写入管线)               (冷启动向导)
```

每个 skill 都自包含全部所需脚本——装了就能用，不依赖其他 skill。

---

## 快速开始

### 安装 Skill

```bash
# 复制到 Claude Code skills 目录
cp -r skills/synapse-graph-memory ~/.claude/skills/

# 或从 .skill 包安装
# （将 .skill 文件拖入 .claude/skills/）
```

### 初始化项目

```
用户：初始化记忆
```

Synapse 自动检测技术栈，为每个模块创建 `meta/` 骨架节点，注册 hooks。

### 记录进度

```
用户：记录一下：接好了 POST /api/v1/auth/login，返回 JWT token，session 持久化完成
```

一行命令跑完整条管线：ingest → suggest edges → apply → rebuild MAP → validate。

### 查询状态

```
用户：登录功能做得怎么样了？
```

Synapse 精确加载正确的节点——先 MAP，再 `feat_login`，只在必要时展开依赖。

---

## 测试结果

在 8 节点 SaaS 测试项目上用 deepseek-v4-pro 评估：

| 指标 | 有 Skill | 无 Skill | 变化 |
|------|---------|----------|------|
| 平均读取文件数 | **8.0** | 13.0 | **-38%** |
| 无关文件数 | **0** | 4.5 | 核心优势 |
| 断言通过率 | **100%** | 62.5% | — |

30+ 模块时差距呈指数级扩大——暴力加载随模块数线性增长，受限 BFS 保持常数级。

完整报告：[EVAL_REPORT.md](EVAL_REPORT.md)

---

## 仓库结构

```
synapse-graph-skills/
├── .github/workflows/     # CI：test、lint、release
├── skills/                # 四个独立可安装的 skill
│   ├── synapse-graph-memory/
│   ├── synapse-timeline/
│   ├── synapse-daily-note/
│   └── synapse-init/
├── docs/                  # 架构、贡献指南、skills 总览
├── tests/                 # 测试运行器 + fixtures
├── EVAL_REPORT.md         # 基准测试结果
├── USAGE.md               # 详细使用指南
├── README.md              # 英文 README
└── README.zh-CN.md        # 本文件
```

## 技术栈

- **bash 4+**（macOS：`brew install bash`）
- **Python 3.8+**（仅标准库——`json`、`re`、`sys`、`datetime`、`pathlib`）
- **Claude Code**（用于 skill 执行；hooks 需配置 settings.json）

零 pip 依赖。零 npm 依赖。POSIX 兼容脚本。无向量数据库。无 embedding。

## 贡献

详见 [docs/contributing.md](docs/contributing.md)，包含 skill 结构规范、eval 格式、PR checklist。

## 许可证

MIT——详见 [LICENSE](LICENSE)。

---

**Synapse Graph Skills (V3)**——图拓扑记忆，让你的 AI 助手知道你上周做了什么，不需要你再解释一遍。从 V1 的扁平文件到 V2 的单体 Agent，再到 V3 的图拓扑 + Skills 架构——每一次都在解决同一个问题：**context 不会随模块数爆炸**。
