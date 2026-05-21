# Synapse Graph Skills

**Engineering memory system for solo full-stack developers.** Partitioned context loading via graph topology — never load all memory at once.

[中文文档](README.zh-CN.md) | [Usage Guide](USAGE.md) | [Architecture](docs/architecture.md) | [Skills Overview](docs/skills-overview.md)

---

## Relationship to Synapse / Synapse-Solo

Synapse Graph Skills is the **third generation** of the Synapse memory system, completely rewritten in **Skills form**, forming a clear technical fork from its predecessors:

```
Synapse (V1)            Synapse-Solo (V2)         Synapse Graph Skills (V3) ← Current
─────────────────      ──────────────────       ──────────────────────────────
Form: Script + config    Form: Monolithic Agent     Form: 4 independent Skills
Storage: Flat Markdown   Storage: Flat Markdown     Storage: Graph-topology Markdown nodes + explicit edges
Retrieval: grep          Retrieval: Keyword+summary Retrieval: 3-layer progressive + bounded BFS
Index: None              Index: Simple summary       Index: Inverted MAP (O(1) lookup)
Edges: None              Edges: Implicit (naming)    Edges: Explicit (depends_on / auto_linked / blocks)
Consistency: Manual      Consistency: Manual         Consistency: Hook-enforced + doctor.sh topology check
Scale limit: ~10 nodes   Scale limit: ~15 nodes      Scale limit: 30+ nodes (BFS-bounded, constant context)
```

**The key fork**: V1/V2 hit context explosion beyond ~15 modules because they use a "flat files + full-text loading" model. V3's graph topology + bounded BFS **decouples** retrieval cost from module count — 30 modules costs roughly the same context as 8.

---

## The Problem

After 3 weeks of context switching between auth, payments, and notifications, your AI assistant loads irrelevant memory or misses critical cross-module dependencies. Existing solutions (vector DBs, embeddings, RAG) are overkill for a solo dev and introduce hallucination risk.

## The Solution: Graph Memory — Four Innovations

Synapse V3 treats project knowledge as **Markdown nodes with explicit dependency edges**. Here's what V3 brings over V1/V2:

### Innovation 1: Explicit Graph Topology, Not Implicit Naming Conventions

V1/V2 relied on file naming (`auth.md`, `payment.md`) to hint at relationships — the AI had to "guess" which files were relevant. V3 declares **explicit dependency edges** in each node's frontmatter:

```yaml
depends_on: [mod_auth-api, mod_user-account]   # Hard: this node breaks if target changes
auto_linked: [mod_design-system]                # Soft: machine-inferred
```

`blocks` (reverse edges) are auto-computed — "what breaks if I change X?" goes from O(n) keyword guessing to O(1) MAP lookup.

### Innovation 2: Three-Layer Progressive Disclosure — Never Load All Nodes

V1/V2's default behavior was "read all `meta/*.md` just to be safe." V3 enforces a strict three-layer protocol:

```
Layer 1: MEMORY_MAP Tag Index + summaries  (~200-500 tok)
    → Vague query? Stop here.
Layer 2: Full target node(s)               (~500-1500 tok)
    → Simple task? Stop here.
Layer 3: Bounded BFS (depth≤2, width≤5)    (~1000-4000 tok)
    → Cross-module? Load only what's needed.
    → Token budget > 15% context? Hard stop.
```

Core constraint: **never load all nodes**. At 30+ modules, bounded BFS stays constant while brute-force scales linearly.

### Innovation 3: Hook-Enforced Consistency, Not Just Documentation

V1/V2 relied on "the developer remembering to follow conventions." V3 encodes the protocol into Claude Code hooks that enforce it at runtime:

| Hook | When | Behavior |
|------|------|----------|
| PreToolUse | Before every file read | Intercept reads, enforce protocol order |
| PostToolUse | After every file write | Auto-detect cross-module edges, suggest updates |
| Stop | Session end | Rebuild MAP, validate topology, detect drift, emit change summary |

Rules are no longer a "suggestion document" — the AI literally cannot read files without following protocol.

### Innovation 4: Connection Points as Verifiable Contracts

V1/V2 described cross-module interfaces as free text ("needs auth API") — useless for impact assessment. V3's Connection Points are **structured contracts with source anchors**:

```markdown
### To mod_payment
- **Endpoint**: POST /api/v1/payments/callback  <!-- @ref: src/payment/routes.ts:45 -->
- **Request**: `{ order_id: string, status: string, amount: number }`
- **Response**: `{ success: boolean, plan: string }`
- **Errors**: `402` Insufficient funds, `409` Duplicate order
```

The `@ref` anchor enables `session-end.sh` to auto-detect when source code drifts from recorded memory.

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

Synapse auto-detects your tech stack, creates `meta/` with skeleton nodes for each module, and registers hooks.

### Log progress

```
User: 记录一下：接好了 POST /api/v1/auth/login，返回 JWT token，session 持久化完成
```

One command runs the full pipeline: ingest → suggest edges → apply → rebuild MAP → validate.

### Query status

```
User: 登录功能做得怎么样了？
```

Synapse loads exactly the right nodes — MAP first, then `feat_login`, then dependencies only if needed.

---

## Eval Results

Tested on an 8-node SaaS fixture (solo-saas) with deepseek-v4-pro:

| Metric | With Skill | Without Skill | Delta |
|--------|-----------|---------------|-------|
| Mean Files Read | **8.0** | 13.0 | **-38%** |
| Irrelevant Files | **0** | 4.5 | key win |
| Assertion Pass Rate | **100%** | 62.5% | — |

At 30+ modules, the gap widens exponentially — brute-force reading scales with module count while bounded BFS stays constant.

Full report: [EVAL_REPORT.md](EVAL_REPORT.md)

---

## Repository Structure

```
synapse-graph-skills/
├── .github/workflows/     # CI: test, lint, release
├── skills/                # Four independently installable skills
│   ├── synapse-graph-memory/
│   ├── synapse-timeline/
│   ├── synapse-daily-note/
│   └── synapse-init/
├── docs/                  # Architecture, contributing, skills overview
├── tests/                 # Test runner + fixtures
├── EVAL_REPORT.md         # Benchmark results
├── USAGE.md               # Detailed usage guide
├── README.md              # This file
└── README.zh-CN.md        # 中文文档
```

## Dependencies

- **bash 4+** (macOS: `brew install bash`)
- **Python 3.8+** (stdlib only — `json`, `re`, `sys`, `datetime`, `pathlib`)
- **Claude Code** (for skill execution; hooks require settings.json registration)

Zero pip packages. Zero npm packages. No vector database. No embeddings. POSIX-compatible scripts.

## Contributing

See [docs/contributing.md](docs/contributing.md) for skill structure conventions, eval format, and PR checklist.

## License

MIT — see [LICENSE](LICENSE) for details.

---

**Synapse Graph Skills (V3)** — graph-topology memory so your AI assistant knows what you built last week without you having to explain it again. From V1 flat files to V2 monolithic agent, to V3 graph topology + Skills architecture — every iteration answers the same question: **context should not grow with module count.**
