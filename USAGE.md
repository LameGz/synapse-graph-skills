# Synapse — Usage Guide

## v1.5 Daily Flow

```bash
bash scripts/init.sh --fullstack
python scripts/project_resume.py --project .
python scripts/memory_inbox.py list --project .
python scripts/memory_inbox.py apply --project .
bash scripts/generate_memory_map.sh --db
```

- Start a returning session with Project Resume.
- Let session-end auto-observe high-confidence source changes.
- Review `.synapse/inbox.json` for low-confidence proposals before applying.
- Keep `meta/*.md` as the source of truth; treat `MEMORY_MAP.*` and SQLite as derived outputs.

## Installation

### From this repository

```bash
# Clone
git clone https://github.com/your-org/synapse-graph-skills.git

# Copy the skills you want
cp -r synapse-graph-skills/skills/synapse-graph-memory ~/.claude/skills/
cp -r synapse-graph-skills/skills/synapse-timeline ~/.claude/skills/
cp -r synapse-graph-skills/skills/synapse-daily-note ~/.claude/skills/
cp -r synapse-graph-skills/skills/synapse-init ~/.claude/skills/
```

### From .skill package

Download the `.skill` file from [Releases](https://github.com/your-org/synapse-graph-skills/releases) and drag it into `~/.claude/skills/`, or:

```bash
# Using Claude Code skill installer
claude skill install synapse-graph-memory-1.0.0.skill
claude skill install synapse-timeline-1.0.0.skill
claude skill install synapse-daily-note-1.0.0.skill
claude skill install synapse-init-1.0.0.skill
```

### Recommended: install all four

For the full experience, install all four skills. They're designed to work together but don't depend on each other.

---

## Getting Started

### Step 1: Initialize memory for your project

```
User: 初始化记忆
```

Or explicitly:

```
User: 帮我在 ~/my-saas-project 初始化 Synapse 记忆系统
```

Synapse will:
1. Detect your tech stack (Node/React, Python/FastAPI, Go, Rust, Java)
2. Create `meta/` directory with one `mod_*.md` skeleton per detected module
3. Copy helper scripts and register Claude Code hooks
4. Generate `MEMORY_MAP.md` + `MEMORY_MAP.json`

### Step 2: Review generated nodes

Open `meta/mod_project.md` and each `meta/mod_*.md`. Fill in:
- Real endpoints, database tables, config values
- Actual `depends_on` relationships between modules
- Current implementation state

### Step 3: Start logging progress

```
User: 记录一下：接好了 POST /api/v1/auth/login，返回 JWT token，
      refresh token 存 httpOnly cookie，session 持久化完成。
```

This runs the full pipeline automatically:
1. Parse natural language into structured proposal
2. Detect cross-module edges (e.g., `mod_auth-api` → `feat_login`)
3. Apply updates to `meta/*.md`
4. Rebuild `MEMORY_MAP.md` + `MEMORY_MAP.json`
5. Validate topology health

### Step 4: Query your memory

```
User: 登录功能做得怎么样了？
User: 还有什么没做完的？
User: 改 mod_user-account 的套餐字段会影响哪些功能？
User: 最近两天前端改了啥？
```

---

## Daily Workflow

### Morning: check status

```
User: 看看项目还有什么没做完的？
```

Synapse reads `MEMORY_MAP.md` Progress Summary (~300 tokens) and reports which nodes are in-progress.

### During development: log changes

```
User: 记录一下：修复了 token 刷新的竞态条件，加了 Redis 分布式锁
```

Or just ask a question that implies a change:

```
User: 改 mod_payment 的回调接口会影响哪些功能？
```

Synapse checks `blocks` field, reads downstream Connection Points, and reports impact before you touch any code.

### Evening: review timeline

```
User: 今天改了哪些东西？
```

Synapse runs `query_timeline.sh --recent 1` and shows all Change Log entries from today.

### Weekly: check open issues

```
User: 有哪些 open issues？
```

Synapse lists all `## Open Issues` entries across all nodes, grouped by module.

---

## Query Patterns

### Status queries

| Question | What Synapse does |
|----------|------------------|
| "登录做得怎么样了？" | MAP → `feat_login` → deps if needed |
| "还有什么没做？" | MAP Progress Summary only (~300 tok) |
| "项目总体状态怎么样？" | MAP Status Digest + Progress Summary (~500 tok) |

### Cross-module impact

| Question | What Synapse does |
|----------|------------------|
| "改 X 会影响哪些功能？" | MAP → check `blocks` for X → read downstream Connection Points |
| "支付超时怎么处理？" | MAP → find payment/timeout nodes → BFS deps |
| "auth 和 payment 之间有什么依赖？" | MAP → inspect `effective_edges` between both |

### Timeline & history

| Question | Script |
|----------|--------|
| "最近两天改了什么？" | `query_timeline.sh --recent 2 --summary` |
| "从 5月1号 之后的改动" | `query_timeline.sh --since 2026-05-01` |
| "auth 模块最近的变化" | `query_timeline.sh --tag auth --recent 7` |
| "有哪些 open issues" | `query_timeline.sh --issues` |

### Daily notes

| Note | Command equivalent |
|------|-------------------|
| "记录一下：接好了 XX 接口" | `synapse_note.sh --text "接好了 XX 接口"` |
| "今天做了什么：修了 A，加了 B" | `synapse_note.sh --text "修了 A，加了 B"` |
| "把这段更新到记忆里" | `synapse_note.sh --text "..."` |

---

## Script Reference

All scripts live under each skill's `scripts/` directory. Here are the key ones:

### synapse_note.sh

```bash
# Dry-run: preview without writing
bash scripts/synapse_note.sh --project . --text "接好了登录接口" --dry-run

# Apply with auto edges, skip confirmation
bash scripts/synapse_note.sh --project . --text "接好了登录接口" --edge-mode auto --yes

# Record edge candidates as Open Issues for later review
bash scripts/synapse_note.sh --project . --text "接好了登录接口" --edge-mode issue
```

### query_timeline.sh

```bash
# All changes from last 3 days
bash scripts/query_timeline.sh --project . --recent 3 --summary

# Changes to a specific node
bash scripts/query_timeline.sh --project . --node meta/mod_auth-api.md

# Filter by Chinese alias
bash scripts/query_timeline.sh --project . --tag 支付 --since 2026-05-01

# Open issues only
bash scripts/query_timeline.sh --project . --issues
```

### init.sh

```bash
# Interactive wizard
bash scripts/init.sh

# Non-interactive with defaults
bash scripts/init.sh --project ./my-project --yes

# Force re-init (skips existing check)
bash scripts/init.sh --project ./my-project --force
```

### generate_memory_map.sh

```bash
# Fast rebuild both MAP formats
bash scripts/generate_memory_map.sh --project .

# Re-parse one changed node and reuse existing MAP data for the rest
bash scripts/generate_memory_map.sh --project . --changed feat_login.md

# Rebuild MAP and sync the optional SQLite cache
bash scripts/generate_memory_map.sh --project . --full --db
```

### project_resume.py

```bash
# Restore project context before continuing work
python scripts/project_resume.py --project .

# Narrow the resume to one domain and emit JSON for tooling
python scripts/project_resume.py --project . --focus payment --json
```

### memory_inbox.py

```bash
# Review low-confidence auto-observed memory proposals
python scripts/memory_inbox.py list --project .

# Apply reviewed proposals into meta/*.md nodes
python scripts/memory_inbox.py apply --project . --limit 5

# Clear the queue after deciding not to apply pending proposals
python scripts/memory_inbox.py clear --project .
```

### doctor.sh

```bash
# Full health check
bash scripts/doctor.sh --project .

# Check specific issues
bash scripts/doctor.sh --project . --check dead-links
bash scripts/doctor.sh --project . --check orphans
bash scripts/doctor.sh --project . --check oversize
```

---

## Edge Management

Edges define how modules relate. Getting them right is the key to accurate retrieval.

### Types of edges

| Edge | Meaning | Example |
|------|---------|---------|
| `depends_on` | Hard dependency — this node breaks if target changes | `feat_login` depends on `mod_auth-api` |
| `auto_linked` | Soft dependency — machine-suggested, related | `feat_login` auto-linked to `mod_design-system` |
| `blocks` | Reverse edge — nodes that depend on this one | `mod_user-account` blocks `feat_subscription` |

### When to use depends_on vs auto_linked

- **depends_on**: You know for certain. Login page calls auth API → confirmed dependency.
- **auto_linked**: Reasonable but not certain. Login page uses design system component → soft link.

### Manual edge editing

Edit the YAML frontmatter in `meta/<node>.md`:

```yaml
---
depends_on: [mod_auth-api, mod_user-account]
auto_linked: [mod_design-system]
---
```

Then rebuild: `bash scripts/generate_memory_map.sh --project .`

### Auto edge detection

```bash
bash scripts/suggest_edges.sh --project .
```

This scans all nodes and suggests edges based on:
- Shared Connection Point references (`@ref mod_xxx#section`)
- Common tag overlap
- Cross-references in Change Log entries

---

## Troubleshooting

### "bash: scripts/xxx.sh: Permission denied"

```bash
chmod +x skills/*/scripts/*.sh
```

### "bash: scripts/xxx.sh: /usr/bin/env: bad interpreter"

You need bash 4+. On macOS:
```bash
brew install bash
# Scripts use #!/usr/bin/env bash — make sure brew bash is in PATH first
```

### "MEMORY_MAP.md not found"

Run `init.sh` first to bootstrap the memory system, or `generate_memory_map.sh` to rebuild from existing `meta/*.md` files.

### "doctor.sh reports dead links"

Open the reported node and fix the `@ref` reference. Dead links happen when:
- A referenced section was renamed or removed
- A referenced node was deleted
- The `@ref` syntax is malformed (should be `@ref mod_xxx#section-name`)

### "No memory nodes found for 'X'"

Your query didn't match any tags, aliases, or keywords. Try:
- Broader terms ("登录" → "auth" or "认证")
- Check available tags: look at the Tag Index in `MEMORY_MAP.md`
- Chinese synonyms: "会员" and "套餐" both match `mod_user-account`

---

## Best Practices

1. **Log after every meaningful change** — a 30-second note saves 10 minutes of context-rebuilding next session
2. **Keep nodes concise** — 30-150 lines per node. Archive at 200+ lines.
3. **Use concrete values** — "POST /api/v1/auth/login returns `{access_token, refresh_token}`" not "implemented auth endpoints"
4. **Update edges when relationships change** — stale edges cause the BFS to load the wrong nodes
5. **Run doctor.sh weekly** — catch dead links and orphans before they confuse retrieval
6. **Prefer vague queries** — "how are we doing?" is cheaper than loading 5 specific modules
