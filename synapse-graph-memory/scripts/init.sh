#!/usr/bin/env bash
# init.sh — One-command Synapse cold-start wizard
# Auto-detects tech stack, infers module boundaries, generates initial nodes.
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "Error: requires bash 4+ (current: $BASH_VERSION)" >&2
  echo "macOS: brew install bash; ensure /opt/homebrew/bin or /usr/local/bin in PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$PROJECT_ROOT" ]; then
  # Not a git repo — infer from script location, but guard against skill-subdir execution
  if [[ "$SCRIPT_DIR" == *"/.claude/skills/"* ]]; then
    # Walk up from .claude/skills/<name>/scripts/ → project root
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  else
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  fi
fi

META_DIR="${PROJECT_ROOT}/meta"
MAP_SCRIPT="${SCRIPT_DIR}/generate_memory_map.sh"

FULLSTACK=false
PROJECT_ROOT_OVERRIDE=""

# Argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fullstack) FULLSTACK=true; shift ;;
    --project) PROJECT_ROOT_OVERRIDE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -n "$PROJECT_ROOT_OVERRIDE" ]; then
  PROJECT_ROOT="$(cd "$PROJECT_ROOT_OVERRIDE" && pwd)"
  META_DIR="${PROJECT_ROOT}/meta"
fi

echo "🧠 Synapse Cold-Start Wizard"
echo "   Project: $PROJECT_ROOT"
echo ""

# ─── Step 1: Create directory structure ────────────────────────────────
mkdir -p "${META_DIR}/archive" "${PROJECT_ROOT}/scripts/hooks" "${PROJECT_ROOT}/.claude"

SKILL_DIR="${PROJECT_ROOT}/.claude/skills/synapse-graph-memory"
SKILL_SCRIPTS="${SKILL_DIR}/scripts"

# Copy generation script if not already present
if [ ! -f "$MAP_SCRIPT" ] && [ -f "${SKILL_SCRIPTS}/generate_memory_map.sh" ]; then
  cp "${SKILL_SCRIPTS}/generate_memory_map.sh" "$MAP_SCRIPT" 2>/dev/null || true
  chmod +x "$MAP_SCRIPT" 2>/dev/null || true
fi

# Copy auxiliary scripts used by MAP generation, hooks, inbox, resume, and health checks.
for aux in generate_memory_map.py suggest_edges.sh ingest_memory.py apply_memory_proposal.py doctor.sh memory_inbox.py project_resume.py auto_observe.py db_init.py db_index.py source_scan.py query_timeline.sh watch.sh; do
  src="${SKILL_SCRIPTS}/${aux}"
  dst="${PROJECT_ROOT}/scripts/${aux}"
  if [ ! -f "$dst" ] && [ -f "$src" ]; then
    cp "$src" "$dst" 2>/dev/null || true
    chmod +x "$dst" 2>/dev/null || true
  fi
done

# Copy hook scripts
hooks_copied=0
for hook in post-tool-use.sh pre-modify-check.sh pre-read-check.sh session-end.sh; do
  src="${SKILL_SCRIPTS}/hooks/${hook}"
  dst="${PROJECT_ROOT}/scripts/hooks/${hook}"
  if [ ! -f "$dst" ] && [ -f "$src" ]; then
    cp "$src" "$dst" 2>/dev/null || true
    chmod +x "$dst" 2>/dev/null || true
    hooks_copied=$((hooks_copied + 1))
  fi
done

# Register hooks in .claude/settings.json
SETTINGS_FILE="${PROJECT_ROOT}/.claude/settings.json"
SETTINGS_TEMPLATE="${SKILL_DIR}/settings.template.json"

merge_settings() {
  local target="$1" template="$2"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -c "
import json
with open('$target') as f: s = json.load(f)
with open('$template') as f: t = json.load(f)
if 'hooks' not in s: s['hooks'] = {}
sh, th = s['hooks'], t.get('hooks', {})

def cmds_of(entry):
    if not isinstance(entry, dict): return []
    if 'command' in entry: return [entry['command']]
    return [h.get('command','') for h in entry.get('hooks', []) if isinstance(h, dict)]

for k in th:
    if k not in sh: sh[k] = []
    existing = set()
    for e in sh[k]:
        existing.update(c for c in cmds_of(e) if c)
    for e in th[k]:
        new_cmds = [c for c in cmds_of(e) if c]
        if new_cmds and any(c not in existing for c in new_cmds):
            sh[k].append(e); existing.update(new_cmds)
with open('$target','w') as f:
    json.dump(s, f, indent=2); f.write('\n')
" 2>/dev/null
}

if [ ! -f "$SETTINGS_FILE" ] && [ -f "$SETTINGS_TEMPLATE" ]; then
  cp "$SETTINGS_TEMPLATE" "$SETTINGS_FILE" 2>/dev/null || true
  echo "   ✓ Created .claude/settings.json with Synapse hooks registered"
elif [ -f "$SETTINGS_FILE" ] && [ -f "$SETTINGS_TEMPLATE" ]; then
  if grep -q 'pre-read-check\|pre-modify-check\|post-tool-use\|session-end' "$SETTINGS_FILE" 2>/dev/null; then
    echo "   ⊘ .claude/settings.json already contains Synapse hooks"
  elif merge_settings "$SETTINGS_FILE" "$SETTINGS_TEMPLATE"; then
    echo "   ✓ Merged Synapse hooks into existing .claude/settings.json"
  else
    echo "   ⚠ .claude/settings.json exists but does not register Synapse hooks."
    echo "     Install python3 for automatic merge, or merge manually:"
    echo "       ${SETTINGS_TEMPLATE} → ${SETTINGS_FILE}"
  fi
fi

# ─── Step 2: Detect tech stack ─────────────────────────────────────────
echo "📡 Detecting tech stack..."

stack=""
framework=""

if [ -f "${PROJECT_ROOT}/package.json" ]; then
  stack="Node.js"
  if grep -q '"next"' "${PROJECT_ROOT}/package.json" 2>/dev/null; then
    framework="Next.js"
  elif grep -q '"react"' "${PROJECT_ROOT}/package.json" 2>/dev/null; then
    framework="React"
  elif grep -q '"vue"' "${PROJECT_ROOT}/package.json" 2>/dev/null; then
    framework="Vue"
  elif grep -q '"express"' "${PROJECT_ROOT}/package.json" 2>/dev/null; then
    framework="Express.js"
  fi
elif [ -f "${PROJECT_ROOT}/go.mod" ]; then
  stack="Go"
  framework=$(grep '^module ' "${PROJECT_ROOT}/go.mod" 2>/dev/null | head -1 | sed 's/module //')
elif [ -f "${PROJECT_ROOT}/pyproject.toml" ] || [ -f "${PROJECT_ROOT}/requirements.txt" ]; then
  stack="Python"
  if [ -f "${PROJECT_ROOT}/pyproject.toml" ] && grep -q 'fastapi' "${PROJECT_ROOT}/pyproject.toml" 2>/dev/null; then
    framework="FastAPI"
  elif [ -f "${PROJECT_ROOT}/pyproject.toml" ] && grep -q 'django' "${PROJECT_ROOT}/pyproject.toml" 2>/dev/null; then
    framework="Django"
  elif [ -f "${PROJECT_ROOT}/requirements.txt" ] && grep -qi 'fastapi' "${PROJECT_ROOT}/requirements.txt" 2>/dev/null; then
    framework="FastAPI"
  elif [ -f "${PROJECT_ROOT}/requirements.txt" ] && grep -qi 'django' "${PROJECT_ROOT}/requirements.txt" 2>/dev/null; then
    framework="Django"
  elif [ -f "${PROJECT_ROOT}/requirements.txt" ] && grep -qi 'flask' "${PROJECT_ROOT}/requirements.txt" 2>/dev/null; then
    framework="Flask"
  fi
elif [ -f "${PROJECT_ROOT}/Cargo.toml" ]; then
  stack="Rust"
  framework=$(grep '^\[package\]' "${PROJECT_ROOT}/Cargo.toml" >/dev/null && echo "Cargo" || echo "")
elif [ -f "${PROJECT_ROOT}/pom.xml" ]; then
  stack="Java"
  framework="Maven"
elif [ -f "${PROJECT_ROOT}/build.gradle" ] || [ -f "${PROJECT_ROOT}/build.gradle.kts" ]; then
  stack="Java/Kotlin"
  framework="Gradle"
fi

# Detect database
DB=""
if [ -f "${PROJECT_ROOT}/prisma/schema.prisma" ]; then
  DB="Prisma + PostgreSQL (inferred)"
elif grep -qi 'postgres\|postgresql' "${PROJECT_ROOT}/package.json" "${PROJECT_ROOT}/pyproject.toml" "${PROJECT_ROOT}/requirements.txt" 2>/dev/null; then
  DB="PostgreSQL"
elif grep -qi 'mongodb\|mongo' "${PROJECT_ROOT}/package.json" "${PROJECT_ROOT}/pyproject.toml" "${PROJECT_ROOT}/requirements.txt" 2>/dev/null; then
  DB="MongoDB"
elif grep -qi 'mysql' "${PROJECT_ROOT}/package.json" "${PROJECT_ROOT}/pyproject.toml" "${PROJECT_ROOT}/requirements.txt" 2>/dev/null; then
  DB="MySQL"
fi

if [ -n "$framework" ]; then
  echo "   Stack: $stack ($framework)"
else
  echo "   Stack: ${stack:-unknown}"
fi
[ -n "$DB" ] && echo "   Database: $DB"
echo ""

# ─── Step 3: Infer module boundaries from directory structure ──────────
echo "🔍 Inferring module boundaries..."

declare -a MODULES=()

# Common module directories
if [ -d "${PROJECT_ROOT}/src/api" ] || [ -d "${PROJECT_ROOT}/api" ]; then
  MODULES+=("api")
fi
if [ -d "${PROJECT_ROOT}/src/components" ] || [ -d "${PROJECT_ROOT}/components" ]; then
  MODULES+=("ui-components")
fi
if [ -d "${PROJECT_ROOT}/src/pages" ] || [ -d "${PROJECT_ROOT}/pages" ] || [ -d "${PROJECT_ROOT}/app" ]; then
  MODULES+=("frontend-routing")
fi
if [ -d "${PROJECT_ROOT}/src/db" ] || [ -d "${PROJECT_ROOT}/db" ] || [ -d "${PROJECT_ROOT}/prisma" ] || [ -d "${PROJECT_ROOT}/migrations" ]; then
  MODULES+=("db-schema")
fi
if [ -d "${PROJECT_ROOT}/src/auth" ] || [ -d "${PROJECT_ROOT}/auth" ]; then
  MODULES+=("auth")
fi
if [ -d "${PROJECT_ROOT}/src/payment" ] || [ -d "${PROJECT_ROOT}/payment" ]; then
  MODULES+=("payment")
fi
if [ -d "${PROJECT_ROOT}/src/utils" ] || [ -d "${PROJECT_ROOT}/utils" ] || [ -d "${PROJECT_ROOT}/lib" ]; then
  MODULES+=("utils")
fi
if [ -d "${PROJECT_ROOT}/src/services" ] || [ -d "${PROJECT_ROOT}/services" ]; then
  MODULES+=("services")
fi
if [ -d "${PROJECT_ROOT}/src/models" ] || [ -d "${PROJECT_ROOT}/models" ]; then
  MODULES+=("models")
fi
if [ -d "${PROJECT_ROOT}/src/middleware" ] || [ -d "${PROJECT_ROOT}/middleware" ]; then
  MODULES+=("middleware")
fi

# If no standard dirs found, create a generic project node
if [ ${#MODULES[@]} -eq 0 ]; then
  MODULES+=("project")
fi

echo "   Detected modules: ${MODULES[*]}"
echo ""

# ─── Step 3.5: Auto-detect source interfaces ─────────────────────────────
echo "Step 3.5: Scanning source files for public interfaces..."
SOURCE_SCAN_SCRIPT="${SCRIPT_DIR}/source_scan.py"
FRAGMENTS_DIR="${PROJECT_ROOT}/.claude/.synapse_cache/source_fragments"

if [ -f "$SOURCE_SCAN_SCRIPT" ] && command -v python3 >/dev/null 2>&1; then
  mkdir -p "$FRAGMENTS_DIR"
  SCAN_RESULT=$(python3 "$SOURCE_SCAN_SCRIPT" --project "$PROJECT_ROOT" --output "$FRAGMENTS_DIR" --scan-depth 2 2>&1)
  echo "   $SCAN_RESULT"
  echo "   Fragments saved to: .claude/.synapse_cache/source_fragments/"
elif [ -f "$SOURCE_SCAN_SCRIPT" ] && command -v python >/dev/null 2>&1; then
  mkdir -p "$FRAGMENTS_DIR"
  SCAN_RESULT=$(python "$SOURCE_SCAN_SCRIPT" --project "$PROJECT_ROOT" --output "$FRAGMENTS_DIR" --scan-depth 2 2>&1)
  echo "   $SCAN_RESULT"
  echo "   Fragments saved to: .claude/.synapse_cache/source_fragments/"
else
  echo "   Skipping (source_scan.py not found or python3 unavailable)"
fi
echo ""

# ─── Full-Stack Mode: 4-layer scanning ──────────────────────────────────
if $FULLSTACK; then
  echo ""
  echo "─── Full-Stack Scan ───"

  # Layer 1: Database Schema
  echo ""
  echo "Layer 1/4: Database schema..."
  PRISMA_SCHEMA="${PROJECT_ROOT}/prisma/schema.prisma"
  if [ -f "$PRISMA_SCHEMA" ] && command -v python3 >/dev/null 2>&1; then
    python3 -c "
import os, re
project = '${PROJECT_ROOT}'
meta_dir = os.path.join(project, 'meta')
os.makedirs(meta_dir, exist_ok=True)
with open('${PRISMA_SCHEMA}') as f:
    content = f.read()
models = re.findall(r'model\s+(\w+)\s*\{', content)
for model_name in models:
    field_re = re.compile(rf'model\s+{model_name}\s*\{{(.*?)\}}', re.DOTALL)
    field_match = field_re.search(content)
    fields_text = field_match.group(1) if field_match else ''
    cols = re.findall(r'^\s*(\w+)\s+(\w+(?:\[\])?)\s*(@\w+(?:\([^)]*\))?)?', fields_text, re.MULTILINE)
    skeleton_cols = [c for c in cols if c[0] in ('id',) or 'Id' in c[0] or 'status' in c[0].lower() or 'type' in c[0].lower() or 'amount' in c[0].lower() or c[2] != '']
    col_table = '| 列名 | 类型 | 约束 |\n|------|------|------|\n'
    for name, typ, attr in skeleton_cols[:8]:
        attr_str = attr.replace('@', '').replace('_', ' ') if attr else '-'
        col_table += f'| {name} | {typ} | {attr_str} |\n'
    if len(cols) > len(skeleton_cols[:8]):
        col_table += f'| ... | ... | (省略 {len(cols) - len(skeleton_cols[:8])} 个辅助字段) |\n'
    node_file = os.path.join(meta_dir, f'db_{model_name.lower()}.md')
    if not os.path.exists(node_file):
        with open(node_file, 'w', encoding='utf-8') as out:
            out.write(f'''---
id: db_{model_name.lower()}
type: database_table
engine: auto-detected
depends_on: []
auto_linked: []
tags: [{model_name.lower()}]
aliases: [{model_name}]
summary: {model_name} 表 — auto-detected from Prisma schema
---

# db_{model_name.lower()}

## Columns (仅业务骨架字段)
{col_table}
## Connection Points
<!-- 待补充: suggest_edges.sh 或手动填写 -->

## Change Log
- $(date +%Y-%m-%d): Auto-detected from Prisma schema (init.sh --fullstack)
''')
        print(f'  + db_{model_name.lower()}')
" 2>&1
  else
    echo "  (no prisma/schema.prisma found or python3 unavailable)"
  fi

  # Layer 2: API Routes
  echo ""
  echo "Layer 2/4: API routes..."
  if [ -f "${SCRIPT_DIR}/source_scan.py" ] && command -v python3 >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/source_scan.py" --project "$PROJECT_ROOT" --scan-depth 3 --json 2>/dev/null | python3 -c "
import json, os, sys
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    print('  (no source files with detectable interfaces)')
    sys.exit(0)
project = '${PROJECT_ROOT}'
meta_dir = os.path.join(project, 'meta')
os.makedirs(meta_dir, exist_ok=True)
router_groups = {}
for filepath, symbols in data.items():
    dirname = os.path.dirname(filepath) or 'root'
    if dirname not in router_groups:
        router_groups[dirname] = []
    router_groups[dirname].extend(symbols)
count = 0
for dirname, symbols in list(router_groups.items())[:15]:
    endpoints = [s for s in symbols if 'def ' in s.get('signature', '') or 'function' in s.get('signature', '') or 'func ' in s.get('signature', '')]
    if len(endpoints) < 1:
        continue
    router_name = os.path.basename(dirname) or 'root'
    node_id = f'api_{router_name}-routes'
    node_file = os.path.join(meta_dir, f'{node_id}.md')
    if not os.path.exists(node_file):
        ep_table = '| 方法 | 路径 | 状态 |\n|------|------|------|\n'
        for ep in endpoints[:10]:
            ep_table += f'| ? | ? | unknown |\n'
        with open(node_file, 'w', encoding='utf-8') as out:
            out.write(f'''---
id: {node_id}
type: api_endpoint_group
framework: auto-detected
source: {dirname}
depends_on: []
auto_linked: []
tags: [api]
summary: API routes in {dirname} — auto-detected ({len(endpoints)} endpoints)
---

# {node_id}

## Endpoints
{ep_table}
## Connection Points
<!-- 待补充 -->

## Change Log
- $(date +%Y-%m-%d): Auto-detected (init.sh --fullstack)
''')
        print(f'  + {node_id}')
        count += 1
if count == 0:
    print('  (no API route files detected)')
" 2>&1
  else
    echo "  (source_scan.py not available, skipping API detection)"
  fi

  # Layer 3: UI Pages
  echo ""
  echo "Layer 3/4: UI pages (skeleton only)..."
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import os
project = '${PROJECT_ROOT}'
meta_dir = os.path.join(project, 'meta')
os.makedirs(meta_dir, exist_ok=True)
page_patterns = [
    ('src/pages', 'react'),
    ('src/views', 'vue'),
    ('app', 'nextjs'),
    ('src/routes', 'sveltekit'),
]
count = 0
for base_dir, framework in page_patterns:
    full_dir = os.path.join(project, base_dir)
    if not os.path.isdir(full_dir):
        continue
    for root, dirs, files in os.walk(full_dir):
        depth = len(os.path.relpath(root, full_dir).split(os.sep))
        rel = os.path.relpath(root, full_dir)
        if rel == '.':
            depth = 0
        if depth > 2:
            dirs.clear()
            continue
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ('node_modules', '__tests__', 'api', 'components', 'hooks', 'utils')]
        page_files = [f for f in files if f.endswith(('.tsx', '.jsx', '.vue', '.svelte')) and not f.startswith('_') and 'test' not in f.lower()]
        if page_files:
            page_name = rel.replace('/', '-').replace('.', '-') or 'index'
            node_id = f'ui_{page_name}-page'
            node_file = os.path.join(meta_dir, f'{node_id}.md')
            if not os.path.exists(node_file):
                with open(node_file, 'w', encoding='utf-8') as out:
                    out.write(f'''---
id: {node_id}
type: ui_page
framework: {framework}
source: {base_dir}/{rel}
depends_on: []
auto_linked: []
tags: [ui]
summary: {page_name} page — auto-detected, {len(page_files)} component(s)
---

# {node_id}

## States
<!-- 待补充 -->

## API 调用
<!-- 待补充: suggest_edges.sh 或手动填写 -->

## Change Log
- $(date +%Y-%m-%d): Auto-detected (init.sh --fullstack)
''')
            print(f'  + {node_id} ({framework})')
            count += 1
        # Only take one level per base_dir
        dirs.clear()
if count == 0:
    print('  (no UI page files detected)')
" 2>&1
  else
    echo "  (python3 unavailable, skipping UI detection)"
  fi

  # Layer 4: Deployment
  echo ""
  echo "Layer 4/4: Deployment config..."
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import os, re
project = '${PROJECT_ROOT}'
meta_dir = os.path.join(project, 'meta')
os.makedirs(meta_dir, exist_ok=True)

dockerfiles = [f for f in os.listdir(project) if f.startswith('Dockerfile') or f.startswith('docker-compose')]
if dockerfiles:
    node_id = 'dep_container-config'
    node_file = os.path.join(meta_dir, f'{node_id}.md')
    if not os.path.exists(node_file):
        env_vars = []
        env_example = os.path.join(project, '.env.example')
        if os.path.exists(env_example):
            with open(env_example, encoding='utf-8-sig', errors='replace') as f:
                for line in f:
                    m = re.match(r'^(\w+)=', line.strip())
                    if m:
                        comment = line.split('#')[-1].strip() if '#' in line else ''
                        env_vars.append((m.group(1), comment[:60]))
        bridges = '| 变量 | 连接 | 说明 |\n|------|------|------|\n'
        for var, desc in env_vars[:10]:
            bridges += f'| {var} | ? | {desc} |\n'
        if not env_vars:
            bridges = '<!-- 未检测到 .env.example -->\n'
        with open(node_file, 'w', encoding='utf-8') as out:
            out.write(f'''---
id: {node_id}
type: deployment
depends_on: []
auto_linked: []
tags: [docker, deploy]
summary: Container config: {\", \".join(dockerfiles)} — auto-detected
---

# {node_id}

## Files
{chr(10).join(\"- \" + f for f in dockerfiles)}

## Environment Bridges
{bridges}
## Change Log
- $(date +%Y-%m-%d): Auto-detected (init.sh --fullstack)
''')
        print(f'  + {node_id} ({len(dockerfiles)} file(s))')
else:
    print('  (no Docker files found)')
" 2>&1
  else
    echo "  (python3 unavailable, skipping deployment detection)"
  fi

  echo ""
  echo "Full-stack scan complete. Skeleton nodes generated in meta/"
  echo "Next: review skeletons, run suggest_edges.sh, use daily-note to fill details"
fi

# ─── Step 4: Generate proj_project.md ──────────────────────────────────
echo "📝 Generating nodes..."

TODAY=$(date +%Y-%m-%d)

if [ ! -f "${META_DIR}/proj_project.md" ]; then
  cat > "${META_DIR}/proj_project.md" << EOF
---
id: proj_project
type: project
status: in-progress
updated: ${TODAY}
summary: "Project overview and architecture decisions. Entry point for new sessions."
depends_on: []
tags: [project, overview]
---

# Project Overview

## Current State
Tech stack: ${framework:-${stack:-unknown}}${DB:+, $DB}.
Project initialized with Synapse on ${TODAY}.

## Key Decisions
- ${TODAY} Adopted Synapse graph memory for partitioned context loading

## Cross-Module Connection Points
None yet — add as modules are created.

## Open Issues
- [PENDING] Module boundaries inferred from directory structure. Review and adjust.

## Change Log (Observation Format)

- [${TODAY}] **Context**: Project initialization
  **Change**: Synapse memory system set up
  **Impact**: All future sessions use graph-based partitioned loading
  **Affected**: none
EOF
  echo "   ✓ ${META_DIR}/proj_project.md"
else
  echo "   ⊘ ${META_DIR}/proj_project.md already exists, skipping"
fi

# ─── Step 5: Generate module skeletons ─────────────────────────────────
for mod in "${MODULES[@]}"; do
  mod_file="${META_DIR}/mod_${mod}.md"
  if [ -f "$mod_file" ]; then
    echo "   ⊘ mod_${mod}.md already exists, skipping"
    continue
  fi

  # Infer tags from module name
  tags="[$mod"
  case "$mod" in
    api) tags="$tags, backend, endpoints" ;;
    auth) tags="$tags, security, login" ;;
    payment) tags="$tags, billing, stripe" ;;
    db-schema) tags="$tags, database, schema" ;;
    ui-components) tags="$tags, frontend, components" ;;
    frontend-routing) tags="$tags, frontend, routing" ;;
    utils|services) tags="$tags, shared, helpers" ;;
    models) tags="$tags, data, types" ;;
    middleware) tags="$tags, gateway, infrastructure" ;;
    *) tags="$tags, module" ;;
  esac
  tags="$tags]"

  cat > "$mod_file" << EOF
---
id: mod_${mod}
type: module
status: in-progress
updated: ${TODAY}
summary: "$(echo "$mod" | sed 's/-/ /g' | awk '{print toupper(substr($0,1,1)) substr($0,2)}'). Auto-generated skeleton — review and fill in."
depends_on:
  - meta/proj_project.md
tags: ${tags}
---

# $(echo "$mod" | sed 's/-/ /g' | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

## Current State
[Describe the current state of this module. Exact mode for paths, config keys, version numbers.]

## Key Decisions
- [YYYY-MM-DD] Decision — rationale

## Cross-Module Connection Points
None yet — add as connections are discovered.

## Open Issues
- [PENDING] Auto-generated skeleton. Review module boundaries and fill in details.

## Change Log (Observation Format)

- [${TODAY}] **Context**: Synapse initialization
  **Change**: Module skeleton auto-generated from directory structure
  **Impact**: Provides initial node for memory graph
  **Affected**: proj_project
EOF
  echo "   ✓ ${mod_file}"
done

echo ""

# ─── Step 6: Generate MEMORY_MAP.md ────────────────────────────────────
echo "🗺️  Building memory index..."

if [ -f "$MAP_SCRIPT" ]; then
  cd "$PROJECT_ROOT" && bash "$MAP_SCRIPT"
else
  echo "   ⚠ generate_memory_map.sh not found. Run it manually after setup."
fi

# ─── Step 7: Summary ───────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────────"
echo "✅ Synapse initialized!"
echo ""
if [ "$hooks_copied" -gt 0 ]; then
  echo "Installed $hooks_copied hook script(s) to scripts/hooks/."
fi
echo ""
echo "Next steps:"
echo "  1. Review generated nodes in ${META_DIR}/"
echo "  2. Fill in skeletons with real endpoints, tables, configs"
echo "  3. Adjust module boundaries if the inference was wrong"
echo "  4. Add real depends_on edges (or run: bash scripts/suggest_edges.sh)"
echo "  5. Load the skill: .claude/skills/synapse-graph-memory/SKILL.md"
echo ""
echo "Pre-commit hook (optional):"
echo "  echo '#!/bin/sh' > .git/hooks/pre-commit"
echo "  echo 'bash scripts/generate_memory_map.sh' >> .git/hooks/pre-commit"
echo "  chmod +x .git/hooks/pre-commit"
