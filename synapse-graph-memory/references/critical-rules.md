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
