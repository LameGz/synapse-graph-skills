#!/usr/bin/env bash
# watch.sh — Polling-based staleness detection for Synapse memory nodes.
# Scans source files for changes and marks referencing meta/ nodes as stale.
#
# Usage:
#   watch.sh --project <root> [--once] [--interval 30]

set -euo pipefail

PROJECT_ROOT=""
ONCE=false
INTERVAL=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    --once) ONCE=true; shift ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$PROJECT_ROOT" ]; then
  echo "Error: --project required" >&2
  exit 1
fi

DB_PATH="${PROJECT_ROOT}/.synapse/cache/memory.db"
STALE_MAP="${PROJECT_ROOT}/.claude/.synapse_cache/.stale_map"

pick_python() {
  local candidate
  for candidate in "${PYTHON_BIN:-}" python3 python; do
    [ -n "$candidate" ] || continue
    command -v "$candidate" >/dev/null 2>&1 || continue
    "$candidate" -c "import json, sqlite3" >/dev/null 2>&1 || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

PY_BIN="$(pick_python || true)"

python_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$path" 2>/dev/null || printf '%s\n' "$path"
  else
    printf '%s\n' "$path"
  fi
}

check_staleness() {
  if [ ! -f "$DB_PATH" ] || [ -z "$PY_BIN" ]; then
    echo "SQLite cache not found. Run generate_memory_map.sh --db first."
    return
  fi

  local project_root_py db_path_py stale_map_py
  project_root_py="$(python_path "$PROJECT_ROOT")"
  db_path_py="$(python_path "$DB_PATH")"
  stale_map_py="$(python_path "$STALE_MAP")"

  SYNAPSE_PROJECT_ROOT="$project_root_py" \
  SYNAPSE_DB_PATH="$db_path_py" \
  SYNAPSE_STALE_MAP="$stale_map_py" \
  "$PY_BIN" -c "
import json, os, sqlite3, sys

project_root = os.environ['SYNAPSE_PROJECT_ROOT']
db_path = os.environ['SYNAPSE_DB_PATH']
stale_map_file = os.environ['SYNAPSE_STALE_MAP']

conn = sqlite3.connect(db_path)

prev_hashes = {}
if os.path.exists(stale_map_file):
    try:
        with open(stale_map_file) as f:
            prev_hashes = json.load(f)
    except json.JSONDecodeError:
        pass

nodes = conn.execute('SELECT id, file_path, updated FROM nodes').fetchall()

new_hashes = {}
new_stale = []

for node_id, file_path, updated in nodes:
    if not file_path:
        continue
    full_path = os.path.join(project_root, file_path)
    if not os.path.exists(full_path):
        continue
    try:
        mtime = os.path.getmtime(full_path)
        size = os.path.getsize(full_path)
        file_hash = f'{mtime}:{size}'
    except OSError:
        continue
    new_hashes[file_path] = file_hash
    if file_path in prev_hashes and prev_hashes[file_path] != file_hash:
        new_stale.append((node_id, file_path, updated))

conn.execute('DELETE FROM staleness')
for node_id, file_path, updated in new_stale:
    conn.execute('''
        INSERT OR REPLACE INTO staleness (node_id, stale_since, reason, affected_refs)
        VALUES (?, date(\"now\"), ?, ?)
    ''', (node_id, f'source changed: {file_path}', json.dumps([file_path])))

conn.commit()
stale_count = conn.execute('SELECT COUNT(*) FROM staleness').fetchone()[0]
conn.close()

with open(stale_map_file, 'w') as f:
    json.dump(new_hashes, f)

if stale_count > 0:
    print(f'STALE: {stale_count} node(s) flagged for review')
    for node_id, file_path, _ in new_stale:
        print(f'  {node_id} — source changed: {file_path}')
else:
    print('No stale nodes. All memory nodes up-to-date.')
" 2>&1
}

if $ONCE; then
  check_staleness
  exit 0
fi

echo "Watching for source changes (interval: ${INTERVAL}s)..."
trap 'echo ""; echo "Watch stopped."; exit 0' INT TERM

while true; do
  check_staleness
  sleep "$INTERVAL"
done
