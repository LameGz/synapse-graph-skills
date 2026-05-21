#!/usr/bin/env bash
# PreToolUse hook: impact surface check before modifying source files.
#
# When Agent is about to Write/Edit a source file (non-meta/), this hook
# scans memory nodes to find which ones reference this file in their
# Connection Points. It then injects an impact warning into the context
# BEFORE the modification happens.
#
# Registration in .claude/settings.json:
#   "PreToolUse": [{ "matcher": "Write|Edit", "command": "bash scripts/hooks/pre-modify-check.sh" }]
#
# This is NOT a block — it's information push. The Agent still decides,
# but now it decides with full awareness of downstream consumers.
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "Error: requires bash 4+ (current: $BASH_VERSION)" >&2
  echo "macOS: brew install bash; ensure /opt/homebrew/bin or /usr/local/bin in PATH" >&2
  exit 1
fi

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$PWD}"
META_DIR="${PROJECT_ROOT}/meta"
MAP_JSON="${PROJECT_ROOT}/MEMORY_MAP.json"

# ─── Lookup blocks for a node from MEMORY_MAP.json ────────────────────
# `blocks` is auto-computed (reverse of depends_on) and lives ONLY in
# MEMORY_MAP.json — never in node frontmatter. Per SKILL.md spec.
lookup_blocks() {
  local target_rel="$1"
  [ ! -f "$MAP_JSON" ] && return 0
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys
try:
    with open('$MAP_JSON') as f: m = json.load(f)
    for n in m.get('nodes', []):
        if n.get('rel') == '$target_rel':
            print(' '.join(n.get('blocks', [])))
            break
except Exception:
    pass
" 2>/dev/null
  fi
  # If python3 unavailable, return empty — hook still shows node ids,
  # just without downstream consumer list. Better than wrong data.
}

# ─── Parse tool call from stdin (JSON) ────────────────────────────────
# Expected stdin format: JSON with tool_name and file_path fields
read -r input_line <&0 || true
[ -z "${input_line:-}" ] && exit 0

tool_name=$(echo "$input_line" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true)
file_path=$(echo "$input_line" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true)

[ -z "$tool_name" ] && exit 0
[ -z "$file_path" ] && exit 0

# Only act on Write/Edit to source files (not meta/, not MEMORY_MAP.md)
case "$tool_name" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

# Skip meta/ files — those are managed by post-tool-use.sh
if echo "$file_path" | grep -qE '^meta/'; then
  exit 0
fi

# Skip if no meta/ directory
[ ! -d "$META_DIR" ] && exit 0

# ─── Find memory nodes that reference this source file ────────────────
# Strategy: scan node bodies for references to the file path.
# We check both exact matches and basename matches.

file_basename=$(basename "$file_path")
file_dir=$(dirname "$file_path")

# Also check for common variants (e.g., src/auth/token.ts → token.ts, auth/token)
search_patterns=(
  "$file_path"
  "$file_basename"
)

# If file is in a subdirectory, also search for the dir/file pattern
if [ "$file_dir" != "." ]; then
  # e.g., src/auth/token.ts → also search for "auth/token"
  short_path=$(echo "$file_path" | sed 's|^[^/]*/||')
  search_patterns+=("$short_path")
fi

declare -a IMPACT_NODES=()

while IFS= read -r -d '' node_file; do
  [ ! -f "$node_file" ] && continue
  rel="${node_file#$PROJECT_ROOT/}"

  # Skip MEMORY_MAP.md and archive
  [[ "$rel" == *"MEMORY_MAP.md"* ]] && continue
  [[ "$rel" == *"archive"* ]] && continue

  # Extract body (after frontmatter)
  body=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$node_file" 2>/dev/null || true)
  [ -z "$body" ] && continue

  # Check if body references any of our search patterns
  found=0
  for pattern in "${search_patterns[@]}"; do
    if echo "$body" | grep -qF "$pattern"; then
      found=1
      break
    fi
  done

  if [ "$found" -eq 1 ]; then
    # Extract node id from frontmatter; blocks comes from MEMORY_MAP.json
    # (NOT from node frontmatter — `blocks` is auto-computed per SKILL.md).
    fm=$(awk '/^---$/ {c++; next} c==1' "$node_file" 2>/dev/null || true)
    node_id=$(echo "$fm" | sed -n 's/^id:[[:space:]]*//p' | tr -d '"' | xargs)
    blocks=$(lookup_blocks "$rel")

    IMPACT_NODES+=("${node_id:-unknown}|${rel}|${blocks:-}")
  fi
done < <(find "$META_DIR" -maxdepth 2 -name '*.md' ! -name 'MEMORY_MAP.md' -print0 2>/dev/null || true)

# ─── Output impact warning ────────────────────────────────────────────
if [ ${#IMPACT_NODES[@]} -eq 0 ]; then
  # No memory nodes reference this file — nothing to report
  exit 0
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ⚠️  SYNAPSE IMPACT CHECK"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📁  You are about to modify: $file_path"
echo ""
echo "🔗  The following memory nodes reference this file in their"
echo "    Cross-Module Connection Points:"
echo ""

for entry in "${IMPACT_NODES[@]}"; do
  IFS='|' read -r node_id rel blocks <<< "$entry"
  echo "    • $node_id ($rel)"
  if [ -n "$blocks" ]; then
    echo "      blocks (downstream consumers): $blocks"
  else
    echo "      blocks: none"
  fi
  echo ""
done

echo "📋  RECOMMENDATION before proceeding:"
echo "    1. Check each blocking node's Connection Points section"
echo "    2. Verify your change does not break downstream contracts"
echo "    3. If contracts change, update affected nodes and rebuild MAP"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

exit 0
