<!-- synapse:begin -->
## Synapse Memory (managed section — do not edit between the markers)

This project uses Synapse, a file-based engineering memory (meta/*.md nodes
indexed by MEMORY_MAP.md). Integrate it into your normal workflow:

1. **Session start / context restore** — when the user asks to resume or asks
   about past work, run:
   `python "{engine}/scripts/project_resume.py" --project .`
2. **Before answering project questions**, prefetch matching memory:
   `python "{engine}/scripts/prefetch_context.py" --project . --prompt "<user ask>"`
   Read only the listed nodes' files that matter; never load all of meta/.
3. **Before finishing a turn with durable code changes**, record them:
   `python "{engine}/scripts/auto_observe.py" --project . --min-confidence 40`
   then add the low-confidence proposals to the review queue:
   `python "{engine}/scripts/memory_inbox.py" add --project . --proposal .synapse-proposal.json`
   Apply confirmed items with `memory_inbox.py apply --project .` .
4. **Status / timeline queries**: `bash "{engine}/scripts/query_timeline.sh" --project . [--tag X]`
5. **Protocol**: read MEMORY_MAP.md first; open individual meta/*.md nodes only
   after the MAP confirms relevance (bounded BFS: depth <= 2, width <= 5).
<!-- synapse:end -->
