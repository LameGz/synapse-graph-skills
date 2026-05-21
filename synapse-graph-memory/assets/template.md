# Synapse Node Templates

Copy the relevant template below when creating a new node.

---

## Module Node (`mod_<name>.md`)

```yaml
---
id: mod_NAME
type: module
status: in-progress
updated: YYYY-MM-DD
summary: "One-line description of what this module does. Read first before loading full node."
depends_on: []
# `auto_linked`: system-discovered edges via co-occurrence + reference + semantic
# signals. Confidence >= 5.0. Auto-decays if not reinforced. Review periodically.
auto_linked: []
tags: []
aliases: []
# `aliases` are natural language synonyms the user might say: Chinese terms,
# English variants, abbreviations, colloquial forms. Indexed alongside tags
# for fallback matching. Pure string contains — no embedding model needed.
# Example: tags: [auth, jwt] → aliases: [authentication, 认证, 登录, signin]
# `blocks` is auto-computed by generate_memory_map.sh as the reverse of depends_on.
# It appears only in MEMORY_MAP.md — do NOT set it in node files.
# Optional: contract version history for temporal reasoning
# contracts:
#   - version: "2.0"
#     since: "2026-04-15"
#     changes: "JWT → PASETO, endpoint prefix /api/v2"
#   - version: "1.0"
#     since: "2025-11-01"
#     deprecated: "2026-04-15"
#     changes: "Initial release"
---

# [Module Name]

## Current State
[Architecture overview. Exact mode for paths, config keys, version numbers.]

## Key Decisions
- [YYYY-MM-DD] Decision — rationale

## Cross-Module Connection Points

### To mod_<name>
- **Endpoint**: METHOD /path
- **Request**: `{ field: type }`
- **Response**: `{ field: type }`
- **Errors**: `CODE` Description
- **Constraints**: rate limits, idempotency

### Reference Anchors (optional but recommended)

To enable automatic drift detection, add `<!-- @ref: path:line -->` comments
after values that must stay in sync with source code:

```markdown
- **Endpoint**: POST /api/v1/auth/refresh  <!-- @ref: src/auth/routes.ts:45 -->
- **Request**: `{ refresh_token: string }`  <!-- @ref: src/auth/types.ts:12 -->
```

The session-end hook validates these anchors against actual source code
and reports which specific Connection Points have drifted.

## Open Issues
- 

## Change Log (Observation Format — YYYY-MM-DD REQUIRED)

```markdown
- [YYYY-MM-DD] **Context**: [What was happening — the trigger or background]
  **Change**: [What was done — concrete, specific]
  **Impact**: [What this affects — downstream consumers, contracts, behavior]
  **Affected**: [list of modules/features impacted, if any]
```

> **Date format is mandatory.** All entries MUST begin with `[YYYY-MM-DD]`.
> Non-conforming entries break Filtered BFS time queries and compound query decomposition.
> Observation format captures *why*, not just *what*. This enables timeline reconstruction and impact assessment.

---

## Feature Node (`feat_<name>.md`)

```yaml
---
id: feat_NAME
type: feature
status: in-progress
updated: YYYY-MM-DD
summary: "One-line description of what this feature does. Read first before loading full node."
depends_on: []
auto_linked: []
tags: []
aliases: []
# `aliases` are natural language synonyms the user might say: Chinese terms,
# English variants, abbreviations, colloquial forms. Indexed alongside tags
# for fallback matching. Pure string contains — no embedding model needed.
# Example: tags: [auth, jwt] → aliases: [authentication, 认证, 登录, signin]
# `blocks` is auto-computed — do NOT set it in the node file.
# `auto_linked` stores high-confidence machine-suggested edges. MEMORY_MAP exposes
# effective_edges = depends_on + auto_linked for traversal.
---

# [Feature Name]

## Current State
[What's built, what's pending. Exact mode for endpoints, field names, config values.]

## Key Decisions
- [YYYY-MM-DD] Decision — why this over alternatives

## Cross-Module Connection Points

### To mod_<name>
- **Endpoint**: METHOD /path
- **Request**: `{ field: type }`
- **Response**: `{ field: type }`
- **Errors**: `CODE` Description
- **Constraints**: rate limits, idempotency

### Reference Anchors (optional but recommended)

To enable automatic drift detection, add `<!-- @ref: path:line -->` comments
after values that must stay in sync with source code:

```markdown
- **Endpoint**: POST /api/v1/auth/refresh  <!-- @ref: src/auth/routes.ts:45 -->
- **Request**: `{ refresh_token: string }`  <!-- @ref: src/auth/types.ts:12 -->
```

The session-end hook validates these anchors against actual source code
and reports which specific Connection Points have drifted.

## Open Issues
- 

## Change Log (Observation Format)

```markdown
- [YYYY-MM-DD] **Context**: [What was happening — user request, bug report, refactor trigger]
  **Change**: [What was built or modified — concrete, specific]
  **Impact**: [What this affects — user-facing behavior, API contracts, dependencies]
  **Affected**: [list of modules/features impacted, if any]
```

> Observation format captures *why*, not just *what*. This enables timeline reconstruction and impact assessment.

---

## Archive Entry (`meta/archive/<name>.md`)

```yaml
---
id: archived_NAME
type: feature
status: archived
updated: YYYY-MM-DD
summary: "Why this was archived and what it did. For historical reference only."
depends_on: []
auto_linked: []
tags: []
aliases: []
# `blocks` is auto-computed — do NOT set it in the node file.
# `auto_linked` stores high-confidence machine-suggested edges. MEMORY_MAP exposes
# effective_edges = depends_on + auto_linked for traversal.
---

# [Archived Feature Name]

## Why archived
[Reason: completed / superseded / abandoned]

## Key deliverables
[What was built / decided]

## Restore notes
[What would need to change to reactivate this node]

## Change Log (Observation Format — YYYY-MM-DD REQUIRED)

```markdown
- [YYYY-MM-DD] **Context**: [Why archived — completed, superseded, or abandoned]
  **Change**: [Final state — what was delivered or decided before archiving]
  **Impact**: [What remains in the system — code, decisions, or docs that persist]
  **Affected**: [none, or list if archive affects active modules]
```

> **Date format is mandatory.** All entries MUST begin with `[YYYY-MM-DD]`.
