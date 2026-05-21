# Synapse — Architecture

## Design Philosophy

Synapse is an **engineering memory system** for solo full-stack developers. It treats project knowledge as a **graph of Markdown nodes** with explicit dependency edges, indexed by an inverted MAP for O(1) lookup — no vector database, no embedding, no AI hallucination risk.

Three design principles:

1. **Partitioned loading** — never load all memory at once. Three-layer progressive disclosure keeps context small.
2. **Deterministic edges** — foreign-key references (`depends_on`, `auto_linked`) instead of vector similarity. Traversal is exact.
3. **Hook-enforced consistency** — the CLI enforces protocol at runtime (PreToolUse, PostToolUse, Stop hooks), not just documentation.

## System Layers

```
┌──────────────────────────────────────────────┐
│  Layer 0: Skills (SKILL.md)                  │
│  Brain — retrieval protocol, trigger patterns │
│  Decision trees, bounded BFS, modify protocol │
├──────────────────────────────────────────────┤
│  Layer 1: Hooks + settings.json              │
│  Spinal cord — runtime enforcement           │
│  PreToolUse: gate file reads                 │
│  PostToolUse: auto-suggest edges             │
│  Stop: rebuild MAP, validate, emit diff       │
├──────────────────────────────────────────────┤
│  Layer 2: Scripts                            │
│  Muscles — deterministic automation          │
│  init.sh, synapse_note.sh, query_timeline.sh │
│  generate_memory_map.sh, doctor.sh           │
│  ingest_memory.py, apply_memory_proposal.py  │
├──────────────────────────────────────────────┤
│  Layer 3: Markdown Nodes + MAP               │
│  Memory — persistent state                   │
│  meta/mod_*.md, meta/feat_*.md               │
│  MEMORY_MAP.md (inverted index)              │
│  MEMORY_MAP.json (machine-readable mirror)   │
└──────────────────────────────────────────────┘
```

## Data Model

### Node Types

| Prefix | Purpose | Example |
|--------|---------|---------|
| `mod_` | Systems module (auth, payment, database) | `mod_auth-api` |
| `feat_` | User-facing feature (spans modules) | `feat_login` |
| `proj_` | Project overview | `proj_saas` |

### Node Anatomy

```yaml
---
depends_on: [mod_auth-api]
auto_linked: [mod_design-system]
tags: [auth, login, session]
aliases: [登录, 认证]
lifecycle: in-progress
summary: Login page UI connected to /api/v1/auth/login, session persistence done
---

# feat_login

## Summary
<one-paragraph context for Layer 1 triage>

## Connection Points
- **JWT token field**: @ref mod_auth-api#token-response
  consumes: access_token, refresh_token
- **User status guard**: @ref mod_user-account#subscription-status
  reads: subscription_status

## Current State
<current implementation status>

## Change Log
- **2026-05-11**: Connected login page to POST /api/v1/auth/login
- **2026-05-10**: UI layout complete, form validation wired

## Open Issues
- Password validation on frontend still missing
```

### Edge Types

| Edge | Semantics | Maintained by |
|------|-----------|---------------|
| `depends_on` | Confirmed dependency (this node breaks if target changes) | Human |
| `auto_linked` | Machine-suggested soft dependency | `suggest_edges.sh` |
| `effective_edges` | `depends_on ∪ auto_linked` (traversal union) | Computed |
| `blocks` | Reverse of `effective_edges` (who depends on me) | `generate_memory_map.sh` |

## Retrieval Protocol — Three-Layer Progressive Disclosure

```
Layer 1: MEMORY_MAP.md Tag Index + summaries  (~200-500 tok)
    │
    ├── Match found, simple query → STOP
    │
    ▼
Layer 2: Full target node(s)                  (~500-1500 tok per node)
    │
    ├── Trivial task (fix button color) → STOP
    │
    ▼
Layer 3: Bounded BFS (depth ≤ 2, width ≤ 5)   (~1000-4000 tok)
    │
    └── Token budget > 15% context → STOP, report to user
```

Key constraint: **never load all nodes**. At 30+ modules, brute-force reading costs exponentially while BFS stays bounded.

## Four-Skill Architecture

```
synapse-graph-memory (core, always loaded)
├── Retrieval Protocol (decision tree)
├── Node spec + critical rules + anti-patterns
└── All scripts + hooks (complete bundle)

synapse-timeline ───── synapse-daily-note ───── synapse-init
(read-only queries)    (write pipeline)          (cold-start wizard)
```

Each skill is **independently installable**. Script duplication across skills is intentional — users don't need the core skill to use any single sub-skill.

## Query Routing

| Query type | Mode | Load |
|-----------|------|------|
| Vague status ("how are we doing") | Status Digest | MAP only (~500 tok) |
| Progress ("what's left") | Progress Summary | MAP only (~300 tok) |
| Specific module ("how is login going") | Progressive BFS | MAP → target → deps |
| Cross-module impact ("what breaks if I change X") | BFS + blocks check | MAP → target → incoming edges |
| Compound (time + domain) | Filtered BFS | Tag + date decompose → intersect |
| Write ("记录一下: ...") | Pipeline | ingest → suggest → apply → rebuild → doctor |

## Script Dependency Graph

```
synapse_note.sh
├── ingest_memory.py          (NL → structured JSON)
├── suggest_edges.sh           (auto-detect cross-module edges)
├── apply_memory_proposal.py   (apply JSON to meta/*.md)
├── generate_memory_map.sh     (rebuild MEMORY_MAP.md + .json)
└── doctor.sh                  (validate topology health)

init.sh
├── generate_memory_map.sh
└── copies all scripts + hooks to target project

query_timeline.sh              (self-contained, bash + embedded Python)
```

## Hook Lifecycle

```
Session start
  │
  ├── PreToolUse: Intercept file reads → enforce protocol order
  ├── PostToolUse: After file write → suggest edge updates
  │
Session end (Stop hook)
  ├── rebuild MEMORY_MAP.md + .json
  ├── validate topology (dead links, cycles, orphans, oversized nodes)
  ├── emit change summary (git diff of meta/)
  └── flag drift (source files changed but meta/ not updated)
```

## Key Constraints

- bash 4+ required (macOS: `brew install bash`)
- Python 3.8+ (stdlib only — `json`, `re`, `sys`, `datetime`, `pathlib`)
- Zero pip/npm dependencies
- All scripts find each other via `SCRIPT_DIR` (same-directory references)
- Nodes: 30-150 lines, auto-archived at 200+ lines
- BFS: depth ≤ 2, width ≤ 5, token budget ≤ 15% context window