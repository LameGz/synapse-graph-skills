# Release Notes

## v1.5.0 Skill-First Memory Release Candidate

- Adds `memory_inbox.py` for persistent review of low-confidence memory proposals in `.synapse/inbox.json`.
- Adds `project_resume.py` for MAP-first project context restoration.
- Fixes `generate_memory_map.sh --db` so it uses the fast Python MAP engine before syncing the optional SQLite cache.
- Clarifies the seven node types and changes initialization to create `proj_project` as the project-level anchor.
- Extends release checks with Inbox, Resume, legacy capability, and fast MAP/edge regression tests.

## Versioning

Synapse Graph Skills follows [Semantic Versioning](https://semver.org/). Each skill within the repo shares the repo version but may be released independently.

## Latest Release

### v1.4.0 — 2026-05-24

**AI Autonomous Memory Writing** — the biggest UX change since v1.0. You no longer need to remember to type `/记录一下`. AI observes conversation + file changes, auto-generates memory proposals, and high-confidence entries (≥70%) are applied silently at session end.

- **auto_observe.py** — Signal extraction from git diff + conversation patterns (Chinese + English regex). Maps 16 source file patterns → node IDs. Generates ranked JSON proposals with confidence scores and evidence.
- **synapse_note.sh --auto-confirm** — Skips interactive prompts, enabling silent AI writes through the full pipeline.
- **session-end hook V3.4** — Auto-collects proposals, splits by 70% confidence threshold, auto-applies high-confidence entries, displays low-confidence for review.
- **SKILL.md Autonomous Memory Writing** — Behavior rules telling AI when to auto-write, how, and when not to.
- **critical-rules.md audit rules** — Auto-record markers (`<!-- auto-recorded, confidence: N% -->`), grep audit commands, rollback procedures.

---

## Previous Releases

### v1.3.0 — 2026-05-24

**Single-Project Full-Stack Memory.** The graph engine now supports 7 node types spanning the complete stack.

- **4 new node types**: `db_` (database tables), `api_` (API endpoint groups), `ui_` (frontend pages), `dep_` (deployment units)
- **bfs_trace()** — State-machine BFS with backtrack pruning for link-trace queries ("how does payment flow from button to database?")
- **init.sh --fullstack** — 4-layer cold-start scan: DB schema → API routes → UI pages → deployment config
- **synapse-init thin wrapper** — Reduced from 357 lines to 20. All logic in core engine, transparent passthrough.
- **fullstack-node-spec.md** — Standalone reference with node templates and 4 patch rules.
- **doctor.sh full-stack validation** — Checks db_ skeleton completeness, ui_ dependency overload, dep_ count limits.

### v1.2.0 — 2026-05-24

**SQLite FTS5 Cache + Real-Time Stale Detection.** Indexing and search performance upgraded from bash+grep to SQLite.

- **db_init.py** — SQLite schema with FTS5 virtual table, edge indices, co-occurrence tracking, staleness table.
- **db_index.py** — Node/edge indexer. Reads Markdown frontmatter → writes SQLite. Supports `--full` and `--changed <id>`.
- **generate_memory_map.sh --db** — Dual output: MEMORY_MAP.json + SQLite cache in one pass.
- **query_timeline.sh SQLite path** — Prioritizes SQLite FTS5 queries over bash grep. BM25 ranking for tag/keyword search.
- **doctor.sh SQL JOINs** — Dead link, orphan, oversized, and stale checks via SQL queries instead of bash loops.
- **watch.sh** — Polling-based staleness detection. Compares source file mtime+size hashes, flags stale meta/ nodes in SQLite.

### v1.1.0 — 2026-05-24

**Incremental MAP + Source Anchor Pre-fill.** MAP rebuilds no longer require full re-parsing of all nodes.

- **--changed incremental mode** — Re-index a single node into MEMORY_MAP.json without touching other nodes. synapse_note.sh automatically passes the modified node name.
- **source_scan.py** — AST-based Python interface extraction + regex for JS/TS/Go. Extracts function/class signatures with `@ref` source anchors. Integrated into init.sh.
- **session-end weekly full check** — Daily sessions use incremental updates; full rebuild only once per 7 days.

### v1.0.0 — 2026-05-21

Initial release of four independently installable skills.

- **synapse-graph-memory** — Core retrieval protocol with 7-step decision tree, three-layer progressive disclosure, and bounded BFS traversal. 11 scripts + 4 hooks.
- **synapse-timeline** — Read-only timeline and open issues query. Self-contained bash+Python script.
- **synapse-daily-note** — One-command NL-to-memory pipeline (ingest → suggest → apply → rebuild → validate).
- **synapse-init** — Cold-start wizard with auto stack detection and module inference.

Eval results on 8-node solo-saas fixture (deepseek-v4-pro):
- 38% fewer files read with skills vs without
- Zero irrelevant files loaded
- 100% assertion pass rate vs 62.5% baseline
