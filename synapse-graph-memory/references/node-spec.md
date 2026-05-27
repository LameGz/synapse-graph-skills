# Node File Specification

## Naming

- `proj_<name>.md` - Project-level overview, architecture decisions, and resume anchor.

- `mod_<name>.md` — Persistent architecture module (routing, state, database schema). Never archived.
- `feat_<name>.md` — Lifecycle-bound feature (login, payment integration). Move to `meta/archive/` when completed.
- Flat or max 2 levels: `meta/` and `meta/archive/`.

## Extended Node Types (Full-Stack Mode)

Synapse v1.5 recognizes seven node types. The base three are `project`, `module`, and `feature`; full-stack mode adds four derived engineering layers:

| Prefix | Type | Purpose | Granularity |
|--------|------|---------|-------------|
| `proj_` | project | Project overview and session resume anchor | One node per project |
| `mod_` | module | Persistent architecture module | One node per stable module boundary |
| `feat_` | feature | Lifecycle-bound user-facing feature | One node per feature or epic |
| `db_` | database_table | Database table with business-logic columns | One node per table |
| `api_` | api_endpoint_group | Group of API endpoints (one router file) | One node per router file |
| `ui_` | ui_page | Frontend page or major tab section | One node per page; split tabs if domain overlap < 30% |
| `dep_` | deployment | Deployment unit as terminal anchor | One node per deployment unit (max 5 total) |

For the full specification, see `references/fullstack-node-spec.md`.

## Size Constraint

- **30-150 lines**: independently understandable after reading
- If >150 lines → split by sub-domain (e.g., `mod_auth.md` → `mod_auth-api.md` + `mod_auth-session.md`)
- If <30 lines → merge with closest dependency (a 10-line node is a leaf, fold into parent)
- Script warns on nodes >200 lines (grace buffer)

## Frontmatter Schema

```yaml
---
id: feat_user-login
type: feature          # "feature" or "module"
status: in-progress    # "in-progress", "stable", or "archived"
updated: 2026-04-30
summary: "One-line description for MAP triage. Read before loading full node."
depends_on:            # Explicit, human-confirmed dependencies
  - meta/mod_auth-api.md
auto_linked:           # High-confidence machine-suggested edges
  - meta/mod_design-system.md
tags: [auth, login, jwt]
aliases: [authentication, 认证, 登录, signin, token验证]
# `blocks` is auto-computed (reverse of effective_edges). Do NOT add to node files.
# **Bidirectional edge rule (FULL-STACK)**: `depends_on` is the ONLY write source for
# dependencies. Reverse edges (`blocks`) are auto-computed by the engine and MUST NOT
# be written in node files. The `post-tool-use` hook rejects any manual `blocks` field.
---
```

- `depends_on` + `auto_linked` = `effective_edges` (used for traversal)
- `blocks` = reverse of `effective_edges` (computed and rendered only in MEMORY_MAP.md)
- `aliases`: natural language synonyms (Chinese/English/abbreviations). Pure string-contains match, no embedding.

## Body Sections

```markdown
# [Node Title]

## Current State
[Specific, concrete details. Use fidelity categories:
 exact mode for paths/names/values, fuzzy mode for motivation/rationale.]

## Key Decisions
- [Date] Decision — why this over alternatives

## Cross-Module Connection Points

### To mod_<name>
- **Endpoint**: METHOD /path
- **Request**: `{ field: type, ... }`
- **Response**: `{ field: type, ... }`
- **Errors**: `CODE` Description
- **Constraints**: rate limits, idempotency, ordering

Each connection point is an interface contract, not free text.
If not API-based (shared state, file format, naming convention), adapt fields but preserve structure.

## Open Issues
- [Blocked on...]

## Change Log (YYYY-MM-DD format REQUIRED)

- [YYYY-MM-DD] **Context**: [trigger or background]
  **Change**: [what was done — concrete]
  **Impact**: [downstream consumers, contracts, behavior]
  **Affected**: [modules/features impacted]
```

Date format is mandatory. Non-conforming entries break Filtered BFS time queries and are flagged in Topology Health.

## Lifecycle (Neat-Freak Protocol)

```
active (in-progress) → stable (completed) → archived (meta/archive/)
```

- `mod_` nodes: cycle between in-progress and stable. Never archived.
- `feat_` nodes: archived when complete and unreferenced by any active node.
- After archiving: rebuild index. MAP drops archived nodes from active index.

## Cleanup Checklist

| Check | Condition | Action |
|---|---|---|
| Orphan nodes | `depends_on` and `blocks` both empty | Ask user: archive or reconnect? |
| Dead links | `depends_on` target doesn't exist | Script auto-detects in Topology Health |
| Bidirectional consistency | A→B exists but B.blocks doesn't list A | Run `generate_memory_map.sh` — auto-fixes |
| Oversized nodes | >200 lines | Suggest split into sub-nodes |
| Stale nodes | `in-progress` but `updated` > 30 days ago | Suggest downgrade to `stable` |
