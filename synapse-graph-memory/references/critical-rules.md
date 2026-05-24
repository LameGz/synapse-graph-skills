# Critical Rules

## 1. Concrete Values: No Summarization

`Current State` must preserve specific values verbatim:

| Category | Good (exact mode) | Bad (fuzzy) |
|---|---|---|
| API paths | `POST /api/v1/auth/refresh` | "the refresh endpoint" |
| Fields + types | `User.email VARCHAR(255) UNIQUE NOT NULL` | "email field exists" |
| Config values | `TOKEN_EXPIRY=900` | "short-lived tokens" |
| Error codes | `{ code: 40101, message: "Token expired" }` | "auth error" |
| Version numbers | `"jsonwebtoken": "^9.0.2"` | "JWT library" |

**Why**: This prevents summary hallucination — information loss across the chain: code → developer understanding → node summary → agent reading → agent's mental model.

**Self-check before writing**: If I delete this data point, can the agent re-derive the correct value from description alone?
- Yes → fuzzy mode OK
- No → exact mode, preserve verbatim

## 2. MEMORY_MAP is Read-Only for Agent

`MEMORY_MAP.md` header: `<!-- AUTO-GENERATED. DO NOT EDIT MANUALLY. -->`

Agent MUST NOT edit this file. Run `generate_memory_map.sh` to rebuild.

**Why**: Agent instruction compliance degrades in long sessions. Deterministic script output is more reliable than trusting the agent to remember index updates.

## 3. Edge Maintenance

**Three edge types:**

| Edge | Owner | When to use |
|---|---|---|
| `depends_on` | Human-confirmed | Stable, verified dependencies. Promote from auto_linked only when confirmed. |
| `auto_linked` | Machine-suggested | High-confidence edges from NLP ingestion. Participate in traversal but remain distinguishable. |
| `effective_edges` | Computed | `depends_on + auto_linked`. Used for BFS traversal and `blocks` computation. |

**User should NOT hand-write `depends_on` during normal memory capture.** Prefer `synapse_note.sh` which auto-suggests edges, then promote only confirmed relationships.

**`blocks`**: Auto-computed reverse of `effective_edges`. Rendered only in MEMORY_MAP.md. If A depends_on B, then B.blocks contains A. Never add `blocks` to node frontmatter.

**After cross-module work**: Check ALL affected nodes for missing edges. If module A's Current State references module B's endpoint but no edge exists → add to `auto_linked` (machine) or `depends_on` (confirmed).

## 4. Soft Dependency Inference (Drift Detection)

Hard edges (`depends_on` + `auto_linked`) form `effective_edges`. The keyword index provides a soft fallback.

**Self-check after writing any node's Current State:**
1. Scan for references to other modules: API paths (`/api/v1/auth/*`), table names, component imports, config keys
2. For each reference, verify `effective_edges` contains that module
3. If reference exists but no edge → EITHER add to `auto_linked`, promote to `depends_on`, OR flag in Open Issues: `[PENDING VERIFY: edge to mod_X? Reference to /api/v1/X but no edge declared]`

## 5. Connection Points as Contracts

Each Connection Point must be a machine-verifiable contract:

```markdown
### To mod_payment
- **Endpoint**: POST /api/v1/payments/callback  <!-- @ref: src/payment/routes.ts:45 -->
- **Request**: `{ order_id: string, status: string, amount: number }`
- **Response**: `{ success: boolean, plan: string }`
- **Errors**: `402` Insufficient funds, `409` Duplicate order
- **Constraints**: Idempotent via `Idempotency-Key` header
```

The `<!-- @ref: path:line -->` anchor enables `session-end.sh` to verify the contract hasn't drifted from source code.

**Why**: Free-text descriptions ("needs auth API") are useless for impact assessment. Structured contracts let both the agent and scripts verify correctness.

## Full-Stack Patch Rules (V3.3)

These rules apply when full-stack nodes (db_/api_/ui_/dep_) are present.

### P1: db_ Nodes — Skeleton Fields Only

Columns table in db_ nodes MUST only list business-logic fields (those referenced
in WHERE/JOIN/IF conditions in application code). Audit fields (created_at, updated_at,
remark, etc.) MUST be omitted or replaced with `... (省略 N 个辅助字段)`.

**Why:** Full column lists rot within days of schema changes. Skeleton fields are stable.

### P2: ui_ Nodes — Tab-Level Exception

When a single page aggregates 3+ unrelated business domains AND the resulting
`depends_on` overlap between them is < 30%, split into `ui_<page>-<tab>` nodes.

**Why:** Prevents false traffic intersection in link-trace queries.

### P3: Bidirectional Edges — Single Source of Truth

`depends_on` in YAML frontmatter is the ONLY write source for graph edges.
Reverse edges in `## Connection Points` sections are READ-ONLY display text
auto-injected by the engine. The `post-tool-use` hook REJECTS manual `blocks`
or reverse-dependency YAML entries.

**Why:** Two-source bidirectional edges inevitably diverge. One source = no drift.

### P4: dep_ Nodes — Terminal Anchors, Not Deployment Docs

dep_ nodes record WHAT communicates in the deployment environment, not HOW to deploy.
Focus on Environment Bridges — which env vars connect services. CI/CD details,
k8s resource limits, and scaling policies belong elsewhere.

**Why:** dep_ nodes are link-trace endpoints, not DevOps runbooks.

## Auto-Recorded Content Audit (V3.4)

### Audit marker

Every auto-written entry MUST include:
```
<!-- auto-recorded, confidence: N% -->
```
immediately after the entry. Human-written entries have NO marker.

### Audit commands

```bash
# List all auto-recorded entries across all nodes
grep -rn "auto-recorded" meta/ | wc -l

# Find auto-recorded entries with low confidence (< 50%)
grep -rn "auto-recorded, confidence: [1-4][0-9]%" meta/

# Compare auto-recorded vs. human-written ratio
auto=$(grep -r "auto-recorded" meta/ | wc -l)
human=$(grep -r "^- " meta/*.md 2>/dev/null | grep -v "auto-recorded" | wc -l)
echo "Auto: $auto, Human: $human"
```

### Review cadence

- **Daily**: session-end hook shows what was auto-recorded. Glance at it.
- **Weekly**: `git diff meta/` since last week. Spot-check entries with confidence < 70%.
- **Monthly**: run `doctor.sh --audit-auto` (planned) to flag auto-entries that haven't been
  touched by a human in 30+ days — these may need validation.

### Rollback

Auto-recorded content is just Markdown. To revert:
```bash
git diff meta/  # Review what was auto-written
git checkout -- meta/feat_X.md  # Revert a single node
git checkout -- meta/  # Revert all auto-writes (then rebuild MAP)
bash scripts/generate_memory_map.sh --full
```
