# Pipeline Details

## Stage 1: ingest_memory.py

Converts natural-language text into a structured proposal JSON.

**Input**: `--project <path>` + `--text "natural language note"`
**Output**: JSON proposal on stdout

**How it works:**
1. Scans all `meta/*.md` nodes, extracts frontmatter (id, tags, aliases, summary)
2. Parses the `--text` for entities: API endpoints (`POST /path`), field names, component names, topics
3. Scores each existing node against the extracted entities using topic priority
4. Selects the best-matching target node (or `"create_node"` if no match)
5. Generates `node_update` (current_state bullets, change_log entry) and `edge_candidates`

**Proposal JSON schema:**
```json
{
  "version": "0.5",
  "action": "update_node",
  "target_node": "meta/feat_subscription.md",
  "raw_text": "...",
  "extracted": {
    "endpoints": ["POST /api/v1/payments/callback"],
    "topics": ["subscription", "payment"]
  },
  "suggested_frontmatter": {},
  "node_update": {
    "current_state": ["- bullet point"],
    "change_log": [{"date": "YYYY-MM-DD", "summary": "...", "details": "..."}]
  },
  "edge_candidates": [
    {"target": "meta/mod_payment.md", "confidence": 9.0, "evidence": "...", "apply_to": "auto_linked"},
    {"target": "meta/mod_user-account.md", "confidence": 8.0, "evidence": "...", "apply_to": "auto_linked"}
  ]
}
```

## Stage 2: suggest_edges.sh

Reads the proposal JSON and prints human-readable edge suggestions.

**Modes:**
- `--proposal proposal.json` — reads edge_candidates from the proposal
- `--auto` — scans all nodes for co-occurrence signals (independent of proposal)

**Confidence thresholds:**
- ≥ 8.0/10: `apply_to = "auto_linked"` (auto-applied in `auto` mode)
- 5.0-7.9: `apply_to = "review"` (shown but requires manual promotion)
- < 5.0: not suggested

## Stage 3: apply_memory_proposal.py

Writes the proposal changes to `meta/*.md`.

**Edge modes:**
| Mode | Edges go to | Behavior |
|---|---|---|
| `auto` | `auto_linked` | Only edges with `apply_to == "auto_linked"` (confidence ≥ 8) |
| `explicit` | `depends_on` | ALL edge candidates promoted to explicit deps |
| `none` | (none) | Node update only, edges ignored |
| `issue` | `## Open Issues` | Each edge candidate becomes `[PENDING VERIFY]` item |

**Always applied regardless of mode:** current_state bullets, change_log entry.

## Stage 4: generate_memory_map.sh

Rebuilds `MEMORY_MAP.md` + `MEMORY_MAP.json` from all `meta/*.md` nodes.

- Parses frontmatter from every node
- Builds tag index, keyword index, tag affinity, change log index
- Computes `effective_edges = depends_on + auto_linked`
- Computes `blocks = reverse(effective_edges)`
- Generates Progress Summary (stable/in-progress ratio, open issues count, priorities)
- Validates topology (dead links, cycles, orphans, oversized nodes)

## Stage 5: doctor.sh

Validates graph health. Checks: missing frontmatter fields, dead links in depends_on/auto_linked, orphan nodes, oversized nodes, stale in-progress nodes. Output ends with "Synapse doctor passed" on success.
