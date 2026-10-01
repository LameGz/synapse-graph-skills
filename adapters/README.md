# Synapse Host Adapters(可插拔宿主适配层)

Synapse 的记忆策略全部在共享脚本里(`synapse-graph-memory/scripts/`);适配层只做一件事:**把不同智能体宿主的生命周期事件归一化到这些脚本上**。这与 `docs/superpowers/specs/2026-07-10-synapse-v2-dual-host-foundation-design.md` 的原则一致:*"Host adapters normalize lifecycle events but contain no memory policy."*

## 适配的三层接入能力

| 宿主能力 | 接入方式 | 无感程度 |
|---|---|---|
| 有 hooks 系统(Claude Code) | 注册 SessionEnd / UserPromptSubmit / PreToolUse / PostToolUse | 完全无感(读写自动) |
| 只认 AGENTS.md(Codex CLI、Gemini CLI、Pi、Zed、OpenCode、Cursor…) | 托管指令段(带 `<!-- synapse:begin/end -->` 标记,重装幂等) | 半无感(按指令自动执行,无需用户敲命令) |
| 都没有 | `.synapse/agent-instructions.md` + 手动接线说明 | 手动 |

## 使用

```bash
python adapters/install_adapter.py list                     # 查看可用适配器
python adapters/install_adapter.py auto --project .         # 自动探测并安装
python adapters/install_adapter.py claude-code --project .
python adapters/install_adapter.py codex --project .
python adapters/install_adapter.py gemini-cli --project .
python adapters/install_adapter.py pi --project .
python adapters/install_adapter.py generic --project .
```

安装完成后写入 `.synapse/adapter.json` 标记(记录宿主、引擎路径、时间)。卸载:删除对应配置段/标记即可;AGENTS.md 中删除 `synapse:begin/end` 之间的内容。

## 新增一个宿主适配器

在 `hosts/` 下新建 `myhost.py`,暴露四个成员即可,安装器自动发现,无需改任何注册代码:

```python
NAME = "myhost"
ALIASES = ["myhost-alias"]

def describe() -> str: ...

def detect(project) -> bool: ...   # auto 模式探测

def install(project, synapse_root) -> list[str]: ...
    # 写配置,返回相对 project 的已写文件列表
```

`registry.json` 是给人看和给 CI 用的镜像文档,不改也能运行。

## 与 v1.5 hooks 的关系

Claude Code 适配器注册的 hooks 就是 v1.5 的四个 hooks 脚本加上新的 `prefetch_context.py`:

- **UserPromptSubmit → prefetch_context.py**(新增):把与用户提问相关的记忆节点摘要注入上下文——"读取无感"。详见 `synapse-graph-memory/scripts/prefetch_context.py` 模块注释。
- **SessionEnd → session-end.sh**:会话结束自动记录 + 重建 MAP——"写入无感"。默认注册在 SessionEnd 事件(每会话一次);如果希望"每轮可见摘要"的旧行为,把它手动改挂到 Stop 事件即可,脚本对两种事件都兼容。
