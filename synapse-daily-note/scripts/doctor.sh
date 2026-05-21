#!/usr/bin/env bash
# doctor.sh — Synapse project health checks for lightweight memory graphs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"

if [ "${1:-}" = "--project" ]; then
  PROJECT_ROOT="$2"
fi

META_DIR="${PROJECT_ROOT}/meta"
issues=0
checked=0

extract_list_items() {
  local key="$1" fm="$2"
  local inline
  inline=$(echo "$fm" | sed -n "/^${key}:[[:space:]]*\[/s/^${key}:[[:space:]]*//p" | tr -d '[]"')
  if [ -n "$(echo "$inline" | xargs)" ]; then
    echo "$inline" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d'
    return
  fi
  echo "$fm" | awk -v k="$key" '
    $0 ~ ("^" k ":[[:space:]]*$") { in_list=1; next }
    in_list && /^[[:space:]]*-[[:space:]]+/ {
      item = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      gsub(/["'"'"'\],]/, "", item)
      sub(/[[:space:]]+$/, "", item)
      if (item != "") print item
      next
    }
    in_list && /^[[:space:]]*$/ { next }
    in_list && /^[A-Za-z_]+:/ { in_list=0 }
  '
}

report_issue() {
  echo "$1"
  issues=$((issues + 1))
}

if [ ! -d "$META_DIR" ]; then
  report_issue "MISSING META: meta/ directory not found"
else
  while IFS= read -r -d '' node_file; do
    checked=$((checked + 1))
    rel="${node_file#$PROJECT_ROOT/}"
    fm=$(awk '/^---$/ {c++; next} c==1' "$node_file" 2>/dev/null || true)

    if [ -z "$fm" ]; then
      report_issue "MISSING FRONTMATTER: $rel"
      continue
    fi

    id=$(echo "$fm" | sed -n 's/^id:[[:space:]]*//p' | tr -d '"' | xargs)
    type=$(echo "$fm" | sed -n 's/^type:[[:space:]]*//p' | tr -d '"' | xargs)
    updated=$(echo "$fm" | sed -n 's/^updated:[[:space:]]*//p' | tr -d '"' | xargs)

    [ -z "$id" ] && report_issue "MISSING ID: $rel"
    [ -z "$type" ] && report_issue "MISSING TYPE: $rel"
    [ -z "$updated" ] && report_issue "MISSING UPDATED: $rel"

    for dep in $(extract_list_items "depends_on" "$fm"); do
      [ -z "$dep" ] && continue
      if [ ! -f "${PROJECT_ROOT}/${dep}" ]; then
        report_issue "DEAD DEPENDS_ON: $rel -> $dep"
      fi
    done

    for dep in $(extract_list_items "auto_linked" "$fm"); do
      [ -z "$dep" ] && continue
      if [ ! -f "${PROJECT_ROOT}/${dep}" ]; then
        report_issue "DEAD AUTO_LINKED: $rel -> $dep"
      fi
    done
  done < <(find "$META_DIR" -maxdepth 2 -name '*.md' ! -name 'MEMORY_MAP.md' -print0 2>/dev/null || true)
fi

if [ "$issues" -eq 0 ]; then
  echo "Synapse doctor: OK ($checked node(s) checked)"
  exit 0
fi

echo "Synapse doctor: found $issues issue(s) across $checked node(s)"
exit 1
