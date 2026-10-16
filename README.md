# Synapse Graph Skills

**Keep project structure, changes and decisions in inspectable files, so coding agents can retrieve the context they need.**

[中文](README.zh-CN.md) · [Usage](USAGE.md) · [Architecture](docs/architecture.md) · [Host adapters](adapters/README.md) · [CI](https://github.com/LameGz/synapse-graph-skills/actions)

Engineering facts live in `meta/*.md` nodes. `MEMORY_MAP.md` and `MEMORY_MAP.json` are generated indexes; SQLite is a rebuildable retrieval cache. Relations connect projects, modules, features, database tables, APIs, pages and deployment units, helping agents answer “what changed?” and “what does this affect?” across sessions.

## Quick start

Requires Git, Bash 4+ and Python. CI validates Python 3.12 on Windows/Linux. Core scripts use the Python standard library, with no pip or npm runtime packages. Use Git Bash/MSYS on Windows and provide Bash 4+ separately on macOS.

Run in Git Bash or another Bash 4+ terminal:

```bash
git clone https://github.com/LameGz/synapse-graph-skills.git
cd synapse-graph-skills
bash synapse-graph-memory/scripts/init.sh --project "/absolute/path/to/your-project"
python adapters/install_adapter.py claude-code --project "/absolute/path/to/your-project"
```

The target directory must already exist. Add `--fullstack` to `init.sh` for full-stack scanning. Initialization creates nodes and indexes; the adapter registers project instructions or hooks. Inspect generated files before committing them to your project.

These hooks reference scripts in this checkout, so keep it at a stable location. Alternatively, install the core skill elsewhere and pass `--synapse-root "/path/to/synapse-graph-memory"`. A `.skill` archive follows the host's skill-installation flow; the adapter installer itself lives in this repository's `adapters/` directory.

## Choose a host

```bash
python adapters/install_adapter.py list
python adapters/install_adapter.py codex --project "/absolute/path/to/your-project"
```

| Host | Integration |
|---|---|
| Claude Code | `.claude/settings.json`: prompt prefetch, read/write guidance, end-of-session proposals |
| Codex, Pi, Zed, OpenCode, Cursor and aliases | Managed `AGENTS.md` section; relies on the host following instructions |
| Gemini CLI | Managed `GEMINI.md` section |
| Generic | `.synapse/agent-instructions.md`, connected by the user |

`auto` detects a host; choose explicitly when several hosts share a project. The Claude adapter uses `CLAUDE_PROJECT_DIR`. Reinstalling updates its own older hooks while retaining custom hooks, and sets a 60-second SessionEnd budget. Successful installation does not establish end-to-end behavior in every host.

## Reading and writing rules

Read **MAP → relevant nodes → bounded neighborhood**. Retrieval bounds traversal depth and width (depth ≤ 2, width ≤ 5) to limit unrelated context. Node size, indexing and search still have costs; total cost is not guaranteed to remain constant as a project grows.

Claude's prompt hook can prefetch summaries; other adapters provide an instruction-driven workflow. No match may produce no output. Once summaries enter host context, their processing location depends on the host and model configuration. Local file storage does not guarantee that context stays on the machine.

The SessionEnd path routes proposals by source and target:

| Proposal | Destination |
|---|---|
| `git_diff` / `hook` source, score at least 70, existing target | Validate the target and apply the original structured proposal there |
| User conversation signal | Memory Inbox for review |
| Unknown target or lower score | Memory Inbox for review |
| Assistant and tool-result text | Excluded from user-decision extraction in this transcript path |

Confidence is a heuristic score, not a calibrated probability. Conversation extraction can miss decisions. Each invocation gets a separate proposal directory, and both partitions are written even when empty, preventing reuse of an earlier invocation's files.

## Inspect and record

Run these commands from this checkout, always passing the target project:

```bash
python synapse-graph-memory/scripts/project_resume.py --project "/absolute/path/to/your-project"
python synapse-graph-memory/scripts/memory_inbox.py list --project "/absolute/path/to/your-project"
```

After inspecting an item and its source, apply its actual ID from the list:

```bash
python synapse-graph-memory/scripts/memory_inbox.py apply --project "/absolute/path/to/your-project" --id ITEM_ID
python synapse-graph-memory/scripts/generate_memory_map.py --project "/absolute/path/to/your-project" --full
```

For manual recording, preview a proposal first. An explicit node marker preserves the target:

```bash
bash synapse-graph-memory/scripts/synapse_note.sh --project "/absolute/path/to/your-project" --text "[mod_billing] Added pagination to invoice endpoints" --dry-run
```

Replace `mod_billing` with an existing node. Remove `--dry-run` for the normal proposal application flow. Discussion alone should not be recorded as completed engineering work.

## Files and skills

| File | Responsibility |
|---|---|
| `meta/*.md` | Engineering memory: summaries, relations, changes and open issues |
| `MEMORY_MAP.md`, `MEMORY_MAP.json` | Generated indexes, rather than separately maintained facts |
| `.synapse/inbox.json` | Proposals waiting for inspection and application |
| `.synapse/adapter.json` | Installed host and engine location |
| `.claude/.synapse_cache/auto-proposals/` | Per-invocation proposal partitions |

Install the four skills independently as supported by your host:

| Skill | Purpose |
|---|---|
| [synapse-graph-memory](synapse-graph-memory/) | Core retrieval, nodes, prefetch and writing policy |
| [synapse-timeline](synapse-timeline/) | Timeline and Open Issues queries |
| [synapse-daily-note](synapse-daily-note/) | Manual natural-language-to-proposal workflow |
| [synapse-init](synapse-init/) | Initialization wizard delegating to the core |

## Working with the other projects

[agent-tree](https://github.com/LameGz/agent-tree) stores task execution and acceptance evidence, and can explicitly export Synapse-compatible nodes and relations. Synapse stores engineering memory for later sessions. [Dream Layer](https://github.com/LameGz/dream-layer) produces exploratory observations, which require human judgment before becoming engineering memory. These repositories install separately; there is no default pipeline that automatically connects every write.

## Development and validation

`synapse-graph-memory/scripts/` is the maintenance source for shared scripts. Distribution rules live in [scripts/dist-manifest.json](scripts/dist-manifest.json); do not edit synchronized copies independently.

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

After editing shared scripts, run `python scripts/build_dist.py` to synchronize copies. Run `python scripts/build_dist.py --package` to rebuild the four `.skill` distribution archives.

On 2026-10-16, 14 Python tests passed, including eight audit regressions. MAP, edge-suggestion, legacy and distribution checks passed. All 14 GitHub Actions checks succeeded, including Windows/Linux offline suites and adapter checks. The full eval runner in `test_runner.sh --all` is a dry-run, not a model-quality benchmark.

[EVAL_REPORT.md](EVAL_REPORT.md) preserves historical small-sample results, which do not establish general accuracy or scaling gains. Real host sessions, concurrent behavior and large-project results require validation in the target environment.

More documentation: [Skills overview](docs/skills-overview.md), [Contributing](docs/contributing.md), [Evolution](EVOLUTION.md).

## Acknowledgments and license

Thanks to the [Linux.do](https://linux.do/) community for discussion. The memory-write lifecycle draws on related design ideas from [Hermes Agent](https://github.com/NousResearch/hermes-agent).

[MIT License](LICENSE).
