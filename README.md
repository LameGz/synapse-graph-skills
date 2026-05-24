# Synapse Graph Skills

**Engineering memory system for solo full-stack developers.** Graph-topology memory with SQLite FTS5, full-stack node types (DB → API → UI → Deploy), and AI-autonomous writing — never load all memory at once, never forget to record.

[中文文档](README.zh-CN.md) | [Usage Guide](USAGE.md) | [Architecture](docs/architecture.md) | [Skills Overview](docs/skills-overview.md) | [Evolution Log](EVOLUTION.md)

---

## Evolution

Synapse has evolved through four generations, with V3.1-V3.4 adding major capabilities:

```
V1 (2024)           V2 (2025)          V3.0 (2026-05)      V3.1–V3.4 (2026-05) ← Current
────────────────    ───────────────    ────────────────    ──────────────────────
Flat Markdown        Monolithic Agent    4 Skills + Graph    +SQLite +Full-Stack +Auto-Write
grep search          Keyword search      3-Layer BFS         Incremental MAP
No edges             Implicit edges      Explicit edges      FTS5 BM25 search
~10 nodes            ~15 nodes           30+ nodes           Stale detection
                                                            AI autonomous writing
```

**V3.1** — Incremental MAP updates + `source_scan.py` AST interface extraction  
**V3.2** — SQLite FTS5 cache + `watch.sh` real-time stale detection  
**V3.3** — Full-stack node types (db_/api_/ui_/dep_) + `bfs_trace()` link queries + `init.sh --fullstack`  
**V3.4** — AI autonomous memory writing — no more manual `/记录一下`

Full evolution log: [EVOLUTION.md](EVOLUTION.md)

---

## What's New in V3.1–V3.4

### SQLite FTS5 Cache (V3.2)

MEMORY_MAP is now backed by a SQLite database with full-text search. Tag lookup, keyword search, and affinity queries use BM25 ranking instead of bash grep. Markdown files remain source of truth — SQLite is a derived cache.

```bash
generate_memory_map.sh --db      # Sync to SQLite
query_timeline.sh --tag payment  # FTS5-powered, O(log n)
```

### Full-Stack Node Types (V3.3)

Beyond `mod_` (module) and `feat_` (feature), four new node types track the complete stack:

| Type | Prefix | Example |
|------|--------|---------|
| Database Table | `db_` | `db_orders` — columns, indexes, FK relationships |
| API Endpoint Group | `api_` | `api_payment-routes` — endpoints per router file |
| UI Page | `ui_` | `ui_checkout-page` — states, API calls |
| Deployment | `dep_` | `dep_container-config` — environment bridges |

```bash
init.sh --fullstack   # Scan DB schema + API routes + UI pages + deployment config
```

### Link-Trace Queries (V3.3)

Ask "how does the payment flow connect from button to database?" and get a full chain:

```
ui_checkout-page → api_payment-routes → db_orders → dep_container-config
```

Powered by `bfs_trace()` — state-machine BFS with backtrack pruning. Allows multi-hop within same type (microservice gateways) and skip-level traversal.

### AI Autonomous Writing (V3.4)

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

**Manual** (V3.0):
```
User: 记录一下：接好了 POST /api/v1/auth/login，返回 JWT token
```

**Automatic** (V3.4): Just code and talk normally. AI observes file changes and conversation, auto-records high-confidence entries at session end. No command needed.

### Query status

```
User: 登录功能做得怎么样了？
User: 改 orders 表会影响哪些页面？
User: 支付链路从前端到数据库怎么通的？
```

Synapse loads exactly the right nodes — MAP first, then target, then BFS dependencies only if needed.

---

## Eval & Benchmarks

### V3.0 Baseline (8-node SaaS fixture, deepseek-v4-pro)

| Metric | With Skill | Without Skill | Delta |
|--------|-----------|---------------|-------|
| Mean Files Read | **8.0** | 13.0 | **-38%** |
| Irrelevant Files | **0** | 4.5 | key win |
| Assertion Pass Rate | **100%** | 62.5% | — |

### V3.2 SQLite Performance (30-node fixture, measured 2026-05-24)

| Operation | V3.0 (bash+grep) | V3.2 (SQLite FTS5) | Speedup |
|-----------|-----------------|-------------------|---------|
| Tag lookup | ~120ms (grep MAP) | ~5ms (FTS5) | **~24×** |
| Full-text search | ~200ms (bash loop) | ~5ms (BM25) | **~40×** |
| SQLite init + index 30 nodes | N/A | ~175ms | new capability |
| Doctor health check | ~350ms (bash loop) | ~120ms (SQL JOIN) | **~3×** |
| MAP full rebuild + SQLite sync | ~2.1s (JSON only) | ~1.6s (JSON + SQLite) | **~1.3×** |

### V3.4 Auto-Observe Accuracy (simulated 50-session run)

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
├── EVOLUTION.md              # Full version evolution log (V1 → V3.4)
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

**Synapse Graph Skills (V3)** — graph-topology memory so your AI assistant knows what you built last week without you having to explain it again. From V1 flat files to V2 monolithic agent, to V3 graph topology + Skills architecture — every iteration answers the same question: **context should not grow with module count.**
