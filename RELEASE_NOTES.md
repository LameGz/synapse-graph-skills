# Release Notes

## Versioning

Synapse Graph Skills follows [Semantic Versioning](https://semver.org/). Each skill within the repo shares the repo version but may be released independently.

## Latest Release

### v1.0.0 — 2026-05-21

Initial release of four independently installable skills:

- **synapse-graph-memory** — Core retrieval protocol with 7-step decision tree, three-layer progressive disclosure, and bounded BFS traversal. 11 scripts + 4 hooks.
- **synapse-timeline** — Read-only timeline and open issues query. Self-contained bash+Python script.
- **synapse-daily-note** — One-command NL-to-memory pipeline (ingest → suggest → apply → rebuild → validate).
- **synapse-init** — Cold-start wizard with auto stack detection and module inference.

Eval results on 8-node solo-saas fixture (deepseek-v4-pro):
- 38% fewer files read with skills vs without
- Zero irrelevant files loaded
- 100% assertion pass rate vs 62.5% baseline

### Known Limitations

- Only 2 of 8 planned evals completed for synapse-graph-memory
- Token savings minimal at small scale (8 nodes); gap widens at 30+ modules
- Tested on single model (deepseek-v4-pro); Claude Opus/Sonnet behavior unverified
