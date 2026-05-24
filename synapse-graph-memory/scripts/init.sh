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

# Copy auxiliary scripts (suggest_edges, etc.)
for aux in suggest_edges.sh ingest_memory.py apply_memory_proposal.py doctor.sh; do
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

# ─── Step 4: Generate mod_project.md ───────────────────────────────────
echo "📝 Generating nodes..."

TODAY=$(date +%Y-%m-%d)

if [ ! -f "${META_DIR}/mod_project.md" ]; then
  cat > "${META_DIR}/mod_project.md" << EOF
---
id: mod_project
type: module
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
  echo "   ✓ ${META_DIR}/mod_project.md"
else
  echo "   ⊘ ${META_DIR}/mod_project.md already exists, skipping"
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
  - meta/mod_project.md
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
  **Affected**: mod_project
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
