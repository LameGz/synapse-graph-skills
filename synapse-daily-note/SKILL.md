---
name: synapse-daily-note
description: 在以下任一情况下激活本技能：用户说"记录一下"、"记一条记忆"、"记录开发进度"、今天做了什么"并跟随具体描述；用户要求将自然语言开发记录转换为结构化记忆节点；用户提到了 MEMORY_MAP.md 或 meta 目录并希望更新项目记忆；用户用"log this change"、"capture this in memory"、"note this down"等表述要求记录变更。
---

# Synapse Daily Note

## Overview

One-command pipeline that converts natural-language notes into structured memory updates:

```
synapse_note.sh --text "your note here"
    │
    ├── Stage 1: ingest_memory.py    → NL → structured proposal JSON
    ├── Stage 2: suggest_edges.sh    → Auto-detect cross-module edges
    ├── Stage 3: apply_memory_proposal.py → Write to meta/*.md
    ├── Stage 4: generate_memory_map.sh   → Rebuild MEMORY_MAP.md + .json
    └── Stage 5: doctor.sh           → Validate topology health
```

## Trigger Patterns (MANDATORY)

| User says... | Action |
|---|---|
| "记录一下: ..." / "记一条记忆: ..." | Run `synapse_note.sh --text "..."` |
| "今天做了什么: ..." (followed by description) | Run `synapse_note.sh --text "..."` |
| "记录开发进度: ..." | Run `synapse_note.sh --text "..."` |
| "log this change: ..." / "capture this: ..." | Run `synapse_note.sh --text "..."` |
| "把这段更新到记忆里: ..." | Run `synapse_note.sh --text "..."` |

## Quick Start

```bash
# Preview (dry-run): see what would change without writing
bash <skill-path>/scripts/synapse_note.sh --project . --text "接好了 POST /api/v1/auth/login，返回 JWT。" --dry-run

# Apply with auto edge detection
bash <skill-path>/scripts/synapse_note.sh --project . --text "接好了 POST /api/v1/auth/login，返回 JWT。" --edge-mode auto --yes
```

## Options

| Flag | Effect |
|---|---|
| `--project <path>` | Project root (default: `.`) |
| `--text "..."` | **Required.** Natural-language note to ingest |
| `--dry-run` | Generate proposal only, don't apply or rebuild MAP |
| `--yes` | Skip interactive edge mode confirmation |
| `--keep-proposal` | Keep `.synapse-proposal.json` after completion |
| `--edge-mode auto` | Apply high-confidence edges to `auto_linked` (default) |
| `--edge-mode explicit` | Promote all suggested edges to `depends_on` |
| `--edge-mode none` | Apply node updates only, no edge changes |
| `--edge-mode issue` | Add edge candidates to `## Open Issues` for later review |

## Interactive Menu

Without `--yes`, after generating the proposal you'll see:

```
Choose action:
1) apply auto_linked (recommended)
2) promote to depends_on
3) apply node only
4) record edge review as Open Issues
5) cancel
```

## What Gets Modified

1. **`meta/<target>.md`** — `## Current State` appended, `## Change Log` entry added, edges updated per mode
2. **`MEMORY_MAP.md` + `MEMORY_MAP.json`** — fully rebuilt after apply
3. **`.synapse-proposal.json`** — temporary, deleted on exit unless `--keep-proposal`

## When to Use vs Manual Edit

**Use synapse_note.sh when:** capturing natural-language updates, logging progress, recording decisions, adding Change Log entries.

**Manually edit meta/*.md when:** restructuring sections, merging/splitting nodes, adding structured Connection Points, correcting frontmatter.

## Dependencies

- bash 4+ (macOS: `brew install bash`)
- Python 3 (stdlib only, no pip packages)
- All scripts must be in the same `scripts/` directory (they reference each other via `SCRIPT_DIR`)

## Supporting Files

- `references/pipeline-details.md` — Stage internals, edge scoring algorithm, proposal JSON schema. Read when debugging pipeline behavior.
