#!/usr/bin/env bash
set -euo pipefail

PROJECT="."
NODE=""
TAG=""
SINCE=""
RECENT=""
LIMIT="20"
SUMMARY=0
ISSUES=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/query_timeline.sh --project <path> [filter]

Filters:
  --node meta/feat_login.md   Show entries for one node
  --tag auth                  Show entries from nodes with the tag or alias
  --since YYYY-MM-DD          Keep entries on or after date
  --recent N                  Keep entries from the last N days
  --limit N                   Limit entries shown (default: 20)
  --summary                   Print grouped counts before entries
  --issues                    Show Open Issues instead of Change Log entries
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --node)
      NODE="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --since)
      SINCE="$2"
      shift 2
      ;;
    --recent)
      RECENT="$2"
      shift 2
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --summary)
      SUMMARY=1
      shift
      ;;
    --issues)
      ISSUES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# ─── SQLite priority path (if DB exists) ───────────────────────────────
DB_PATH="${PROJECT}/.synapse/cache/memory.db"
USE_SQLITE=false
if [ -f "$DB_PATH" ] && command -v python3 >/dev/null 2>&1; then
  USE_SQLITE=true
fi

if [ "$USE_SQLITE" = true ] && [ "$ISSUES" -eq 0 ]; then
  python3 -c "
import json, sqlite3, sys

conn = sqlite3.connect('${DB_PATH}')

where_clauses = []
params = []

if '${NODE}':
    node_id = '${NODE}'.replace('meta/', '').replace('.md', '')
    where_clauses.append('n.id = ?')
    params.append(node_id)

if '${TAG}':
    where_clauses.append('(n.tags LIKE ? OR n.aliases LIKE ?)')
    params.extend([f'%{('${TAG}')}%', f'%{('${TAG}')}%'])

if '${SINCE}':
    where_clauses.append('n.updated >= ?')
    params.append('${SINCE}')

where_sql = ' AND '.join(where_clauses) if where_clauses else '1=1'
limit = int('${LIMIT}') if '${LIMIT}'.isdigit() else 20

query = f'''
    SELECT n.id, n.type, n.status, n.summary, n.tags, n.aliases, n.updated, n.file_path
    FROM nodes n
    WHERE {where_sql}
    ORDER BY n.updated DESC
    LIMIT {limit}
'''

try:
    results = conn.execute(query, params).fetchall()
except Exception as e:
    print(f'SQLite error: {e}', file=sys.stderr)
    sys.exit(1)

if not results:
    print('No matching nodes found.')
    sys.exit(0)

if '${SUMMARY}' == '1':
    print(f'Nodes: {len(results)}')
    tags_all = set()
    for r in results:
        for t in json.loads(r[4] or '[]'):
            tags_all.add(t)
    print(f'Tags: {\", \".join(sorted(tags_all))}')
    print()

for r in results:
    tags_str = ', '.join(json.loads(r[4] or '[]')[:3])
    print(f'[{r[0]}] {r[3][:100]}')
    print(f'  Status: {r[2]} | Updated: {r[6]} | Tags: {tags_str}')

conn.close()
" 2>&1
  exit $?
fi

# Fall through to existing bash query logic...

PROJECT_ABS="$(cd "$PROJECT" && pwd)"

python - "$PROJECT_ABS" "$NODE" "$TAG" "$SINCE" "$RECENT" "$LIMIT" "$SUMMARY" "$ISSUES" <<'PY'
import json
import re
import sys
from datetime import date, timedelta
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

project = Path(sys.argv[1])
node_filter = sys.argv[2]
tag_filter = sys.argv[3]
since = sys.argv[4]
recent = sys.argv[5]
limit = int(sys.argv[6])
show_summary = sys.argv[7] == "1"
show_issues = sys.argv[8] == "1"

if recent:
    since = (date.today() - timedelta(days=int(recent))).isoformat()

map_json = project / "MEMORY_MAP.json"
node_meta = {}
if map_json.exists():
    data = json.loads(map_json.read_text(encoding="utf-8"))
    for node in data.get("nodes", []):
        path = node.get("path", "")
        terms = set(node.get("tags", [])) | set(node.get("aliases", [])) | {node.get("id", "")}
        node_meta[path] = terms

def frontmatter_terms(path):
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return set()
    parts = text.split("---", 2)
    if len(parts) < 3:
        return set()
    terms = set()
    current = None
    for line in parts[1].splitlines():
        if ":" in line and not line.startswith(" "):
            key, raw = line.split(":", 1)
            current = key.strip()
            value = raw.strip()
            if current in {"id", "tags", "aliases"}:
                if value.startswith("[") and value.endswith("]"):
                    terms.update(item.strip().strip('"\'') for item in value[1:-1].split(",") if item.strip())
                elif value:
                    terms.add(value.strip('"'))
        elif current in {"tags", "aliases"} and line.strip().startswith("-"):
            terms.add(line.strip()[1:].strip().strip('"'))
    return terms

def section_lines(path, heading):
    lines = path.read_text(encoding="utf-8").splitlines()
    in_section = False
    collected = []
    for line in lines:
        if line.startswith("## "):
            if in_section:
                break
            in_section = line.strip() == heading
            continue
        if in_section:
            collected.append(line)
    return collected

def changelog_entries(path):
    rel = path.relative_to(project).as_posix()
    entries = []
    current = None
    for line in section_lines(path, "## Change Log"):
        m = re.match(r"^- \[?(\d{4}-\d{2}-\d{2})\]?\s*(.*)", line.strip())
        if m:
            if current:
                entries.append(current)
            current = {"date": m.group(1), "path": rel, "text": m.group(2).strip(), "details": [], "kind": "change"}
        elif current and line.startswith("  "):
            current["details"].append(line.strip())
    if current:
        entries.append(current)
    return entries

def issue_entries(path):
    rel = path.relative_to(project).as_posix()
    entries = []
    for line in section_lines(path, "## Open Issues"):
        stripped = line.strip()
        if not stripped or stripped == "None.":
            continue
        if stripped.startswith("-"):
            entries.append({"date": "open", "path": rel, "text": stripped[1:].strip(), "details": [], "kind": "issue"})
    return entries

paths = sorted((project / "meta").glob("*.md")) if (project / "meta").exists() else []
if node_filter:
    paths = [project / node_filter]

entries = []
entry_terms = {}
for path in paths:
    if not path.exists():
        continue
    rel = path.relative_to(project).as_posix()
    terms = node_meta.get(rel) or frontmatter_terms(path)
    if tag_filter and tag_filter not in terms:
        continue
    source_entries = issue_entries(path) if show_issues else changelog_entries(path)
    for entry in source_entries:
        if since and entry["date"] != "open" and entry["date"] < since:
            continue
        entries.append(entry)
        entry_terms[entry["path"]] = terms

if show_issues:
    entries.sort(key=lambda item: item["path"])
else:
    entries.sort(key=lambda item: (item["date"], item["path"]), reverse=True)

label = node_filter or tag_filter or "project"
mode = "Open Issues" if show_issues else "Timeline"
if since:
    print(f"{mode}: {label} since {since}")
else:
    print(f"{mode}: {label}")
print()

limited_entries = entries[:limit]
if show_summary:
    all_terms = sorted({term for path in {entry["path"] for entry in entries} for term in entry_terms.get(path, set()) if term})
    print("Summary:")
    print(f"- entries: {len(entries)}")
    print(f"- nodes: {len({entry['path'] for entry in entries})}")
    print(f"- tags: {', '.join(all_terms) if all_terms else 'none'}")
    print()

if not entries:
    if show_issues:
        print("No matching Open Issues entries.")
    else:
        print("No matching Change Log entries.")
    print("Hint: run generate_memory_map.sh --project <path> --full or check YYYY-MM-DD dates.")
    sys.exit(0)

for entry in limited_entries:
    print(f"{entry['date']} {entry['path']}")
    print(f"- {entry['text']}")
    for detail in entry["details"]:
        print(f"  {detail}")
    print()
PY
