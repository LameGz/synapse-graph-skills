# Skills Overview

## Four Skills, One System

Synapse is shipped as four independently installable skills. Install one, several, or all.

| Skill | Role | Type | Scripts | Triggers |
|-------|------|------|---------|----------|
| [synapse-graph-memory](#synapse-graph-memory) | Core retrieval engine | Read + Write | 11 scripts + 4 hooks | Status queries, cross-module impact, memory loading |
| [synapse-timeline](#synapse-timeline) | Timeline & issues query | Read-only | 1 script | "最近改了啥", "有哪些 open issues" |
| [synapse-daily-note](#synapse-daily-note) | Daily memory capture | Write pipeline | 6 scripts | "记录一下: ...", "今天做了什么" |
| [synapse-init](#synapse-init) | Project bootstrap | Setup | 10 scripts + 4 hooks | "初始化记忆", "给项目配 Synapse" |

---

## synapse-graph-memory

**Core retrieval protocol.** The brain of Synapse — a 7-step decision tree for loading exactly the right amount of context from the graph memory.

### What it does

- Classifies queries (vague status → progress → specific → cross-module)
- Three-layer progressive disclosure: MAP triage → target node → bounded BFS
- Enforces token budgets (BFS stops at 15% context window)
- Modify protocol: checks `blocks` before writes to assess downstream impact
- Read-only fallback: keyword index, alias matching, tag affinity expansion

### When it triggers

- "XX 做得怎么样了？" / "登录功能的状态"
- "改 mod_user-account 会影响哪些功能？"
- "加载相关记忆节点"
- "上次做到哪了"

### Files

| File | Purpose |
|------|---------|
| `SKILL.md` (169 lines) | Retrieval protocol, decision tree, query routing table |
| `references/node-spec.md` | Node naming, frontmatter schema, lifecycle |
| `references/critical-rules.md` | Five rules: concrete values, MAP read-only, edges, drift, lifecycle |
| `references/common-mistakes.md` | 16 anti-patterns with fix columns |

### Scripts bundled (11)

`init.sh`, `synapse_note.sh`, `query_timeline.sh`, `generate_memory_map.sh`, `suggest_edges.sh`, `doctor.sh`, `benchmark.sh`, `demo_solo_saas.sh`, `parse-session.sh`, `ingest_memory.py`, `apply_memory_proposal.py`, `visualize.py`, plus 4 hooks

---

## synapse-timeline

**Read-only timeline queries.** Parses Change Log and Open Issues from memory nodes with rich filtering.

### What it does

- Timeline mode: reads `## Change Log` sections, sorted newest-first
- Issues mode: reads `## Open Issues` sections
- Filters: `--tag`, `--since`, `--recent N`, `--node`, `--limit`
- Summary mode: grouped counts by node/tag before entries

### When it triggers

- "最近改了啥" / "最近两天改了什么"
- "有哪些 open issues" / "还没解决的问题"
- "XX 模块最近的变化"
- "从 2026-05-01 之后的改动"

### Files

| File | Purpose |
|------|---------|
| `SKILL.md` (97 lines) | Trigger patterns, filter reference, output format |
| `references/query-cookbook.md` | 10 common query patterns with exact commands |
| `scripts/query_timeline.sh` | Self-contained (bash + embedded Python, 227 lines) |

---

## synapse-daily-note

**One-command write pipeline.** Converts natural-language notes into structured memory updates.

### Pipeline stages

```
synapse_note.sh --text "接好了 POST /api/v1/auth/login，返回 JWT"
    │
    ├── Stage 1: ingest_memory.py       NL → structured JSON proposal
    ├── Stage 2: suggest_edges.sh       Auto-detect cross-module edges
    ├── Stage 3: apply_memory_proposal   Write to meta/*.md
    ├── Stage 4: generate_memory_map    Rebuild MEMORY_MAP.md + .json
    └── Stage 5: doctor.sh              Validate topology health
```

### Interactive edge modes

- `auto` — apply high-confidence edges to `auto_linked`
- `explicit` — promote all suggested edges to `depends_on`
- `none` — node update only, skip edges
- `issue` — record edge candidates as Open Issues for later review

### When it triggers

- "记录一下: ..." / "记一条记忆: ..."
- "今天做了什么: ..."
- "把这段更新到记忆里: ..."

### Files

| File | Purpose |
|------|---------|
| `SKILL.md` (90 lines) | Pipeline overview, options, interactive menu |
| `references/pipeline-details.md` | Stage internals, edge scoring, JSON schema |
| `scripts/synapse_note.sh` | Entry point |
| `scripts/ingest_memory.py` | NL → JSON |
| `scripts/suggest_edges.sh` | Edge detection |
| `scripts/apply_memory_proposal.py` | Apply to files |
| `scripts/generate_memory_map.sh` | Rebuild index |
| `scripts/doctor.sh` | Validation |

---

## synapse-init

**Cold-start wizard.** Bootstraps the Synapse memory system into any project.

### What it does

1. Creates directory structure (`meta/`, `meta/archive/`, `scripts/hooks/`)
2. Auto-detects tech stack (Node/React/Python/FastAPI/Go/Rust/Java)
3. Infers module boundaries from `src/` directory structure
4. Generates `mod_project.md` overview node
5. Generates `mod_*.md` skeleton nodes per detected module
6. Copies helper scripts and registers hooks in `.claude/settings.json`
7. Builds initial `MEMORY_MAP.md` + `MEMORY_MAP.json`

### Auto-detection

| Signal | Detected stack |
|--------|---------------|
| `package.json` | Node.js → Next.js/React/Vue/Express |
| `pyproject.toml` / `requirements.txt` | Python → FastAPI/Django/Flask |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pom.xml` / `build.gradle` | Java |
| `prisma/schema.prisma` | Database → PostgreSQL |

### When it triggers

- "初始化记忆" / "初始化 Synapse"
- "给项目配 Synapse" / "给这个项目加上记忆系统"
- "setup memory for this project" / "bootstrap memory graph"

### Files

| File | Purpose |
|------|---------|
| `SKILL.md` (93 lines) | 7-step wizard, auto-detection heuristics |
| `references/init-parameters.md` | Module detection rules, directory mapping |
| `references/troubleshooting.md` | Common failures and fixes |
| `scripts/init.sh` | Entry point (~400 lines) |
| `scripts/` (9 more) | Copied to target project: generate_memory_map, suggest_edges, ingest, apply, doctor, 4 hooks |
| `assets/settings.template.json` | Hook registration template |
| `assets/template.md` | Node template |

---

## Which Skill to Install?

| You want to... | Install |
|---------------|---------|
| Ask "how is X going" and get precise answers | `synapse-graph-memory` |
| View timeline and open issues | `synapse-timeline` |
| Log daily progress with one command | `synapse-daily-note` |
| Bootstrap memory for a new project | `synapse-init` |
| All of the above | All four |