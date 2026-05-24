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

# ─── SQLite priority path ────────────────────────────────────────────────
DB_PATH="${PROJECT_ROOT}/.synapse/cache/memory.db"
if [ -f "$DB_PATH" ] && command -v python3 >/dev/null 2>&1; then
  python3 -c "
import json, sqlite3, sys, os

conn = sqlite3.connect('${DB_PATH}')
issues = 0

# Check: dead depends_on links
dead_deps = conn.execute('''
    SELECT e.source, e.target FROM edges e
    LEFT JOIN nodes n ON e.target = n.id
    WHERE e.kind = \"depends_on\" AND n.id IS NULL
''').fetchall()
for source, target in dead_deps:
    print(f'DEAD DEPENDS_ON: {source} -> {target}')
    issues += 1

# Check: dead auto_linked links
dead_links = conn.execute('''
    SELECT e.source, e.target FROM edges e
    LEFT JOIN nodes n ON e.target = n.id
    WHERE e.kind = \"auto_linked\" AND n.id IS NULL
''').fetchall()
for source, target in dead_links:
    print(f'DEAD AUTO_LINKED: {source} -> {target}')
    issues += 1

# Check: orphans (no incoming or outgoing edges, feature nodes only)
orphans = conn.execute('''
    SELECT n.id FROM nodes n
    LEFT JOIN edges e_out ON n.id = e_out.source
    LEFT JOIN edges e_in ON n.id = e_in.target
    WHERE e_out.source IS NULL AND e_in.target IS NULL
      AND (n.type = \"feature\" OR n.type = \"ui_page\" OR n.type = \"api_endpoint_group\")
''').fetchall()
for (nid,) in orphans:
    print(f'ORPHAN: {nid} (no edges, consider archiving)')
    issues += 1

# Check: oversized nodes (>200 lines)
oversized = conn.execute('''
    SELECT id, line_count FROM nodes WHERE line_count > 200
''').fetchall()
for nid, lc in oversized:
    print(f'OVERSIZED: {nid} ({lc} lines, suggest splitting)')
    issues += 1

# Check: stale in-progress nodes (>30 days)
stale = conn.execute('''
    SELECT id, updated FROM nodes
    WHERE status = \"in-progress\" AND updated < date(\"now\", \"-30 days\")
''').fetchall()
for nid, upd in stale:
    print(f'STALE: {nid} (in-progress since {upd}, >30 days)')
    issues += 1

# Check: missing frontmatter fields
missing = conn.execute('''
    SELECT id FROM nodes
    WHERE summary = \"\" OR type = \"\" OR status = \"\" OR updated = \"\"
''').fetchall()
for (nid,) in missing:
    print(f'MISSING FIELDS: {nid} (summary/type/status/updated empty)')
    issues += 1

count = conn.execute('SELECT COUNT(*) FROM nodes').fetchone()[0]
conn.close()

if issues == 0:
    print(f'Synapse doctor: OK ({count} node(s) via SQLite)')
else:
    print(f'Synapse doctor: found {issues} issue(s) across {count} node(s)')
sys.exit(0 if issues == 0 else 1)
" 2>&1
  exit $?
fi

# Fall through to existing bash logic...

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
