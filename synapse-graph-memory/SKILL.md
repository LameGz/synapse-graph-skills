---
name: synapse-graph-memory
description: 在以下任一情况下激活本技能：用户提到了项目的记忆文件（MEMORY_MAP.md、meta/*.md）或"记忆节点"；用户询问某个功能/模块的状态、进度、还差什么、做得怎么样了（如"登录功能做得怎么样了？""还差什么"）；用户询问跨模块影响、模块之间的依赖关系，或"会影响哪些 feature"；用户使用了符合记忆节点命名规则的模块/功能名称（如 mod_xxx、feat_xxx）；用户要求加载、总结记忆节点的内容；用户用"上次做到哪了""最近关于 X 的改动有哪些""帮我加载相关记忆节点"等表述进行进度回顾或变更总结。
---

# Synapse Graph Memory

## Overview

Partitioned context loading via graph topology with progressive disclosure. Each Markdown node declares cross-module dependencies in frontmatter and a one-line `summary` for rapid triage. Three-layer retrieval:

- **Layer 1**: Read MEMORY_MAP summaries — triage without commitment (~200-500 tok)
- **Layer 2**: Read full target node(s) — load only after confirming relevance
- **Layer 3**: Bounded BFS deps (depth ≤ 2, width ≤ 5) — expand only when necessary

Three CS primitives: inverted index (MEMORY_MAP for O(1) lookup), normalization (domain-split nodes), foreign-key references (depends_on edges for deterministic traversal, not vector similarity).

For the full node specification, critical rules, and common mistakes, see `references/` — they are loaded on demand, not by default.

## Quick Reference

| Action | Rule |
|---|---|
| Vague status / progress | Read `## Status Digest` or `## Progress Summary` in MEMORY_MAP.md |
| Find nodes for topic | Read MEMORY_MAP.md, match tags → aliases → keywords |
| Load memory for task | Layer 1 MAP → Layer 2 target node → Layer 3 bounded BFS (depth≤2, width≤5) |
| Compound time+domain query | Filtered BFS: decompose query → tag + date filter + section locate |
| Check downstream impact | Read `blocks` field in MEMORY_MAP.md before modifying any module |
| Natural-language memory write | `synapse_note.sh --text "..."` (one command: ingest → suggest → apply → rebuild → doctor) |
| Review queued memory | `memory_inbox.py list --project <path>` then `memory_inbox.py apply --project <path>` |
| Resume project context | `project_resume.py --project <path>` (MAP-first project recovery) |
| Rebuild index | Auto-run by session-end hook; manual: `generate_memory_map.sh` |
| Health check | `doctor.sh` — validates frontmatter, dead links, orphans, oversized nodes |
| Initialize project | `init.sh` — auto-detect stack, generate skeleton nodes |

## Trigger Patterns (MANDATORY)

When the user's message matches ANY of these, execute the Retrieval Protocol before responding:

| User says... | Action |
|---|---|
| "XX 怎么样了/状态/完成了吗" / "how is XX going" | Find XX in Tag Index → load node → report |
| "继续做 XX" / "上次 XX 做到哪了" | Find XX → load node + deps → surface last Change Log entry |
| "XX 有什么问题" / "关于 XX..." | Find XX → load node → check Open Issues section |
| "做到什么程度了" / "还有多少没做完" / "接下来做什么" | Read Progress Summary only (~300 tok) |
| "今天/最近 XX 改了什么" | Filtered BFS: tag match + date filter on Change Log |
| "XX 链路怎么通的" / "这个按钮经过了哪些接口" / "从前端到数据库的完整路径" | Link Trace: bfs_trace() with --traverse-types ui,api,db,dep |

**Keyword extraction**: Tech terms first (FastAPI → `api`, React → `frontend`). Module names direct (登录 → `auth, login`). If no keyword extracted AND no tag matches → Status Digest mode (read only, don't guess).

Project resume triggers: when the user says "继续这个项目", "上次做到哪了", or "给我恢复一下上下文", run `project_resume.py --project <path>` before loading individual nodes.

## Query Routing

| Query type | Example | Mode | Reads |
|---|---|---|---|
| Vague status | "咱们做的咋样了" | Status Digest + Progress Summary | MEMORY_MAP.md only (~500 tok) |
| Progress / next steps | "还有什么没做" | Progress Summary | MEMORY_MAP.md Progress Summary (~300 tok) |
| Specific module | "登录做得怎么样了" | Progressive BFS | MAP → target node → deps if needed |
| Cross-module | "支付超时怎么处理" | Progressive BFS + Impact | MAP → target node → deps + in-degree check |
| Trivial change | "登录按钮改个颜色" | Progressive BFS (shallow) | MAP → target node only |
| Compound query | "今天前端改了啥" | Filtered BFS | Tag + date + section decomposition |
| Tag miss | "那个 token 刷新的事" | Keyword fallback | MAP keyword index → target node |
| Link trace | "支付链路怎么通的" | bfs_trace() state machine | MAP → start node → bfs_trace(types) → terminal paths |

### Filtered BFS — Compound Query Decomposition

| Dimension | Examples | Maps to |
|---|---|---|
| Time | "今天", "昨天", "最近" | Date filter on Change Log (YYYY-MM-DD enforced) |
| Domain | "前端", "支付", "数据库" | Tag match |
| Sub-domain | "UI", "API", "样式" | Secondary tag within domain results |
| Action | "改了", "新增", "修复" | Section: Change Log / Current State / Open Issues |

Procedure: extract dimensions → tag match + date filter → intersect results. If empty, broaden window or drop sub-domain.

## Retrieval Protocol (MANDATORY) — Decision Tree

Follow this tree exactly. Do NOT skip steps. Do NOT load files outside the paths specified.

```
START: User query matches trigger pattern?
├─ NO  → Skip retrieval. Proceed normally.
└─ YES → Continue.

STEP 1 — Query Classification
├─ Vague status ("how are we doing?")
│  └─ → Read MEMORY_MAP.md ## Status Digest + ## Progress Summary. STOP. (~500 tok)
├─ Progress/next-steps ("what's left?")
│  └─ → Read MEMORY_MAP.md ## Progress Summary ONLY. STOP. (~300 tok)
├─ Compound query (time + domain + action)
│  └─ → Decompose per Filtered BFS. Continue to STEP 2.
└─ Specific task (has domain keywords)
   └─ → Continue to STEP 2.

STEP 2 — Layer 1: MAP Triage (DO NOT load node files yet)
Open MEMORY_MAP.md.

2a. Tag Index lookup — search for tag matching query keyword.
    ├─ ≤3 matches  → Mark ALL as candidates. Go to STEP 3.
    ├─ 4-5 matches → Read summaries. Pick top 3 by recency. Go to STEP 3.
    ├─ >5 matches → STOP. Ask user to narrow scope.
    └─ 0 matches  → Go to 2b.

2b. Tag Affinity expansion (only if 2a found 0)
    ├─ Found ≥30% affinity → Retry 2a with synonym. If still 0, go to 2c.
    └─ None → Go to 2c.

2c. Alias match (only if 2a+2b both failed)
    └─ Scan Tag Index for alias string-contains query keyword. Same width bounds. Go to STEP 3 on match; else 2d.

2d. Keyword Index fallback (last resort)
    ├─ Found → Mark as candidate. Same width bounds. Go to STEP 3.
    └─ None → STOP. "No memory nodes found for 'X'."

At end of STEP 2: 1-3 candidates identified. Cost: 200-500 tok.

STEP 3 — Layer 2: Target Node Loading
For each candidate:
├─ Read FULL node file.
├─ Running token total > ~1,000? → Prioritize most recent. Defer others.
└─ Confirm relevance.

Trivial task ("fix button color") → STOP. Deps unnecessary.
Cross-module or ambiguous → Continue to STEP 4.

STEP 4 — Layer 3: Bounded BFS (depth ≤ 2, width ≤ 5)
4a. Depth 1 (MANDATORY for cross-module)
    └─ Read ALL nodes in target's `depends_on` + `auto_linked` (effective_edges).
       ├─ >5 edges? → Load first 5 by declaration order.
       └─ Token budget >15% of context? → STOP. Report to user.

4b. Depth 2 (CONDITIONAL)
    └─ For each depth-1 node, read its effective_edges.
       ├─ Load ONLY if node tags overlap with task domain.
       └─ Skip unrelated transitive deps.

4c. Stop checks (after each depth)
    ├─ depth > 2? → STOP.
    ├─ token budget > 15%? → STOP.
    └─ Task satisfied? → STOP.

Typical load: 2-4 files (simple), 6-10 files (cross-module).

STEP 5 — Modify Protocol (ONLY for write/edit tasks)
For each node you will modify:
├─ Check `blocks` field in MEMORY_MAP.md.
├─ `blocks` non-empty? → Read ## Connection Points from EACH blocking node.
│  Assess: will your change break downstream contracts?
└─ Proceed only after impact assessment.

STEP 6 — Post-Retrieval
├─ Assemble context: target nodes + BFS-loaded deps.
├─ Merge subgraphs if multiple roots.
├─ Execute task.
├─ Cross-module relationships changed? → Update depends_on (confirmed) or auto_linked (machine-suggested).
└─ Node structure changed? → Run `generate_memory_map.sh`.

STEP 7 — Session Wrap (HOOK-ENFORCED, do NOT execute manually)
`session-end.sh` runs automatically at session end:
1. Rebuild MEMORY_MAP.md / MEMORY_MAP.json
2. Validate topology (dead links, cycles, orphans, oversized nodes)
3. Emit change summary (git diff of meta/)
4. Flag drift (source files changed but meta/ not updated)

Address hook output warnings before next session.
```

## Supporting Files

- `references/node-spec.md` — Node naming, frontmatter schema, body sections, size limits, lifecycle. Read when creating or editing nodes.
- `references/critical-rules.md` — Five rules (concrete values, MAP read-only, edge maintenance, drift detection, lifecycle). Read before modifying memory.
- `references/common-mistakes.md` — Anti-patterns table. Read when debugging retrieval failures.
- `assets/template.md` — Copy when creating new mod_ or feat_ nodes.
- `scripts/` — All automation scripts. Execute via bash, do NOT load into context.

## Link Trace — Full-Stack Path Finding (V3.3)

When the user asks how a complete chain flows through the stack:

1. **Identify start node** from query (usually a ui_ or feat_ node)
2. **Run bfs_trace**: `generate_memory_map.sh --trace-from <node_id> --traverse-types ui,api,db,dep`
3. **Interpret results**:
   - Non-partial paths: render as `ui_X → api_Y → db_Z → dep_W`
   - Partial paths: include warning that chain did not reach terminal type
4. **Report** the valid paths (up to 3) to the user

### State Machine Behavior

The BFS allows:
- **Multi-hop within same type**: `ui → api_A → api_B → db` (microservice gateways)
- **Skip-level**: `ui → api → dep` (skip db, directly to deployment)
- **Terminal types**: last type in the sequence (default: `dep`)

### Backtrack Pruning

After BFS completes:
1. Filter paths whose last node matches a terminal type
2. Sort by length, take shortest `width` paths
3. If zero terminal-reaching paths: degrade to partial mode with warning

### Usage

```bash
bash scripts/generate_memory_map.sh --trace-from ui_checkout-page --traverse-types ui,api,db,dep
```

Returns JSON with `paths` array and `partial` flag.

## Autonomous Memory Writing (V3.4)

During conversation, YOU are responsible for keeping the memory graph up to date.
Do NOT wait for the user to say "/记录一下". Observe the conversation and act.

### When to auto-write

| Signal | Action | Confidence |
|--------|--------|------------|
| Source file changed (PostToolUse) | Record Change Log in matching meta/ node | High (~90%) |
| User says "决定了" / "就用" / "we'll use" | Record Key Decision | High (~85%) |
| API endpoint added/removed | Update Connection Points | High (~95%) |
| User says "还差" / "还没" / "not yet" | Add Open Issue | Medium (~70%) |
| New file created | Suggest new meta/ node | Medium (~60%) |
| Long discussion on one topic (>10 msgs) | Suggest Change Log entry | Low (~50%) |

### How to auto-write

Use the standard pipeline — don't hand-edit nodes.

```
bash scripts/synapse_note.sh --text "..." --edge-mode auto --auto-confirm
```

The `--auto-confirm` flag skips interactive prompts. The pipeline handles:
ingest -> suggest_edges -> apply -> rebuild MAP -> validate

### Auto-write marker

All auto-written entries in node files are tagged:
```
<!-- auto-recorded, confidence: N% -->
```
This lets the user audit AI-written content vs. human-written content.

### Audit trail

Session-end hook collects all auto-proposals, auto-applies high-confidence (>=70%)
entries, and displays low-confidence entries for user review:

```
🧠 Synapse Session End

📝 Auto-Recorded:
  ✓ api_payment-routes: 新增 API 端点 POST /callback (95%)
  ✓ feat_login: 响应式断点 768->640px (90%)

⚠  Needs Review:
  1. [key_decision] 决定: Redis 做支付状态缓存
     confidence: 85% | target: mod_payment
```

### When NOT to auto-write

- User explicitly says "先别记" / "don't record this"
- The change is a WIP / experiment that may be reverted
- You cannot determine the target node with confidence > 40%
- The same content was already recorded in this session (dedup)

### PostToolUse hook integration

After writing a source file, consider: should I record this? If yes:
1. Identify the target meta/ node from the file path
2. Run `auto_observe.py --changed-file <path>` to get a proposal
3. If confidence >= 70%, auto-apply immediately (don't wait for session end)
4. If confidence < 70%, note it for session-end review
