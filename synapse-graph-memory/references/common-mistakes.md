# Common Mistakes

| Mistake | Why Wrong | Fix |
|---|---|---|
| Reading all meta/*.md "to be safe" | Loads irrelevant context, defeats the system | Trust the graph. MAP (Layer 1) → target (Layer 2) → deps only if needed (Layer 3) |
| "the auth endpoints" instead of `/api/v1/auth/refresh` | Agent hallucinates details from fuzzy signal | Write paths/values verbatim (exact mode in fidelity categories) |
| Updating `depends_on` on one side only | Graph becomes asymmetric, reverse direction invisible | Check ALL affected nodes after cross-module work |
| Manual edit of MEMORY_MAP.md | Drift between MAP and actual files | Run `generate_memory_map.sh` instead |
| Deep directory nesting (`meta/frontend/ui/components/...`) | Defeats flat-file grep-ability | Max 2 levels: `meta/` and `meta/archive/` |
| One node per source file | Node count explodes, MAP becomes expensive | One node per functional module |
| Ignoring hook output warnings | Hooks enforce checks but agent must act on warnings | Read hook output before next task; fix flagged issues |
| Missing `summary` in frontmatter | Agent cannot triage in Layer 1; forced to load full files | Always include one-line summary |
| Flat Change Log entries ("Fixed bug") | Loses causal context | Use Observation format: Context → Change → Impact → Affected |
| Modifying a module without checking `blocks` | Downstream consumers silently break | Execute modify-protocol: check blocks in MAP, read Connection Points of dependents |
| Assuming flat 1-hop is always enough | Transitive chains (A→B→C→D) lose context at depth 3+ | Trust bounded BFS — constrains depth (≤2) and width (≤5) |
| Free-text Connection Points | "Needs auth API" useless for impact assessment | Use schema: Endpoint, Request, Response, Errors |
| Node too large (>150 lines) | Becomes its own memory collapse | Split by sub-domain |
| Node too small (<30 lines) | Graph clutter, traversal cost without information gain | Merge with closest dependency |
| Manually editing `blocks` field | `blocks` doesn't live in node files; it's computed | Run `generate_memory_map.sh` — derives blocks from depends_on |
