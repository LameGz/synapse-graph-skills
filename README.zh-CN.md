# Synapse Graph Skills

> **给编码智能体的文件化工程记忆**——写入无感、读取无感、多宿主可插拔。你不用再记住"记录一下",也不用再解释"上次做到哪了"。

GitHub:[LameGz/synapse-graph-skills](https://github.com/LameGz/synapse-graph-skills) · [English](README.md) · [使用指南](USAGE.md) · [架构文档](docs/architecture.md)

---

## 它解决什么问题

个人全栈开发者的项目记忆散落在对话历史里:换个会话就丢,换个工具就断,模块一多就只能靠暴力重读文件。Synapse 把工程记忆落成 **`meta/*.md` 图节点 + 自动生成的 MEMORY_MAP 索引**——Markdown 是唯一事实源,SQLite 只是可删的缓存,零外部服务。

## 核心能力(v1.5)

**双向无感**——这是 v1.5 的主线:

- **写入无感(SessionEnd)**:会话结束时,hook 自动从 git diff / 对话信号里提取值得记的变化——高置信度(≥70%)静默落库,低置信度进 Memory Inbox 待审。你正常写代码就行。
- **读取无感(UserPromptSubmit)**:你提问时,hook 自动把与问题相关的记忆节点摘要注入上下文——支持中文提问(内置"支付→payment"这类跨语言话题映射)。你不用说"加载记忆"。

**检索有纪律**——MAP 优先、目标节点其次、受限 BFS(depth≤2, width≤5)展开,模块再多上下文也不爆炸。

**多宿主可插拔**——同一套记忆策略,按宿主生命周期归一化:

| 宿主 | 接入方式 | 无感程度 |
|------|---------|---------|
| Claude Code | hooks(SessionEnd / UserPromptSubmit / PreToolUse / PostToolUse) | 完全无感 |
| Codex CLI / Gemini CLI / Pi / Zed / OpenCode / Cursor | AGENTS.md 托管指令段 | 半无感(按指令自动执行) |
| 其他 | `.synapse/agent-instructions.md` 手动接线 | 手动 |

**单一来源构建**——全部脚本以 `synapse-graph-memory/scripts/` 为 canonical,其余 Skill 的副本由 `build_dist.py` 构建期同步,CI 用 `--check` 门禁防漂移。

**零依赖**——bash 4+、Python 3.8+ 标准库(sqlite3/ast/json/re),无 pip 包、无 npm 包、无外部 API、无向量数据库。

---

## 快速开始

```bash
# 1. 安装核心 Skill
cp -r synapse-graph-memory ~/.claude/skills/

# 2. 在目标项目里初始化记忆(全栈项目加 --fullstack)
bash ~/.claude/skills/synapse-graph-memory/scripts/init.sh --project /path/to/project

# 3. 安装宿主适配器(自动探测;也可显式指定 claude-code / codex / gemini-cli / pi / generic)
python adapters/install_adapter.py auto --project /path/to/project
```

然后正常干活。想看自动记了什么:

```bash
python synapse-graph-memory/scripts/memory_inbox.py list --project .
python synapse-graph-memory/scripts/project_resume.py --project .   # 或 --project-root .
```

手动记录(v1.4 后通常不需要):

```bash
bash synapse-graph-memory/scripts/synapse_note.sh --project . --text "接好了 POST /api/v1/auth/login,返回 JWT"
```

### 查询就说话

```
用户:登录功能做得怎么样了?
用户:改 orders 表会影响哪些页面?
用户:支付链路从前端到数据库怎么通的?
```

---

## 无感是怎么发生的

```
写入:SessionEnd → session-end.sh → auto_observe.py(git diff + 信号提取)
        → 置信度 ≥70%: synapse_note.sh 直接落库 + 增量重建 MAP
        → 置信度 <70%: memory_inbox.py 进 .synapse/inbox.json 待审

读取:UserPromptSubmit → prefetch_context.py
        → 中文分词 + 话题别名 + 可选 FTS5 BM25
        → 相关节点摘要注入上下文(预算 ~450 token,无匹配则静默)

守护:PreToolUse/PostToolUse → MAP-first 协议提醒、影响面提示、节点 frontmatter 校验
```

适配器只做生命周期归一化,**不含记忆策略**——策略全部在共享脚本里(见 [adapters/README.md](adapters/README.md))。新增宿主 = 在 `adapters/hosts/` 丢一个含 `NAME / ALIASES / detect / install` 的 Python 模块。

---

## 四个 Skill(独立可安装,按需选择)

| Skill | 功能 | 安装场景 |
|-------|------|---------|
| **[synapse-graph-memory](synapse-graph-memory/)** | 核心引擎——检索协议 + 链路追踪 + 无感读写(canonical) | 所有场景必装 |
| **[synapse-timeline](synapse-timeline/)** | 只读时间线 & Open Issues 查询 | 只要"最近改了啥" |
| **[synapse-daily-note](synapse-daily-note/)** | NL → 记忆写入管线 | 手动记录 |
| **[synapse-init](synapse-init/)** | 冷启动向导(薄 wrapper,委托核心引擎) | 新项目/已有项目初始化 |

## 全栈 7 类节点

| 类型 | 前缀 | 示例 |
|------|------|------|
| 项目 | `proj_` | `proj_project`——锚点、状态、范围 |
| 模块 | `mod_` | `mod_auth`——服务或包边界 |
| 功能 | `feat_` | `feat_checkout`——业务能力 |
| 数据库表 | `db_` | `db_orders`——字段、索引、外键 |
| API 端点组 | `api_` | `api_payment-routes`——按 router 文件分组 |
| UI 页面 | `ui_` | `ui_checkout-page`——页面状态、API 调用 |
| 部署单元 | `dep_` | `dep_container-config`——环境变量桥接 |

```bash
init.sh --fullstack   # 四层扫描:DB schema → API 路由 → UI 页面 → 部署配置
```

## 单一来源构建

```bash
python scripts/build_dist.py            # 把 canonical 脚本同步进各 Skill
python scripts/build_dist.py --check    # 漂移检查(CI 门禁)
python scripts/build_dist.py --package  # 重新打包 4 个 .skill
```

规则见 `scripts/dist-manifest.json`(synapse-init 的 `init.sh` 委托 wrapper 通过 `keep` 保留)。**不要手改各 Skill 里的同步副本。**

---

## 基准数据

> **数据出处**:v1.0 表来自 2 条实跑 eval 记录([EVAL_REPORT.md](EVAL_REPORT.md) 与 `synapse-graph-memory-workspace/`);v1.2/v1.4 的性能与准确率数字为**理论测算/模拟数据,非实测基准**。可复现的离线测试在 `tests/`。

### v1.0 基线(8 节点测试项目,deepseek-v4-pro,实跑)

| 指标 | 装 Skill | 不装 | 变化 |
|------|---------|------|------|
| 平均读取文件数 | **8.0** | 13.0 | **-38%** |
| 无关文件 | **0** | 4.5 | 核心优势 |
| 断言通过率 | **100%** | 62.5% | — |

核心收益是**读取纪律**:不装 Skill 时 Agent 出于保险把 MAP、缓存、全部节点都读一遍;装了之后按需加载。30+ 模块时差距进一步拉大——暴力加载随模块数线性增长,受限 BFS 保持常数级。

## 平台与依赖

- **Windows**(Git Bash/MSYS)、**macOS**(bash 4+:`brew install bash`)、**Linux**
- Python 3.8+,仅标准库;解释器自动发现(`PYTHON_BIN` → `python3` → `python`)
- Claude Code(hooks)或任意支持 AGENTS.md 的编码智能体

## 仓库结构

```
synapse-graph-skills/
├── synapse-graph-memory/     # 核心引擎(canonical)——检索、BFS、SQLite、预取、自动写入
│   ├── SKILL.md              # 检索协议 + 自主写入规则
│   ├── references/           # 节点规范、补丁规则、全栈节点类型
│   └── scripts/              # 26 个脚本:MAP、doctor、watch、auto_observe、prefetch 等
├── synapse-timeline/         # 只读时间线(脚本由 build_dist 同步)
├── synapse-daily-note/       # NL → 记忆写入管线(脚本由 build_dist 同步)
├── synapse-init/             # 冷启动向导(薄 wrapper;脚本由 build_dist 同步)
├── adapters/                 # 可插拔宿主适配器 + 安装器
├── scripts/                  # build_dist.py 单一来源构建 + manifest
├── tests/                    # 离线测试套件(CI 在 Ubuntu + Windows 上跑)
├── docs/                     # 架构、贡献指南、设计文档
├── EVOLUTION.md              # 版本演化日志
├── EVAL_REPORT.md            # eval 实跑记录
├── USAGE.md                  # 详细使用指南
├── README.md                 # 英文 README
└── README.zh-CN.md           # 本文件
```

## 文档索引

- [使用指南](USAGE.md) / [架构文档](docs/architecture.md) / [Skills 总览](docs/skills-overview.md)
- [宿主适配器契约](adapters/README.md)——含"如何新增一个宿主"
- [演化日志](EVOLUTION.md) · [v1.5 发布博客](docs/synapse-v1.5-release-blog.zh-CN.md)
- [v2 双宿主 Proposal 协议设计](docs/superpowers/specs/2026-07-10-synapse-v2-dual-host-foundation-design.md)(下一步)

## 贡献

详见 [docs/contributing.md](docs/contributing.md)。改核心脚本后跑:`python scripts/build_dist.py && bash tests/test_legacy_capabilities.sh`。

## 🙏 致谢

感谢 [Linux.do 社区](https://linux.do/)的讨论与反馈;记忆写入的生命周期设计受益于 [Nous Research Hermes Agent](https://github.com/NousResearch/hermes-agent) 的启发。

## 许可证

MIT——详见 [LICENSE](LICENSE)。

---

**Synapse Graph Skills (v1.5)**——图拓扑记忆,让你的 AI 助手知道你上周做了什么,不需要你再解释一遍。**context 不应该随模块数爆炸,记忆不应该依赖人记住去记录,也不应该绑定在某一个智能体上。**
