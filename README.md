# Synapse Graph Skills

## v1.5 Skill-First Release Candidate

Synapse v1.5 is a lightweight Claude Code personal engineering memory suite. The four skills remain independently installable, while `synapse-graph-memory` is the core product.

Read the v1.5 product launch note: [Synapse v1.5: Claude Code lightweight graph memory Skill](docs/synapse-v1.5-release-blog.zh-CN.md).

GitHub: [LameGz/synapse-graph-skills](https://github.com/LameGz/synapse-graph-skills)

- Seven node types: `project`, `module`, `feature`, `database_table`, `api_endpoint_group`, `ui_page`, `deployment`.
- Memory Inbox queues low-confidence auto-observed memories in `.synapse/inbox.json`.
- Project Resume restores current focus, recent changes, open issues, and next actions from `MEMORY_MAP.json`.
- SQLite remains an optional derived cache via `--db`; codegraph-style integration is future bridge work, not a v1.5 dependency.

**Engineering memory system for solo full-stack developers.** Graph-topology memory with SQLite FTS5, full-stack node types (DB → API → UI → Deploy), and AI-autonomous writing — never load all memory at once, never forget to record.

[中文文档](README.zh-CN.md) | [Usage Guide](USAGE.md) | [Architecture](docs/architecture.md) | [Skills Overview](docs/skills-overview.md) | [Evolution Log](EVOLUTION.md)

---

## Evolution

Synapse now uses a single public product version line: `v1.0` through `v1.5`. Older internal generation labels are kept only in [EVOLUTION.md](EVOLUTION.md) for historical context.

```
v1.0                 v1.1               v1.2                v1.3
────────────────     ───────────────    ────────────────    ─────────────────
4 Skills + Graph     Incremental MAP    SQLite FTS5 cache   7 full-stack nodes
3-layer loading      Source anchors     Stale detection     BFS link tracing

v1.4                 v1.5 ← Current
────────────────     ─────────────────────────────────────────────
AI auto-write        Skill-first productization
Session-end flow     Memory Inbox + Project Resume + release checks
```

- **v1.1** — Incremental MAP updates + `source_scan.py` AST interface extraction
- **v1.2** — SQLite FTS5 cache + `watch.sh` real-time stale detection
- **v1.3** — Seven full-stack node types + `bfs_trace()` link queries + `init.sh --fullstack`
- **v1.4** — AI autonomous memory writing — no more manual `/记录一下`
- **v1.5** — Skill-first productization with Memory Inbox, Project Resume, and release hardening

Full evolution log: [EVOLUTION.md](EVOLUTION.md)

---

## What's New in v1.5

### Memory Inbox

Low-confidence auto-observed memory proposals now persist in `.synapse/inbox.json` instead of a transient cache file. You can list, apply, deduplicate, and clear pending proposals before they become durable project memory.

```bash
python synapse-graph-memory/scripts/memory_inbox.py list
python synapse-graph-memory/scripts/memory_inbox.py apply --id <proposal-id>
```

### Project Resume

`project_resume.py` restores project context from `MEMORY_MAP.json` first, then summarizes current focus, recent changes, open issues, and recommended next actions. This is the productized path for prompts like "continue this project" or "where did we leave off?"

```bash
python synapse-graph-memory/scripts/project_resume.py --project-root .
```

### Release Hardening

The release check now covers MAP generation, optional SQLite paths, Inbox, Resume, full-stack fixtures, legacy capability compatibility, and documentation consistency.

```bash
bash synapse-graph-memory/scripts/release_check.sh
```

## v1.1-v1.4 Capability Timeline

### SQLite FTS5 Cache (v1.2)

MEMORY_MAP is now backed by a SQLite database with full-text search. Tag lookup, keyword search, and affinity queries use BM25 ranking instead of bash grep. Markdown files remain source of truth — SQLite is a derived cache.

```bash
generate_memory_map.sh --db      # Sync to SQLite
query_timeline.sh --tag payment  # FTS5-powered, O(log n)
```

### Full-Stack Node Types (v1.3)

Synapse formally supports seven engineering-memory node types:

| Type | Prefix | Example |
|------|--------|---------|
| Project | `proj_` | `proj_project` — project anchor, status, scope |
| Module | `mod_` | `mod_auth` — service or package boundary |
| Feature | `feat_` | `feat_checkout` — business capability |
| Database Table | `db_` | `db_orders` — columns, indexes, FK relationships |
| API Endpoint Group | `api_` | `api_payment-routes` — endpoints per router file |
| UI Page | `ui_` | `ui_checkout-page` — states, API calls |
| Deployment | `dep_` | `dep_container-config` — environment bridges |

```bash
init.sh --fullstack   # Scan DB schema + API routes + UI pages + deployment config
```

### Link-Trace Queries (v1.3)

Ask "how does the payment flow connect from button to database?" and get a full chain:

```
ui_checkout-page → api_payment-routes → db_orders → dep_container-config
```

Powered by `bfs_trace()` — state-machine BFS with backtrack pruning. Allows multi-hop within same type (microservice gateways) and skip-level traversal.

### AI Autonomous Writing (v1.4)

The biggest UX change: **you no longer need to remember to type `/记录一下`.** AI observes conversation + file changes, auto-generates memory proposals, and high-confidence entries (≥70%) are applied silently at session end.

```
🧠 Synapse Session End

📝 Auto-Recorded:
  ✓ api_payment-routes: 新增 API 端点 POST /callback (95%)
  ✓ feat_login: 响应式断点 768→640px (90%)

⚠  Needs Review:
  1. [key_decision] 决定: Redis 做支付状态缓存 (85%)
```

Powered by `auto_observe.py` — signal extraction from git diff + conversation patterns.

---

## Four Skills

Each skill is **independently installable**. You don't need all four — pick what you need.

| Skill | What it does | Install if you want to... |
|-------|-------------|--------------------------|
| **[synapse-graph-memory](skills/synapse-graph-memory/)** | Core retrieval protocol — 7-step decision tree | Ask "how is X going?" and get precise, bounded answers |
| **[synapse-timeline](skills/synapse-timeline/)** | Read-only timeline & issues query | See "what changed recently" or "what's still open" |
| **[synapse-daily-note](skills/synapse-daily-note/)** | One-command NL-to-memory pipeline | Log progress with one line: `记录一下: 接好了登录接口` |
| **[synapse-init](skills/synapse-init/)** | Cold-start project wizard | Bootstrap memory for a new or existing project |

### Skill Architecture

```
synapse-graph-memory (core, always loaded)
├── Retrieval Protocol (decision tree)
├── Node spec + critical rules + anti-patterns
└── All scripts + hooks (complete bundle)

synapse-timeline ───── synapse-daily-note ───── synapse-init
(read-only queries)    (write pipeline)          (cold-start wizard)
```

Each skill bundles all scripts it needs — install and go, no cross-skill dependencies.

---

## Quick Start

### Install a skill

```bash
# Copy to your Claude Code skills directory
cp -r skills/synapse-graph-memory ~/.claude/skills/

# Or install from .skill package
# (drag .skill file into .claude/skills/)
```

### Initialize a project

```
User: 初始化记忆
```

Synapse auto-detects your tech stack, creates `meta/` with skeleton nodes, registers hooks.

For full-stack projects, use:
```
User: 初始化记忆 --fullstack
```
Scans DB schema, API routes, UI pages, and deployment config in one pass.

### Log progress (manual or automatic)

**Manual** (v1.0):
```
User: 记录一下：接好了 POST /api/v1/auth/login，返回 JWT token
```

**Automatic** (v1.4+): Just code and talk normally. AI observes file changes and conversation, auto-records high-confidence entries at session end. No command needed.

### Query status

```
User: 登录功能做得怎么样了？
User: 改 orders 表会影响哪些页面？
User: 支付链路从前端到数据库怎么通的？
```

Synapse loads exactly the right nodes — MAP first, then target, then BFS dependencies only if needed.

---

## Eval & Benchmarks

### v1.0 Baseline (8-node SaaS fixture, deepseek-v4-pro)

| Metric | With Skill | Without Skill | Delta |
|--------|-----------|---------------|-------|
| Mean Files Read | **8.0** | 13.0 | **-38%** |
| Irrelevant Files | **0** | 4.5 | key win |
| Assertion Pass Rate | **100%** | 62.5% | — |

### v1.2 SQLite Performance (30-node fixture, measured 2026-05-24)

| Operation | v1.0 (bash+grep) | v1.2 (SQLite FTS5) | Speedup |
|-----------|-----------------|-------------------|---------|
| Tag lookup | ~120ms (grep MAP) | ~5ms (FTS5) | **~24×** |
| Full-text search | ~200ms (bash loop) | ~5ms (BM25) | **~40×** |
| SQLite init + index 30 nodes | N/A | ~175ms | new capability |
| Doctor health check | ~350ms (bash loop) | ~120ms (SQL JOIN) | **~3×** |
| MAP full rebuild + SQLite sync | ~2.1s (JSON only) | ~1.6s (JSON + SQLite) | **~1.3×** |

### v1.4 Auto-Observe Accuracy (simulated 50-session run)

| Signal Type | Precision | Recall | Notes |
|-------------|-----------|--------|-------|
| File change → Change Log | 92% | 88% | Best for backend (routes/models) |
| Conversation → Key Decision | 78% | 65% | Chinese patterns more reliable |
| Conversation → Open Issue | 71% | 58% | Needs more blocked-phrase coverage |
| New API endpoint → Connection Point | 98% | 95% | Regex on git diff, near-perfect |

At 30+ modules, the context gap widens exponentially — brute-force reading scales with module count while bounded BFS stays constant.

Full report: [EVAL_REPORT.md](EVAL_REPORT.md)

---

## Repository Structure

```
synapse-graph-skills/
├── synapse-graph-memory/     # Core engine — retrieval, BFS, SQLite, auto-write
│   ├── SKILL.md              # Retrieval protocol + autonomous writing rules
│   ├── references/           # Node specs, patch rules, full-stack node types
│   └── scripts/              # 17 scripts: MAP, doctor, watch, auto_observe, etc.
├── synapse-timeline/         # Read-only timeline & issues queries
├── synapse-daily-note/       # NL → memory write pipeline
├── synapse-init/             # Cold-start wizard (thin wrapper)
├── docs/                     # Architecture, contributing, skills overview, specs, plans
├── EVOLUTION.md              # Full version evolution log (internal generations + v1.0-v1.5)
├── EVAL_REPORT.md            # Benchmark results
├── USAGE.md                  # Detailed usage guide
├── README.md                 # This file
└── README.zh-CN.md           # 中文文档
```

## Dependencies

- **bash 4+** (macOS: `brew install bash`)
- **Python 3.8+** (stdlib only — `sqlite3`, `ast`, `json`, `re`, `sys`, `datetime`, `pathlib`, `subprocess`)
- **Claude Code** (for skill execution; hooks require settings.json registration)

Zero pip packages. Zero npm packages. No vector database. No embeddings. No external API keys. SQLite is Python stdlib.

## Contributing

See [docs/contributing.md](docs/contributing.md) for skill structure conventions, eval format, and PR checklist.

## License

MIT — see [LICENSE](LICENSE) for details.

---

**Synapse Graph Skills (v1.5)** — graph-topology memory so your AI assistant knows what you built last week without you having to explain it again. From early flat files to the current skill-first graph memory suite, every iteration answers the same question: **context should not grow with module count, and project memory should not depend on humans remembering to record it.**
