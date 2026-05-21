---
name: synapse-init
description: 在以下任一情况下激活本技能：用户说"初始化记忆"、"给项目配 Synapse"、"setup memory for this project"、"bootstrap memory graph"；用户要求为新项目或已有项目配置工程记忆系统；用户提到想自动检测技术栈并生成记忆骨架；用户说"给这个项目加上 Synapse"或类似表述。
---

# Synapse Init

## Overview

One-command cold-start wizard that bootstraps the Synapse memory system into a project:

```
init.sh
  │
  ├── Step 1: Create directory structure (meta/, meta/archive/, scripts/hooks/)
  ├── Step 2: Auto-detect tech stack (Node/React/Python/FastAPI/Go/Rust/Java)
  ├── Step 3: Infer module boundaries from src/ directory structure
  ├── Step 4: Generate mod_project.md overview node
  ├── Step 5: Generate mod_*.md skeleton nodes per detected module
  ├── Step 6: Copy helper scripts + register hooks in .claude/settings.json
  └── Step 7: Build initial MEMORY_MAP.md + MEMORY_MAP.json
```

## Trigger Patterns (MANDATORY)

| User says... | Action |
|---|---|
| "初始化记忆" / "初始化 Synapse" | Run `init.sh` in target project root |
| "给项目配 Synapse" / "给这个项目加上记忆系统" | Run `init.sh --project <path>` |
| "setup memory for this project" | Run `init.sh` |
| "bootstrap memory graph" | Run `init.sh` |
| "帮我在 <path> 项目里初始化工程记忆" | Run `init.sh --project <path>` |

## Quick Start

```bash
# Initialize current directory
bash <skill-path>/scripts/init.sh

# Initialize specific project
bash <skill-path>/scripts/init.sh --project ./my-project --yes

# Non-interactive mode
bash <skill-path>/scripts/init.sh --yes
```

## What Gets Created

| Path | Content |
|---|---|
| `meta/mod_project.md` | Project overview with detected tech stack |
| `meta/mod_<name>.md` | One skeleton per detected module (auth, api, payment, etc.) |
| `MEMORY_MAP.md` | Auto-generated graph index |
| `MEMORY_MAP.json` | Machine-readable index mirror |
| `scripts/` | Helper scripts (generate_memory_map, suggest_edges, ingest, apply, doctor) |
| `scripts/hooks/` | 4 Claude Code hooks (pre-read, pre-modify, post-tool, session-end) |
| `.claude/settings.json` | Hook registrations |

## Auto-Detection Heuristics

**Stack detection** (first match wins):
- Node.js: `package.json` → Next.js/React/Vue/Express
- Python: `pyproject.toml` / `requirements.txt` → FastAPI/Django/Flask
- Go: `go.mod`
- Rust: `Cargo.toml`
- Java: `pom.xml` / `build.gradle`

**Database detection:** `prisma/schema.prisma` → PostgreSQL, or grep for postgres/mongodb/mysql in config files.

**Module inference** (directory existence):
`src/api` → `mod_api`, `src/components` → `mod_ui-components`, `src/pages` → `mod_frontend-routing`, `src/auth` → `mod_auth`, `src/payment` → `mod_payment`, `prisma` → `mod_database`, etc.

Fallback: single `mod_project` if no patterns match.

## Post-Init Checklist

After init, tell the user to:
1. Review generated nodes — adjust module boundaries if needed
2. Fill skeletons with real endpoints, tables, configs
3. Add real `depends_on` edges or run `suggest_edges.sh`
4. Load the core skill for retrieval: `.claude/skills/synapse-graph-memory/SKILL.md`

## Dependencies

- bash 4+ (macOS: `brew install bash`)
- Python 3 (for `merge_settings()` when .claude/settings.json already exists)
- git (for project root detection)

## Supporting Files

- `references/init-parameters.md` — Module detection rules, directory-to-module mapping, customization
- `references/troubleshooting.md` — Common failures: bash version, permissions, idempotency, no directories detected
