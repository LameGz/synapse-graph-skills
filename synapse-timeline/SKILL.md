---
name: synapse-timeline
description: Timeline and progress query for Synapse graph memory. Parses Change Log and Open Issues from meta/*.md nodes with rich filtering by tag, date, node, and recency. Use when asking "what changed recently", "what's still pending", "project status", "timeline for X", or any time-based or progress query about the project memory. Always activate on questions about project history, recent changes, open issues, or development progress.
---

# Synapse Timeline

v1.5 product shape: this skill remains a read-only timeline and issue query entry. For full project context restoration, prefer the core Project Resume flow (`project_resume.py --project <path>`) before loading individual nodes.

## Overview

Read-only query tool that parses `meta/*.md` node files and `MEMORY_MAP.json` to answer time-based and progress questions. Never modifies files. Never writes.

Two query modes:
- **Timeline** (default): Reads `## Change Log` sections, sorted newest-first
- **Issues** (`--issues`): Reads `## Open Issues` sections, sorted by node path

## Trigger Patterns (MANDATORY)

| User says... | Action |
|---|---|
| "最近改了啥" / "最近两天改了什么" / "这周做了什么" | `query_timeline.sh --recent N --summary` |
| "上次 XX 是什么时候" / "when did we last touch X" | `query_timeline.sh --node meta/XX.md` |
| "有哪些 open issues" / "还没解决的问题" / "还有啥没做" | `query_timeline.sh --issues` |
| "进度怎么样了" / "项目状态" / "做到什么程度了" | `query_timeline.sh --issues --summary` |
| "XX 模块最近的变化" / "timeline for auth" | `query_timeline.sh --tag XX --recent 7 --summary` |
| "从 YYYY-MM-DD 之后的改动" | `query_timeline.sh --since YYYY-MM-DD` |

If the user asks about progress but the project has `MEMORY_MAP.md`, prefer reading `## Progress Summary` from the MAP directly (cheaper). Use `query_timeline.sh` when the user wants dated, detailed entries.

## Quick Start

```bash
# From skill directory
bash scripts/query_timeline.sh --project <project-path> [filters]

# Or from anywhere
bash <path-to-skill>/scripts/query_timeline.sh --project <project-path> [filters]
```

## Filter Reference

| Flag | Argument | Effect |
|---|---|---|
| `--project` | `<path>` | Root of the Synapse project (must contain `meta/`) |
| `--node` | `meta/feat_login.md` | Show entries for one specific node only |
| `--tag` | `auth` / `支付` | Filter nodes matching tag or alias (uses `MEMORY_MAP.json` for lookup, falls back to frontmatter parsing) |
| `--since` | `YYYY-MM-DD` | Only entries on or after this date |
| `--recent` | `N` (days) | Only entries from last N days (overrides `--since`) |
| `--limit` | `N` | Max entries shown (default: 20) |
| `--summary` | (flag) | Print grouped counts before entries |
| `--issues` | (flag) | Show Open Issues instead of Change Log entries |
| `-h` / `--help` | (flag) | Print usage |

## Output Format

**Timeline mode:**
```
Timeline: <label>

2026-05-12 meta/feat_subscription.md
- Added day-two subscription memory...

2026-05-11 meta/feat_login.md
- **Context**: Natural-language memory ingestion
  **Change**: Connected login page...
  **Impact**: ...
```

**Issues mode:**
```
Open Issues: <label>

meta/mod_auth-api.md
- Token refresh endpoint needs rate limiting
meta/feat_login.md
- Password validation on frontend still missing
```

**With --summary:**
```
Summary:
- entries: 8
- nodes: 8
- tags: auth, api, login, payment, ...

<entries follow>
```

## Dependencies

- bash 4+ (macOS: `brew install bash`)
- Python 3 (stdlib only: `json`, `re`, `sys`, `datetime`, `pathlib`)
- No pip packages. No other Synapse scripts needed.

## Supporting Files

- `references/query-cookbook.md` — 10 common query patterns with exact commands and expected output. Read when the user asks "how do I query X?".
