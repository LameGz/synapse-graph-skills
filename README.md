# Synapse Graph Skills

> **File-based engineering memory for coding agents** — seamless writes, seamless reads, pluggable across hosts. Stop remembering to "log this"; stop re-explaining "where were we last time".

GitHub: [LameGz/synapse-graph-skills](https://github.com/LameGz/synapse-graph-skills) · [中文文档](README.zh-CN.md) · [Usage Guide](USAGE.md) · [Architecture](docs/architecture.md)

---

## The problem it solves

For solo full-stack developers, project memory lives in chat history: it evaporates across sessions, breaks across tools, and collapses into brute-force file re-reading as modules multiply. Synapse turns engineering memory into **`meta/*.md` graph nodes + an auto-generated MEMORY_MAP index** — Markdown is the single source of truth, SQLite is a disposable cache, zero external services.

## Core capabilities (v1.5)

**Seamless in both directions** — the v1.5 theme:

- **Seamless writes (SessionEnd)**: at session end, a hook extracts git changes and user-text conversation signals. High-confidence source changes (≥70%) update their existing target node; conversation signals, unknown targets and low-confidence items queue in the Memory Inbox. Assistant/tool text never becomes an automatic decision.
- **Seamless reads (UserPromptSubmit)**: when you ask something, a hook injects summaries of relevant memory nodes into context — Chinese prompts included (built-in cross-language topic aliases like 支付 → payment). No "load memory" incantation.

**Disciplined retrieval** — MAP first, then the target node, then bounded BFS (depth ≤ 2, width ≤ 5). Context stays flat no matter how many modules you have.

**Pluggable across hosts** — one memory policy, normalized per host lifecycle:

| Host | Integration | Seamlessness |
|------|-------------|--------------|
| Claude Code | hooks (SessionEnd / UserPromptSubmit / PreToolUse / PostToolUse) | fully seamless |
| Codex CLI / Gemini CLI / Pi / Zed / OpenCode / Cursor | managed AGENTS.md section | semi-seamless (instruction-driven) |
| anything else | `.synapse/agent-instructions.md`, wired manually | manual |

**Single-source build** — every script is canonical in `synapse-graph-memory/scripts/`; the other skills' copies are synced at build time by `build_dist.py`, with a `--check` drift gate in CI.

**Zero dependencies** — bash 4+, Python 3.8+ stdlib only (sqlite3/ast/json/re). No pip packages, no npm packages, no external APIs, no vector database.

---

## Quick start

```bash
# 1. Install the core skill
cp -r synapse-graph-memory ~/.claude/skills/

# 2. Initialize memory in your project (add --fullstack for DB+API+UI+deploy scanning)
bash ~/.claude/skills/synapse-graph-memory/scripts/init.sh --project /path/to/project

# 3. Install a host adapter (auto-detect; or explicit: claude-code / codex / gemini-cli / pi / generic)
python adapters/install_adapter.py auto --project /path/to/project
```

Then work normally. To see what was recorded automatically:

```bash
python synapse-graph-memory/scripts/memory_inbox.py list --project .
python synapse-graph-memory/scripts/project_resume.py --project .   # alias: --project-root .
```

Manual recording (rarely needed after v1.4):

```bash
bash synapse-graph-memory/scripts/synapse_note.sh --project . --text "wired up POST /api/v1/auth/login, returns JWT"
```

### Query by asking

```text
User: How is the login feature going?
User: Which pages does changing the orders table affect?
User: How does the payment flow run from frontend button to database?
```

---

## How the seamlessness works

```text
WRITE: SessionEnd → session-end.sh → auto_observe.py (git diff + signal extraction)
         → source change ≥70% + known target: session_memory.py applies structured target + MAP rebuild
         → conversation / unknown target / confidence <70%: Memory Inbox review

READ:  UserPromptSubmit → prefetch_context.py
         → CJK-aware tokenizing + topic aliases + optional FTS5 BM25
         → relevant node summaries injected (~450 token budget; silent when no match)

GUARD: PreToolUse/PostToolUse → MAP-first protocol nudge, impact warning,
         node frontmatter validation
```

Adapters only normalize lifecycle events — **memory policy always lives in the shared scripts** (see [adapters/README.md](adapters/README.md)). Adding a host = dropping a Python module with `NAME / ALIASES / detect / install` into `adapters/hosts/`.

---

## Four skills (independently installable)

| Skill | Purpose | Install when |
|-------|---------|--------------|
| **[synapse-graph-memory](synapse-graph-memory/)** | Core engine — retrieval protocol, link tracing, seamless read/write (canonical) | always |
| **[synapse-timeline](synapse-timeline/)** | Read-only timeline & Open Issues queries | you only want "what changed recently" |
| **[synapse-daily-note](synapse-daily-note/)** | NL → memory write pipeline | you want manual recording |
| **[synapse-init](synapse-init/)** | Cold-start wizard (thin wrapper delegating to the core) | initializing new or existing projects |

## Full-stack node types (7)

| Type | Prefix | Example |
|------|--------|---------|
| Project | `proj_` | `proj_project` — anchor, status, scope |
| Module | `mod_` | `mod_auth` — service or package boundary |
| Feature | `feat_` | `feat_checkout` — business capability |
| DB table | `db_` | `db_orders` — fields, indexes, FKs |
| API endpoints | `api_` | `api_payment-routes` — grouped by router file |
| UI page | `ui_` | `ui_checkout-page` — page state, API calls |
| Deployment | `dep_` | `dep_container-config` — env bridging |

```bash
init.sh --fullstack   # scan DB schema → API routes → UI pages → deploy configs
```

## Single-source build

```bash
python scripts/build_dist.py            # sync canonical scripts into each skill
python scripts/build_dist.py --check    # drift check (CI gate)
python scripts/build_dist.py --package  # rebuild the 4 .skill archives
```

Rules live in `scripts/dist-manifest.json` (synapse-init's delegating `init.sh` is preserved via `keep`). **Never hand-edit synced copies inside dependent skills.**

---

## Benchmarks

> **Data provenance**: the v1.0 table below comes from 2 recorded eval runs ([EVAL_REPORT.md](EVAL_REPORT.md) and `synapse-graph-memory-workspace/`). The v1.2/v1.4 performance and accuracy figures published earlier were **theoretical estimates / simulated data, not measured benchmarks**. Reproducible offline tests live in `tests/`.

### v1.0 baseline (8-node SaaS fixture, deepseek-v4-pro, measured)

| Metric | With Skill | Without Skill | Delta |
|--------|-----------|---------------|-------|
| Mean files read | **8.0** | 13.0 | **-38%** |
| Irrelevant files | **0** | 4.5 | the key win |
| Assertion pass rate | **100%** | 62.5% | — |

The core win is **reading discipline**: without the skill the agent defensively loads the MAP, caches, and every node; with it, loading is on-demand. At 30+ modules the gap widens further — brute-force reading scales linearly while bounded BFS stays constant.

## Platforms & dependencies

- **Windows** (Git Bash/MSYS), **macOS** (bash 4+ via `brew install bash`), **Linux**
- Python 3.8+, stdlib only; interpreter auto-discovery (`PYTHON_BIN` → `python3` → `python`)
- Claude Code (hooks) or any AGENTS.md-spec coding agent

## Repository structure

```text
synapse-graph-skills/
├── synapse-graph-memory/     # Core engine (canonical) — retrieval, BFS, SQLite, prefetch, auto-write
│   ├── SKILL.md              # Retrieval protocol + autonomous writing rules
│   ├── references/           # Node specs, patch rules, full-stack node types
│   └── scripts/              # 26 scripts: MAP, doctor, watch, auto_observe, prefetch, etc.
├── synapse-timeline/         # Read-only timeline (scripts synced by build_dist)
├── synapse-daily-note/       # NL → memory write pipeline (scripts synced by build_dist)
├── synapse-init/             # Cold-start wizard (thin wrapper; scripts synced by build_dist)
├── adapters/                 # Pluggable host adapters + installer
├── scripts/                  # build_dist.py single-source build + manifest
├── tests/                    # Offline test suite (CI runs it on Ubuntu + Windows)
├── docs/                     # Architecture, contributing, design docs
├── EVOLUTION.md              # Version evolution log
├── EVAL_REPORT.md            # Recorded eval runs
├── USAGE.md                  # Detailed usage guide
├── README.md                 # This file
└── README.zh-CN.md           # 中文文档
```

## Documentation index

- [Usage guide](USAGE.md) · [Architecture](docs/architecture.md) · [Skills overview](docs/skills-overview.md)
- [Host adapter contract](adapters/README.md) — includes "how to add a host"
- [Evolution log](EVOLUTION.md) · [v1.5 release blog (中文)](docs/synapse-v1.5-release-blog.zh-CN.md)
- [v2 dual-host Proposal protocol design](docs/superpowers/specs/2026-07-10-synapse-v2-dual-host-foundation-design.md) (next step)

## Contributing

See [docs/contributing.md](docs/contributing.md). After touching core scripts: `python scripts/build_dist.py && bash tests/test_legacy_capabilities.sh`.

## 🙏 Acknowledgements

Thanks to the [Linux.do community](https://linux.do/) for discussion and feedback; the lifecycle design of memory writes draws inspiration from the [Nous Research Hermes Agent](https://github.com/NousResearch/hermes-agent).

## License

MIT — see [LICENSE](LICENSE).

---

**Synapse Graph Skills (v1.5)** — graph-topology memory so your AI assistant knows what you did last week without a briefing. **Context shouldn't explode with module count, memory shouldn't depend on you remembering to record — and it shouldn't be locked to one agent.**
