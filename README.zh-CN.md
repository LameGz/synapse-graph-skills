# Synapse Graph Skills

**把项目结构、变更与决策写成可检查的文件记忆，让编码智能体按需找回上下文。**

[English](README.md) · [使用指南](USAGE.md) · [架构](docs/architecture.md) · [宿主适配器](adapters/README.md) · [CI](https://github.com/LameGz/synapse-graph-skills/actions)

工程事实保存在 `meta/*.md` 节点中，`MEMORY_MAP.md` 与 `MEMORY_MAP.json` 由节点生成，SQLite 用作可重建的检索缓存。项目、模块、功能、数据库、API、页面和部署节点通过关系连接，帮助回答“上次改了什么”“改这里会影响哪里”。

## 快速开始

需要 Git、Bash 4+ 和 Python。CI 验证 Python 3.12 的 Windows/Linux 环境；核心脚本使用 Python 标准库，无需安装 pip 或 npm 运行时依赖。Windows 使用 Git Bash/MSYS，macOS 需另备 Bash 4+。

在 Git Bash 或其他 Bash 4+ 终端执行：

```bash
git clone https://github.com/LameGz/synapse-graph-skills.git
cd synapse-graph-skills
bash synapse-graph-memory/scripts/init.sh --project "/absolute/path/to/your-project"
python adapters/install_adapter.py claude-code --project "/absolute/path/to/your-project"
```

目标项目目录必须已存在；全栈扫描可在 `init.sh` 后增加 `--fullstack`。初始化生成记忆节点与索引，适配器为该项目注册宿主指令或 hooks。先检查生成内容，再纳入项目版本控制。

上例让 hooks 引用本仓库中的脚本，请保留该目录。也可以把核心技能安装到固定位置，再通过 `--synapse-root "/path/to/synapse-graph-memory"` 指定。只有 `.skill` 包时，需按宿主方式安装技能；适配器安装器本身在本仓库的 `adapters/` 中。

## 选择宿主

```bash
python adapters/install_adapter.py list
python adapters/install_adapter.py codex --project "/absolute/path/to/your-project"
```

| 宿主 | 实际接入方式 |
|---|---|
| Claude Code | `.claude/settings.json`：提问预取、读写提示、会话结束提案处理 |
| Codex、Pi、Zed、OpenCode、Cursor 等 | `AGENTS.md` 托管指令段，依赖宿主执行指令 |
| Gemini CLI | `GEMINI.md` 托管指令段 |
| 通用宿主 | `.synapse/agent-instructions.md`，由使用者接线 |

`auto` 可探测宿主，多个宿主共存时宜显式选择。Claude 适配器使用 `CLAUDE_PROJECT_DIR`，重新安装会更新自身旧 hook 并保留自定义 hook；SessionEnd 配置 60 秒预算。配置可安装不代表所有宿主行为均已端到端验收。

## 读取与写入的规则

读取顺序是 **MAP → 相关节点 → 有界邻域**。检索展开限制深度与宽度（depth ≤ 2、width ≤ 5），减少无关内容；节点自身大小、索引生成和检索仍有成本，不承诺项目变大后总成本恒定。

Claude 的提问 hook 可以预取相关摘要；其他适配器靠指令约定执行。预取无匹配时可无输出。摘要进入宿主上下文后的处理位置取决于宿主与模型配置，本地文件存储不等于上下文永不离机。

SessionEnd 的自动路径按来源与目标分流：

| 提案 | 去向 |
|---|---|
| `git_diff` / `hook` 来源、置信度至少 70、目标节点存在 | 校验目标后按原结构化对象写入该节点 |
| 用户对话信号 | Memory Inbox 待审 |
| 未知目标或低置信度 | Memory Inbox 待审 |
| 助手与工具结果文本 | 不作为该对话抽取路径的用户决策来源 |

这里的置信度是规则评分，不是统计校准过的概率。对话抽取使用启发式规则，可能漏记。每次处理使用独立提案目录，高低分桶都写入当前结果，包括空集合，避免复用上一轮文件。

## 查看与人工记录

以下命令从本仓库根目录执行，`--project` 始终指向目标项目：

```bash
python synapse-graph-memory/scripts/project_resume.py --project "/absolute/path/to/your-project"
python synapse-graph-memory/scripts/memory_inbox.py list --project "/absolute/path/to/your-project"
```

检查一条待审提案及其来源后，使用列表中的实际 ID 应用：

```bash
python synapse-graph-memory/scripts/memory_inbox.py apply --project "/absolute/path/to/your-project" --id ITEM_ID
python synapse-graph-memory/scripts/generate_memory_map.py --project "/absolute/path/to/your-project" --full
```

手动记录可先生成提案预览，显式节点标记保留目标：

```bash
bash synapse-graph-memory/scripts/synapse_note.sh --project "/absolute/path/to/your-project" --text "[mod_billing] 发票接口增加分页" --dry-run
```

将 `mod_billing` 换为项目中存在的节点。移除 `--dry-run` 后进入正常提案应用流程；不要把未经核实的讨论当成已实现的工程事实。

## 文件与技能

| 文件 | 职责 |
|---|---|
| `meta/*.md` | 工程记忆事实源：摘要、关系、变更记录和待办问题 |
| `MEMORY_MAP.md`、`MEMORY_MAP.json` | 生成索引，不作为独立事实维护 |
| `.synapse/inbox.json` | 等待检查与应用的提案 |
| `.synapse/adapter.json` | 安装的宿主与引擎位置 |
| `.claude/.synapse_cache/auto-proposals/` | 逐次处理的提案分桶 |

四个技能可按宿主需要独立安装：

| 技能 | 用途 |
|---|---|
| [synapse-graph-memory](synapse-graph-memory/) | 核心检索、图节点、预取与写入策略 |
| [synapse-timeline](synapse-timeline/) | 时间线与 Open Issues 查询 |
| [synapse-daily-note](synapse-daily-note/) | 自然语言到记忆提案的手动记录流程 |
| [synapse-init](synapse-init/) | 初始化向导，委托核心脚本 |

## 与另外两个项目协作

[agent-tree](https://github.com/LameGz/agent-tree) 保存任务执行与验收证据，可显式导出 Synapse 兼容节点与关系；Synapse 保存供后续会话查阅的工程记忆。[Dream Layer](https://github.com/LameGz/dream-layer) 生成探索性观察；其输出需要人判断后才能进入工程记忆。三个仓库分别安装，没有默认自动串联所有写入。

## 开发与验证

`synapse-graph-memory/scripts/` 是共享脚本的唯一维护来源。分发规则见 [scripts/dist-manifest.json](scripts/dist-manifest.json)，不要分别修改其他技能中的同步副本。

```bash
python scripts/build_dist.py --check
bash tests/test_runner.sh --all
bash tests/test_generate_memory_map_py.sh
bash tests/test_suggest_edges_fast.sh
bash tests/test_suggest_edges_dedup.sh
python tests/test_memory_inbox.py
python tests/test_project_resume.py
python tests/test_audit_regressions.py
bash tests/test_legacy_capabilities.sh
```

改共享脚本后先运行 `python scripts/build_dist.py` 同步；发布技能包时运行 `python scripts/build_dist.py --package`。四个 `.skill` 文件是分发产物。

2026-10-16：14 项 Python 测试通过（含 8 项审计回归），MAP、边建议、legacy 与分发检查通过；GitHub Actions 的 14 个检查全部成功，包含 Windows/Linux 离线套件及适配器检查。`test_runner.sh --all` 的完整 eval 为 dry-run，不是模型质量实测。

[EVAL_REPORT.md](EVAL_REPORT.md) 保留历史小样本记录，不能据此承诺一般准确率或规模化收益。真实宿主会话、并发行为和大型项目效果仍需在目标环境验证。

更多资料：[技能总览](docs/skills-overview.md)、[贡献指南](docs/contributing.md)、[演化记录](EVOLUTION.md)。

## 致谢与许可

感谢 [Linux.do](https://linux.do/) 社区的讨论；记忆写入生命周期参考了 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 的相关设计。

[MIT License](LICENSE)。
