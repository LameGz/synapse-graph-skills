#!/usr/bin/env bash
# PostToolUse hook: validates Synapse memory nodes after Agent modifies them.
# Fires after every Write/Edit tool call targeting meta/*.md files.
# Reads tool call info from stdin (JSON) or args.
set -euo pipefail

# ─── Parse input ──────────────────────────────────────────────────────
# Claude Code passes tool call data as JSON on stdin
tool_name=""
file_path=""

if [ -p /dev/stdin ] || [ ! -t 0 ]; then
  stdin_data=$(cat)
  tool_name=$(echo "$stdin_data" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  file_path=$(echo "$stdin_data" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

# Also try positional args as fallback
[ -z "$tool_name" ] && tool_name="${1:-}"
[ -z "$file_path" ] && file_path="${2:-}"

# Only care about Write/Edit on meta/*.md files
case "$tool_name" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

case "$file_path" in
  meta/*.md) ;;
  *) exit 0 ;;
esac

# Don't validate MEMORY_MAP (auto-generated) or archive entries
case "$file_path" in
  */MEMORY_MAP.md) exit 0 ;;
  */archive/*) exit 0 ;;
esac

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$PWD}"
file_abs="${PROJECT_ROOT}/${file_path}"

if [ ! -f "$file_abs" ]; then
  echo "---"
  echo "🔍 Synapse: \`$file_path\` was created. Ensure frontmatter is complete."
  echo "   Required: id, type, status, updated, depends_on, tags"
  echo "   Note: \`blocks\` is auto-computed by generate_memory_map.sh — do NOT set it in the node file."
  exit 0
fi

# ─── Validate frontmatter ─────────────────────────────────────────────
warnings=""

# Extract frontmatter
fm=$(awk '/^---$/ {c++; next} c==1' "$file_abs" 2>/dev/null || true)
if [ -z "$fm" ]; then
  echo "---"
  echo "⚠ Synapse: \`$file_path\` has no YAML frontmatter (missing --- delimiters)."
  echo "   Run \`scripts/generate_memory_map.sh\` after fixing."
  exit 0
fi

# Check required fields (blocks is auto-computed; not required in source frontmatter)
for field in id type status updated depends_on tags; do
  if ! echo "$fm" | grep -q "^${field}:"; then
    warnings="${warnings}  - Missing field: \`$field\`
"
  fi
done

# Warn (not error) if author embedded a non-empty blocks field — it will be ignored.
if echo "$fm" | grep -qE '^blocks:[[:space:]]*\[[^]]*[a-zA-Z]'; then
  warnings="${warnings}  - \`blocks\` is auto-computed; values you set here will be ignored. Use \`[]\` or omit the field.
"
fi

# Check depends_on targets exist (handles BOTH inline `[a, b]` and multi-line `- a` forms)
deps=$(echo "$fm" | awk '
  BEGIN { in_list = 0 }
  /^depends_on:[[:space:]]*\[/ {
    line = $0
    sub(/^depends_on:[[:space:]]*\[/, "", line)
    sub(/\].*$/, "", line)
    n = split(line, parts, ",")
    for (i = 1; i <= n; i++) {
      v = parts[i]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      gsub(/^["\047]|["\047]$/, "", v)
      if (v != "") print v
    }
    next
  }
  /^depends_on:[[:space:]]*$/ { in_list = 1; next }
  in_list && /^[[:space:]]*-[[:space:]]+/ {
    v = $0
    sub(/^[[:space:]]*-[[:space:]]*/, "", v)
    gsub(/^["\047]|["\047]$/, "", v)
    sub(/[[:space:]]+$/, "", v)
    if (v != "") print v
    next
  }
  in_list && /^[[:space:]]*$/ { next }
  in_list && /^[a-zA-Z]/ { in_list = 0 }
')
if [ -n "$deps" ]; then
  while IFS= read -r dep; do
    dep=$(echo "$dep" | xargs)
    [ -z "$dep" ] && continue
    if [ ! -f "${PROJECT_ROOT}/${dep}" ]; then
      warnings="${warnings}  - Dead link: depends_on \`$dep\` — file not found
"
    fi
  done <<< "$deps"
fi

# Check updated field is today
updated=$(echo "$fm" | sed -n 's/^updated:[[:space:]]*//p' | tr -d '"' | xargs)
today=$(date +%Y-%m-%d)
if [ -n "$updated" ] && [ "$updated" != "$today" ]; then
  warnings="${warnings}  - \`updated\` field is $updated (today is $today)
"
fi

# ─── Output ────────────────────────────────────────────────────────────
if [ -n "$warnings" ]; then
  echo "---"
  echo "🔍 Synapse Post-Edit Check — \`$file_path\`:"
  echo "$warnings"
  echo "  Fix these before ending the session."
fi

exit 0
