#!/usr/bin/env bash
# generate_memory_map.sh — scan meta/*.md nodes and rebuild MEMORY_MAP.md
# Also auto-computes blocks (reverse depends_on), validates topology,
# extracts keywords for semantic fallback, and estimates token costs.
#
# Usage:
#   scripts/generate_memory_map.sh              # Incremental (skip unchanged)
#   scripts/generate_memory_map.sh --full       # Force full rebuild
#   scripts/generate_memory_map.sh --changed <file>  # Re-parse specific node only
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "Error: requires bash 4+ (current: $BASH_VERSION)" >&2
  echo "macOS: brew install bash; ensure /opt/homebrew/bin or /usr/local/bin in PATH" >&2
  exit 1
fi

# ─── Argument parsing ──────────────────────────────────────────────────
FULL_REBUILD=false
CHANGED_FILE=""
STATS_MODE=false
USE_DB=false
DB_PATH=""
PROJECT_ROOT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) FULL_REBUILD=true; shift ;;
    --project)
      PROJECT_ROOT_OVERRIDE="$2"
      shift 2
      ;;
    --changed)
      CHANGED_FILE="$2"
      shift 2
      ;;
    --stats) STATS_MODE=true; shift ;;
    --db) USE_DB=true; DB_PATH="${PROJECT_ROOT}/.synapse/cache/memory.db"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ "$STATS_MODE" = true ]; then
  START_TIME=$(date +%s)
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "$PROJECT_ROOT_OVERRIDE" ]; then
  PROJECT_ROOT="$(cd "$PROJECT_ROOT_OVERRIDE" && pwd)"
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"
fi
META_DIR="${PROJECT_ROOT}/meta"
OUTPUT="${PROJECT_ROOT}/MEMORY_MAP.md"
CACHE_DIR="${PROJECT_ROOT}/.claude/.synapse_cache"

# Set DB_PATH after PROJECT_ROOT is resolved
if [ "$USE_DB" = true ]; then
  DB_PATH="${PROJECT_ROOT}/.synapse/cache/memory.db"
fi

mkdir -p "$CACHE_DIR"

if [ ! -d "$META_DIR" ]; then
  echo "No meta/ directory found at $META_DIR. Nothing to index."
  exit 0
fi

# ─── Incremental mode: re-parse only specified node(s) ─────────────────
if [ -n "$CHANGED_FILE" ] && [ -f "$META_DIR/$CHANGED_FILE" ]; then
  fm=$(awk '/^---$/ {c++; next} c==1' "$META_DIR/$CHANGED_FILE" 2>/dev/null || true)

  node_id=$(echo "$fm" | sed -n 's/^id:[[:space:]]*//p' | tr -d '"' | xargs)
  node_type=$(echo "$fm" | sed -n 's/^type:[[:space:]]*//p' | tr -d '"' | xargs)
  node_status=$(echo "$fm" | sed -n 's/^status:[[:space:]]*//p' | tr -d '"' | xargs)
  node_summary=$(echo "$fm" | sed -n 's/^summary:[[:space:]]*//p' | tr -d '"' | xargs)
  node_updated=$(echo "$fm" | sed -n 's/^updated:[[:space:]]*//p' | tr -d '"' | xargs)

  if [ -z "$node_id" ]; then
    echo "Warning: --changed file has no id in frontmatter: $CHANGED_FILE" >&2
    exit 0
  fi

  MAP_FILE="${PROJECT_ROOT}/MEMORY_MAP.json"

  if [ -f "$MAP_FILE" ] && command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys

node_id = '${node_id}'
changed_file = '${CHANGED_FILE}'
map_file = '${MAP_FILE}'

try:
    with open(map_file) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {'nodes': {}, 'tag_index': {}, 'keyword_index': {}, 'affinity': {}}

# Build node data
depends_on = []
auto_linked = []
tags_list = []
aliases_list = []

fm = '''$(echo "$fm" | sed "s/'/'\\\\''/g")'''

for line in fm.split('\n'):
    line = line.strip()
    if line.startswith('depends_on:'):
        val = line.split(':', 1)[1].strip()
        if val.startswith('[') and val.endswith(']'):
            depends_on = [v.strip().strip(\"'\\\"\") for v in val[1:-1].split(',') if v.strip()]
    elif line.startswith('auto_linked:'):
        val = line.split(':', 1)[1].strip()
        if val.startswith('[') and val.endswith(']'):
            auto_linked = [v.strip().strip(\"'\\\"\") for v in val[1:-1].split(',') if v.strip()]
    elif line.startswith('tags:'):
        val = line.split(':', 1)[1].strip()
        if val.startswith('[') and val.endswith(']'):
            tags_list = [v.strip().strip(\"'\\\"\") for v in val[1:-1].split(',') if v.strip()]
    elif line.startswith('aliases:'):
        val = line.split(':', 1)[1].strip()
        if val.startswith('[') and val.endswith(']'):
            aliases_list = [v.strip().strip(\"'\\\"\") for v in val[1:-1].split(',') if v.strip()]

node_data = {
    'id': node_id,
    'type': '${node_type}',
    'status': '${node_status}',
    'summary': '${node_summary}',
    'depends_on': depends_on,
    'auto_linked': auto_linked,
    'tags': tags_list,
    'aliases': aliases_list,
    'updated': '${node_updated}',
    'file': changed_file
}

# Update or insert node
data['nodes'][node_id] = node_data

# Rebuild tag index for this node's tags
if 'tag_index' not in data:
    data['tag_index'] = {}
for tag in tags_list:
    if tag not in data['tag_index']:
        data['tag_index'][tag] = []
    if node_id not in data['tag_index'][tag]:
        data['tag_index'][tag].append(node_id)

# Recompute blocks for all nodes
for nid in data['nodes']:
    if 'blocks' not in data['nodes'][nid]:
        data['nodes'][nid]['blocks'] = []
    else:
        data['nodes'][nid]['blocks'] = []

for nid, ndata in data['nodes'].items():
    for dep in ndata.get('depends_on', []):
        dep_id = dep.replace('meta/', '').replace('.md', '')
        if dep_id in data['nodes']:
            if nid not in data['nodes'][dep_id].get('blocks', []):
                data['nodes'][dep_id].setdefault('blocks', []).append(nid)
    for link in ndata.get('auto_linked', []):
        link_id = link.replace('meta/', '').replace('.md', '')
        if link_id in data['nodes']:
            if nid not in data['nodes'][link_id].get('blocks', []):
                data['nodes'][link_id].setdefault('blocks', []).append(nid)

with open(map_file, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(f'Incremental update: {node_id} ({changed_file})')
" 2>&1

  # Also update cache for this file
  ck=$(echo "$CHANGED_FILE" | sed 's/[\/\\]/_/g')
  awk '/^---$/ {c++; next} c==1' "$META_DIR/$CHANGED_FILE" > "${CACHE_DIR}/${ck}.cache" 2>/dev/null || true

  else
    echo "Incremental update: $node_id ($CHANGED_FILE) — full rebuild required (no MAP or python3)"
  fi

  # Exit early — skip full rebuild
  exit 0
fi

# ─── Cache helpers ─────────────────────────────────────────────────────
# Cache key: sanitized relative path (replace / with _)
cache_key() {
  local rel="$1"
  echo "$rel" | sed 's/[\/\\]/_/g'
}

# Check if a node needs re-parsing (mtime > cached mtime, or no cache)
needs_reparse() {
  local file="$1" rel="$2"
  local ck cached_mtime file_mtime
  ck=$(cache_key "$rel")
  local cache_file="${CACHE_DIR}/${ck}.cache"

  [ ! -f "$cache_file" ] && return 0  # No cache → reparse
  [ "$FULL_REBUILD" = true ] && return 0  # Full rebuild → reparse

  # If --changed specified, only reparse the changed file
  if [ -n "$CHANGED_FILE" ]; then
    if [ "$rel" = "$CHANGED_FILE" ]; then return 0; else return 1; fi
  fi

  # Compare mtime: reparse if file newer than cache
  file_mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0)
  cached_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
  [ "$file_mtime" -gt "$cached_mtime" ] && return 0
  return 1
}

# Read cached parse result
read_cache() {
  local rel="$1"
  local ck
  ck=$(cache_key "$rel")
  cat "${CACHE_DIR}/${ck}.cache" 2>/dev/null || true
}

# Write parse result to cache
write_cache() {
  local rel="$1" result="$2"
  local ck
  ck=$(cache_key "$rel")
  echo "$result" > "${CACHE_DIR}/${ck}.cache"
}

# ─── Extract a YAML scalar field (single-line) ────────────────────────
extract_scalar() {
  local key="$1" fm="$2"
  echo "$fm" | sed -n "s/^${key}:[[:space:]]*//p" | tr -d '"' | xargs
}

# ─── Extract a YAML list field — handles BOTH formats ─────────────────
#   tags: [auth, login, jwt]          ← inline
#   tags:                             ← multi-line
#     - auth
#     - login
# Output: one item per line (so callers can join with the separator they need).
extract_list() {
  local key="$1" fm="$2"

  # Try inline first: key: [a, b]
  local inline
  inline=$(echo "$fm" | sed -n "/^${key}:[[:space:]]*\[/s/^${key}:[[:space:]]*//p" | tr -d '[]"')
  if [ -n "$(echo "$inline" | xargs)" ]; then
    echo "$inline" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d'
    return
  fi

  # Multi-line: key:\n  - a\n  - b
  echo "$fm" | awk -v k="$key" -v in_list=0 '
    $0 ~ ("^" k ":[[:space:]]*$") { in_list=1; next }
    in_list && /^[[:space:]]*-[[:space:]]+/ {
      item = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      gsub(/["\47\],]/, "", item)
      sub(/[[:space:]]+$/, "", item)
      if (item != "") printf "%s\n", item
      next
    }
    in_list && /^[[:space:]]*$/ { next }
    in_list && /^[a-zA-Z]/ { in_list=0 }
  '
}

# ─── Extract keywords from node body for semantic fallback ─────────────
# Returns comma-separated keywords: API endpoints, function names, tables, config keys
extract_keywords() {
  local body="$1"
  local kw=""

  # API endpoints: capture only the path (drop the HTTP verb so "GET" alone doesn't pollute the index)
  local apis
  apis=$(echo "$body" | grep -oE '(GET|POST|PUT|DELETE|PATCH)[[:space:]]+(/[a-zA-Z0-9_/{}:-]+)' \
    | sed -E 's/^(GET|POST|PUT|DELETE|PATCH)[[:space:]]+//' \
    | sort -u | head -10)
  if [ -n "$apis" ]; then
    kw="$kw"$'\n'"$apis"
  fi

  # Function/method calls: word()
  local funcs
  funcs=$(echo "$body" | grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\(\)' | sort -u | head -10)
  if [ -n "$funcs" ]; then
    kw="$kw"$'\n'"$funcs"
  fi

  # Table names from "**Table**: name"
  local tables
  tables=$(echo "$body" | sed -n 's/.*\*\*[Tt]able\*\*:[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p' | sort -u | head -10)
  if [ -n "$tables" ]; then
    kw="$kw"$'\n'"$tables"
  fi

  # Config keys: ALL_CAPS identifiers (3+ chars). Drop HTTP verbs — they're already captured by the API extractor above.
  local configs
  configs=$(echo "$body" | grep -oE '\b[A-Z][A-Z0-9_]{2,}\b' \
    | grep -vE '^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)$' \
    | sort -u | head -10)
  if [ -n "$configs" ]; then
    kw="$kw"$'\n'"$configs"
  fi

  # Deduplicate and format
  echo "$kw" | sort -u | sed '/^$/d' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g'
}

# ─── Extract Change Log dates + summaries from node body ───────────────
extract_changelog_entries() {
  local file="$1"
  awk '
    /^## Change Log/ { in_ch = 1; next }
    in_ch && /^## / { exit }
    in_ch && /^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]/ {
      line = $0
      sub(/^- \[/, "", line)
      date = line
      sub(/\].*$/, "", date)
      summary = $0
      sub(/^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}\][[:space:]]*/, "", summary)
      gsub(/^\*\*(Context|Change|Impact|Affected)\*\*:[[:space:]]*/, "", summary)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", summary)
      if (length(summary) > 120) summary = substr(summary, 1, 120) "..."
      if (date ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) print date "|" summary
    }
  ' "$file" 2>/dev/null || true
}

# ─── Parse a single node file ─────────────────────────────────────────
parse_node() {
  local file="$1"
  local rel="${file#$PROJECT_ROOT/}"

  local fm
  fm=$(awk '/^---$/ {c++; next} c==1' "$file" 2>/dev/null || true)
  [ -z "$fm" ] && return

  local id type status updated tags depends_on auto_linked summary aliases
  id=$(extract_scalar "id" "$fm")
  type=$(extract_scalar "type" "$fm")
  status=$(extract_scalar "status" "$fm")
  updated=$(extract_scalar "updated" "$fm")
  tags=$(extract_list "tags" "$fm" | tr '\n' ',' | sed 's/,$//')
  depends_on=$(extract_list "depends_on" "$fm" | tr '\n' ',' | sed 's/,$//')
  auto_linked=$(extract_list "auto_linked" "$fm" | tr '\n' ',' | sed 's/,$//')
  summary=$(extract_scalar "summary" "$fm")
  aliases=$(extract_list "aliases" "$fm" | tr '\n' ',' | sed 's/,$//')

  # Warn on missing required fields (don't skip — let user fix)
  [ -z "$id" ] && echo "WARNING: $rel — missing required field 'id'" >&2
  [ -z "$type" ] && echo "WARNING: $rel — missing required field 'type'" >&2

  # Skip archived
  [ "$status" = "archived" ] && return

  # Extract keywords from body (after frontmatter)
  local body
  body=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$file" 2>/dev/null || true)
  local keywords
  keywords=$(extract_keywords "$body")

  # Token estimate: bytes / 4
  local file_size tokens
  file_size=$(wc -c < "$file" 2>/dev/null || echo 0)
  tokens=$(( file_size / 4 ))

  echo "${id:-unknown}|${type:-unknown}|${status:-unknown}|${updated:-}|${tags}|${depends_on}|${auto_linked}|${summary}|${keywords}|${aliases}|${tokens}|${rel}"
}

# ─── First pass: collect all nodes ─────────────────────────────────────
declare -A NODE_DEPS           # rel_path -> comma-separated depends_on
declare -A NODE_AUTO_LINKED    # rel_path -> comma-separated auto_linked
declare -A NODE_INFO           # rel_path -> full parsed line
declare -A CHANGELOG_PER_NODE  # rel_path -> newline-separated "date|summary"
declare -A CHANGELOG_INDEX     # YYYY-MM -> newline-separated "date|id|rel|summary"
declare -a ALL_NODES

parsed_count=0
cached_count=0

while IFS= read -r -d '' file; do
  rel="${file#$PROJECT_ROOT/}"

  if needs_reparse "$file" "$rel"; then
    result=$(parse_node "$file")
    if [ -n "$result" ]; then
      write_cache "$rel" "$result"
      parsed_count=$((parsed_count + 1))
    fi
  else
    result=$(read_cache "$rel")
  fi

  if [ -n "$result" ]; then
    IFS='|' read -r id type status updated tags deps auto_linked summary keywords aliases tokens rel <<< "$result"
    ALL_NODES+=("$result")
    NODE_DEPS["$rel"]="$deps"
    NODE_AUTO_LINKED["$rel"]="$auto_linked"
    NODE_INFO["$rel"]="$result"
    cached_count=$((cached_count + 1))

    # Build change log index
    ch_entries=$(extract_changelog_entries "$file")
    CHANGELOG_PER_NODE["$rel"]="$ch_entries"
    if [ -n "$ch_entries" ]; then
      while IFS='|' read -r ch_date ch_summary; do
        [ -z "$ch_date" ] && continue
        ch_month="${ch_date:0:7}"
        CHANGELOG_INDEX["$ch_month"]="${CHANGELOG_INDEX[$ch_month]:-}${ch_date}|${id}|${rel}|${ch_summary}
"
      done <<< "$ch_entries"
    fi
  fi
done < <(find "$META_DIR" -maxdepth 2 -name '*.md' ! -name 'MEMORY_MAP.md' -print0 2>/dev/null || true)

# Log incremental stats
if [ "$FULL_REBUILD" = true ]; then
  echo "Full rebuild: re-parsed $parsed_count nodes."
elif [ -n "$CHANGED_FILE" ]; then
  echo "Incremental (--changed $CHANGED_FILE): re-parsed $parsed_count node(s), loaded $cached_count from cache."
else
  echo "Incremental: re-parsed $parsed_count changed node(s), loaded $((cached_count - parsed_count)) from cache."
fi

# ─── Compute blocks = reverse(effective_edges) ────────────────────────
declare -A NODE_BLOCKS  # rel_path -> space-separated list of paths that depend on it
for rel in "${!NODE_INFO[@]}"; do
  deps="${NODE_DEPS[$rel]:-}"
  auto_links="${NODE_AUTO_LINKED[$rel]:-}"
  edges="${deps}${deps:+,}${auto_links}"
  [ -z "$edges" ] && continue
  IFS=',' read -ra EDGE_ARR <<< "$edges"
  for d in "${EDGE_ARR[@]}"; do
    d=$(echo "$d" | xargs)
    [ -z "$d" ] && continue
    NODE_BLOCKS["$d"]="${NODE_BLOCKS[$d]:-} ${rel}"
  done
done

# ─── Build tag index ───────────────────────────────────────────────────
declare -A TAG_MAP  # tag -> newline-separated "id | rel | deps | blocks | summary | keywords | aliases | tokens"
for rel in "${!NODE_INFO[@]}"; do
  result="${NODE_INFO[$rel]}"
  IFS='|' read -r id type status updated tags deps auto_linked summary keywords aliases tokens rel2 <<< "$result"
  blocks=$(echo "${NODE_BLOCKS[$rel]:-}" | xargs | tr ' ' ',')

  # Index by official tags
  IFS=',' read -ra TAGS <<< "$tags"
  for tag in "${TAGS[@]}"; do
    tag=$(echo "$tag" | xargs)
    [ -z "$tag" ] && continue
    tag_lower=$(echo "$tag" | tr '[:upper:]' '[:lower:]')
    TAG_MAP["$tag_lower"]="${TAG_MAP[$tag_lower]:-}${id}|${rel}|${deps}|${blocks}|${auto_linked}|${summary}|${keywords}|${aliases}|${tokens}
"
  done

  # Index by aliases (natural language synonyms) — same structure as tags
  if [ -n "$aliases" ]; then
    IFS=',' read -ra ALS <<< "$aliases"
    for al in "${ALS[@]}"; do
      al=$(echo "$al" | xargs | tr '[:upper:]' '[:lower:]')
      [ -z "$al" ] && continue
      # Only add if not already covered by a tag
      if [ -z "${TAG_MAP[$al]:-}" ] || ! echo "${TAG_MAP[$al]}" | grep -qF "${id}|"; then
        TAG_MAP["$al"]="${TAG_MAP[$al]:-}${id}|${rel}|${deps}|${blocks}|${summary}|${keywords}|${aliases}|${tokens}
"
      fi
    done
  fi
done

# ─── Build tag affinity map ────────────────────────────────────────────
# Compute co-occurrence frequency between tags across all nodes.
# If two tags appear together in >30% of nodes containing either tag,
# they are marked as semantically related.
declare -A TAG_CO_OCCUR    # "tag1|||tag2" -> co-occurrence count
declare -A TAG_NODE_COUNT  # tag -> number of nodes containing this tag

for rel in "${!NODE_INFO[@]}"; do
  result="${NODE_INFO[$rel]}"
  IFS='|' read -r id type status updated tags deps auto_linked summary keywords aliases tokens rel2 <<< "$result"

  IFS=',' read -ra TAGS_ARR <<< "$tags"
  node_tags=()
  for tag in "${TAGS_ARR[@]}"; do
    tag=$(echo "$tag" | xargs | tr '[:upper:]' '[:lower:]')
    [ -z "$tag" ] && continue
    TAG_NODE_COUNT["$tag"]=$(( ${TAG_NODE_COUNT[$tag]:-0} + 1 ))
    node_tags+=("$tag")
  done

  # Count co-occurrences (only for pairs within same node)
  for ((i=0; i<${#node_tags[@]}; i++)); do
    t1="${node_tags[$i]}"
    for ((j=i+1; j<${#node_tags[@]}; j++)); do
      t2="${node_tags[$j]}"
      # Normalize pair order
      if [[ "$t1" < "$t2" ]]; then pair="$t1|||$t2"; else pair="$t2|||$t1"; fi
      TAG_CO_OCCUR["$pair"]=$(( ${TAG_CO_OCCUR[$pair]:-0} + 1 ))
    done
  done
done

# ─── Build keyword index ───────────────────────────────────────────────
declare -A KEYWORD_MAP  # keyword -> newline-separated "id | rel | tags"
for rel in "${!NODE_INFO[@]}"; do
  result="${NODE_INFO[$rel]}"
  IFS='|' read -r id type status updated tags deps auto_linked summary keywords aliases tokens rel2 <<< "$result"

  IFS=',' read -ra KWS <<< "$keywords"
  for kw in "${KWS[@]}"; do
    kw=$(echo "$kw" | xargs | tr '[:upper:]' '[:lower:]')
    [ -z "$kw" ] && continue
    KEYWORD_MAP["$kw"]="${KEYWORD_MAP[$kw]:-}${id}|${rel}|${tags}
"
  done
done

# ─── Write MEMORY_MAP.md ───────────────────────────────────────────────
set +eu  # output block: allow unset variables and don't exit on pipeline/subshell errors
{

  echo '<!-- AUTO-GENERATED by scripts/generate_memory_map.sh. DO NOT EDIT MANUALLY. -->'
  echo "# Project Memory Graph Index"
  echo
  echo "> Retrieval Protocol: Read MAP → Target node (summary first) → Bounded BFS deps (depth ≤ 2, width ≤ 5)"
  echo "> Cost-conscious: token estimates shown per node. Spend wisely."
  echo

  # ─── Tag Index ───────────────────────────────────────────────────────
  echo "## Tag Index"
  echo

  if [ ${#TAG_MAP[@]} -eq 0 ]; then
    echo "No active memory nodes found."
    echo
  else
    while IFS= read -r tag; do
      [ -z "$tag" ] && continue
      echo "### \`$tag\`"
      echo
      printf '%s' "${TAG_MAP[$tag]}" | sort -t'|' -k1,1 -u | while IFS='|' read -r nid nrel ndeps nblocks nauto_linked nsummary nkeywords naliases ntokens; do
        echo "- **$nid** — \`$nrel\` (~${ntokens} tok)"
        [ -n "$nsummary" ] && echo "  summary: $nsummary"
        [ -n "$naliases" ] && [ "$naliases" != " " ] && echo "  aliases: $(echo "$naliases" | sed 's/,/, /g')"
        [ -n "$ndeps" ] && echo "  depends_on: $(echo "$ndeps" | sed 's/,/, /g')"
        [ -n "$nauto_linked" ] && echo "  auto_linked: $(echo "$nauto_linked" | sed 's/,/, /g')"
        [ -n "$nblocks" ] && echo "  blocks: $(echo "$nblocks" | sed 's/,/, /g')"
      done
      echo
    done < <(printf '%s\n' "${!TAG_MAP[@]}" | sort)
  fi

  # ─── Tag Affinity (semantic synonym expansion) ───────────────────────
  echo "## Tag Affinity"
  echo
  echo "> Auto-detected tag relationships based on co-occurrence across nodes."
  echo "> Use when tag matching fails — query synonyms may surface related nodes."
  echo

  affinity_count=0
  if [ ${#TAG_CO_OCCUR[@]} -eq 0 ]; then
    echo "No tag affinities detected (need ≥2 tags per node)."
    echo
  else
    for pair in "${!TAG_CO_OCCUR[@]}"; do
      co_count="${TAG_CO_OCCUR[$pair]}"
      t1="${pair%%|||*}"
      t2="${pair##*|||}"
      [ -z "$t1" ] && continue
      [ -z "$t2" ] && continue

      c1="${TAG_NODE_COUNT[$t1]:-0}"
      c2="${TAG_NODE_COUNT[$t2]:-0}"
      if [ "$c1" -eq 0 ] || [ "$c2" -eq 0 ]; then continue; fi

      min_count=$c1
      [ "$c2" -lt "$min_count" ] && min_count=$c2

      rate=$(( co_count * 100 / min_count ))

      if [ "$rate" -ge 30 ]; then
        echo "- \`$t1\` ↔ \`$t2\` (co-occur in $co_count / $min_count nodes, ${rate}%)"
        affinity_count=$((affinity_count + 1))
      fi
    done
    [ "$affinity_count" -eq 0 ] && echo "No strong affinities detected (threshold: 30% co-occurrence)."
    echo
  fi

  # ─── Keyword Index (semantic fallback) ───────────────────────────────
  echo "## Keyword Index"
  echo
  echo "> Fallback when tag matching fails or returns too many results."
  echo "> Keywords auto-extracted from API endpoints, function names, table names, config keys."
  echo

  if [ ${#KEYWORD_MAP[@]} -eq 0 ]; then
    echo "No keywords extracted."
    echo
  else
    while IFS= read -r kw; do
      [ -z "$kw" ] && continue
      echo "### \`$kw\`"
      echo
      printf '%s' "${KEYWORD_MAP[$kw]}" | sort -t'|' -k1,1 -u | while IFS='|' read -r nid nrel ntags; do
        echo "- **$nid** — \`$nrel\` (tags: ${ntags:-none})"
      done
      echo
    done < <(printf '%s\n' "${!KEYWORD_MAP[@]}" | sort)
  fi

  # ─── All Active Nodes ────────────────────────────────────────────────
  echo "## All Active Nodes"
  echo

  if [ ${#ALL_NODES[@]} -eq 0 ]; then
    echo "None."
  else
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      IFS='|' read -r nid ntype nstatus nupdated ntags ndeps nauto_linked nsummary nkeywords naliases ntokens nrel <<< "$entry"
      case "$ntype" in
        module) pfx="[mod]" ;;
        feature) pfx="[feat]" ;;
        *) pfx="[$ntype]" ;;
      esac
      nblocks=$(echo "${NODE_BLOCKS[$nrel]:-}" | xargs | tr ' ' ',')
      echo "- $pfx **$nid** ($nstatus, ~${ntokens} tok) — \`$nrel\`"
      [ -n "$nupdated" ] && echo "  updated: $nupdated"
      [ -n "$nsummary" ] && echo "  summary: $nsummary"
      [ -n "$naliases" ] && [ "$naliases" != " " ] && echo "  aliases: $(echo "$naliases" | sed 's/,/, /g')"
      [ -n "$ndeps" ] && echo "  depends_on: $(echo "$ndeps" | sed 's/,/, /g')"
      [ -n "$nauto_linked" ] && echo "  auto_linked: $(echo "$nauto_linked" | sed 's/,/, /g')"
      [ -n "$nblocks" ] && echo "  blocks: $(echo "$nblocks" | sed 's/,/, /g')"
    done < <(printf '%s\n' "${ALL_NODES[@]}" | sort -t'|' -k2,2 -k1,1)
    echo
  fi

  # ─── Status Digest (lightweight global overview, ~1 line per node) ──
  echo "## Status Digest"
  echo
  echo "> Read THIS section only for vague status queries. Cost: ~200 tokens total."
  echo
  while IFS= read -r nrel; do
    nrel_clean=$(echo "$nrel" | xargs)
    [ -z "$nrel_clean" ] && continue
    result="${NODE_INFO[$nrel_clean]}"
    IFS='|' read -r nid ntype nstatus nupdated ntags ndeps nauto_linked nsummary nkeywords naliases ntokens rel2 <<< "$result"
    [ -z "$nid" ] && continue
    # Count open issues
    issue_cnt=0
    fpath="${PROJECT_ROOT}/${nrel_clean}"
    if [ -f "$fpath" ]; then
      issue_cnt=$(awk '/^## Open Issues$/,/^## / { if (/^- /) c++ } END { print c+0 }' "$fpath" 2>/dev/null)
      last_ch=$(awk '/^## Change Log$/,/^$|^---$/ { if (/^- /) { print; exit } }' "$fpath" 2>/dev/null | sed 's/^- //' | xargs 2>/dev/null || true)
    fi
    echo "- **$nid** ($nstatus, updated: ${nupdated:-?}, ${issue_cnt:-0} open, ~${ntokens} tok)"
    [ -n "$nsummary" ] && echo "  $nsummary"
    [ -n "${last_ch:-}" ] && echo "  Last: $last_ch"
    [ -n "${ndeps:-}" ] && [ "$ndeps" != " " ] && echo "  depends_on: $(echo "$ndeps" | sed 's/,/, /g')"
    [ -n "${nauto_linked:-}" ] && [ "$nauto_linked" != " " ] && echo "  auto_linked: $(echo "$nauto_linked" | sed 's/,/, /g')"
    nblocks=$(echo "${NODE_BLOCKS[$nrel_clean]:-}" 2>/dev/null | xargs 2>/dev/null | tr ' ' ',' 2>/dev/null || true)
    [ -n "${nblocks:-}" ] && [ "$nblocks" != " " ] && echo "  blocks: $(echo "$nblocks" | sed 's/,/, /g')"
  done < <(printf '%s\n' "${!NODE_INFO[@]}" | sort)
  echo

  # ─── Change Log Index ──────────────────────────────────────────────────
  echo "## Change Log Index"
  echo
  echo "> Time-filtered node lookup for Filtered BFS compound queries."
  echo "> Grouped by month. Intersect with Tag Index for date + domain queries."
  echo

  if [ ${#CHANGELOG_INDEX[@]} -eq 0 ]; then
    echo "No Change Log entries found."
    echo
  else
    while IFS= read -r month; do
      [ -z "$month" ] && continue
      echo "### ${month}"
      echo
      printf '%s' "${CHANGELOG_INDEX[$month]}" | sort -t'|' -k1,1r | while IFS='|' read -r ch_date ch_id ch_rel ch_summary; do
        [ -z "$ch_date" ] && continue
        echo "- **${ch_date}** — \`${ch_id}\` — ${ch_summary:-(no summary)}"
      done
      echo
    done < <(printf '%s\n' "${!CHANGELOG_INDEX[@]}" | sort -r)
  fi

  # ─── Progress Summary ─────────────────────────────────────────────────
  echo "## Progress Summary"
  echo
  echo "> Auto-computed project health snapshot. Read for \"how are we doing?\" queries."
  echo

  total_nodes=${#ALL_NODES[@]}
  stable_cnt=0
  in_progress_cnt=0
  total_issues=0
  blocked_nodes=""

  while IFS= read -r nrel; do
    nrel_clean=$(echo "$nrel" | xargs)
    [ -z "$nrel_clean" ] && continue
    result="${NODE_INFO[$nrel_clean]}"
    IFS='|' read -r _ _ nstatus _ _ _ _ _ _ _ _ _ <<< "$result"
    [ -z "$nstatus" ] && continue

    case "$nstatus" in
      stable) stable_cnt=$((stable_cnt + 1)) ;;
      in-progress) in_progress_cnt=$((in_progress_cnt + 1)) ;;
      *) ;;
    esac

    # Count open issues
    fpath="${PROJECT_ROOT}/${nrel_clean}"
    if [ -f "$fpath" ]; then
      issues=$(awk '/^## Open Issues$/,/^## / { if (/^- /) c++ } END { print c+0 }' "$fpath" 2>/dev/null || echo 0)
      total_issues=$((total_issues + issues))
      if [ "$issues" -gt 0 ]; then
        nid=$(echo "$result" | cut -d'|' -f1)
        blocked_nodes="${blocked_nodes}${nid}|${issues}|${nrel_clean}
"
      fi
    fi
  done < <(printf '%s\n' "${!NODE_INFO[@]}" | sort)

  if [ "$total_nodes" -gt 0 ]; then
    stable_pct=$(( stable_cnt * 100 / total_nodes ))
    in_progress_pct=$(( in_progress_cnt * 100 / total_nodes ))
    echo "- **${total_nodes}** total active nodes"
    echo "- **${stable_cnt}** stable (${stable_pct}%), **${in_progress_cnt}** in-progress (${in_progress_pct}%)"
    echo "- **${total_issues}** open issues across all nodes"
    echo

    # Suggested next priorities
    echo "### Suggested Next Priorities"
    echo

    if [ -n "$blocked_nodes" ]; then
      echo "Nodes with open issues (sorted by issue count):"
      echo
      printf '%s' "$blocked_nodes" | sort -t'|' -k2,2rn | while IFS='|' read -r bnid bissues brel; do
        [ -z "$bnid" ] && continue
        echo "- **$bnid** — ${bissues} open issue(s) — \`$brel\`"
      done
      echo
    fi

    # In-progress nodes (active work)
    in_progress_list=""
    while IFS= read -r nrel; do
      nrel_clean=$(echo "$nrel" | xargs)
      [ -z "$nrel_clean" ] && continue
      result="${NODE_INFO[$nrel_clean]}"
      nstatus=$(echo "$result" | cut -d'|' -f3)
      [ "$nstatus" != "in-progress" ] && continue
      nid=$(echo "$result" | cut -d'|' -f1)
      nupdated=$(echo "$result" | cut -d'|' -f4)
      in_progress_list="${in_progress_list}${nid}|${nupdated}|${nrel_clean}
"
    done < <(printf '%s\n' "${!NODE_INFO[@]}" | sort)

    if [ -n "$in_progress_list" ]; then
      echo "In-progress nodes (focus candidates):"
      echo
      printf '%s' "$in_progress_list" | sort -t'|' -k2,2r | while IFS='|' read -r pnid pupdated prel; do
        [ -z "$pnid" ] && continue
        echo "- **$pnid** (updated: ${pupdated:-?}) — \`$prel\`"
      done
      echo
    fi

    if [ -z "$blocked_nodes" ] && [ -z "$in_progress_list" ]; then
      echo "All nodes stable with no open issues. No immediate action suggested."
      echo
    fi
  else
    echo "No active nodes."
    echo
  fi

  # ─── Topology validation ─────────────────────────────────────────────
  echo "## Topology Health"
  echo

  warnings=0

  # Parse failures (frontmatter validation — independent of parse pipeline)
  while IFS= read -r -d '' file; do
    rel="${file#$PROJECT_ROOT/}"
    [[ "$rel" == *"MEMORY_MAP.md"* ]] && continue
    [[ "$rel" == *"archive"* ]] && continue
    fm=$(awk '/^---$/ {c++; next} c==1' "$file" 2>/dev/null || true)
    [ -z "$fm" ] && continue

    if ! echo "$fm" | grep -qE '^id:[[:space:]]*[^[:space:]]'; then
      echo "- 💥 PARSE FAILURE: \`$rel\` — missing required field 'id'"
      warnings=$((warnings + 1))
    fi
    if ! echo "$fm" | grep -qE '^type:[[:space:]]*(module|feature|archived)'; then
      echo "- 💥 PARSE FAILURE: \`$rel\` — missing or invalid field 'type' (expected: module|feature|archived)"
      warnings=$((warnings + 1))
    fi
    if ! echo "$fm" | grep -qE '^status:[[:space:]]*(in-progress|stable|archived)'; then
      echo "- 💥 PARSE FAILURE: \`$rel\` — missing or invalid field 'status' (expected: in-progress|stable|archived)"
      warnings=$((warnings + 1))
    fi
  done < <(find "$META_DIR" -maxdepth 2 -name '*.md' ! -name 'MEMORY_MAP.md' -print0 2>/dev/null || true)

  # Dead links (depends_on)
  for rel in "${!NODE_DEPS[@]}"; do
    deps="${NODE_DEPS[$rel]}"
    [ -z "$deps" ] && continue
    IFS=',' read -ra DEP_ARR <<< "$deps"
    for d in "${DEP_ARR[@]}"; do
      d=$(echo "$d" | xargs)
      [ -z "$d" ] && continue
      if [ ! -f "${PROJECT_ROOT}/${d}" ]; then
        echo "- ⚠ DEAD LINK: \`$rel\` depends_on \`$d\` — file not found"
        warnings=$((warnings + 1))
      fi
    done
  done

  # Dead links (auto_linked)
  for rel in "${!NODE_AUTO_LINKED[@]}"; do
    auto_deps="${NODE_AUTO_LINKED[$rel]}"
    [ -z "$auto_deps" ] && continue
    IFS=',' read -ra AUTO_DEP_ARR <<< "$auto_deps"
    for d in "${AUTO_DEP_ARR[@]}"; do
      d=$(echo "$d" | xargs)
      [ -z "$d" ] && continue
      if [ ! -f "${PROJECT_ROOT}/${d}" ]; then
        echo "- ⚠ DEAD LINK: \`$rel\` auto_linked \`$d\` — file not found"
        warnings=$((warnings + 1))
      fi
    done
  done

  # Cycle detection (A depends_on B, B depends_on A — using full rel paths)
  declare -A CYCLE_SEEN
  for rel in "${!NODE_DEPS[@]}"; do
    deps="${NODE_DEPS[$rel]}"
    [ -z "$deps" ] && continue
    IFS=',' read -ra DEP_ARR <<< "$deps"
    for d in "${DEP_ARR[@]}"; do
      d=$(echo "$d" | xargs)
      [ -z "$d" ] && continue
      # Build a normalized pair key (sorted) to avoid duplicate reports
      if [[ "$rel" < "$d" ]]; then pair="$rel|||$d"; else pair="$d|||$rel"; fi
      [ "${CYCLE_SEEN[$pair]:-}" = "1" ] && continue
      CYCLE_SEEN["$pair"]=1
      d_deps="${NODE_DEPS[$d]:-}"
      if echo "${d_deps}," | grep -qF "${rel},"; then
        echo "- 🔄 CYCLE: \`$rel\` ⇄ \`$d\` — mutual dependency (OK for some patterns, flag if unintentional)"
        warnings=$((warnings + 1))
      fi
    done
  done

  # Orphan nodes (no deps, no blocks)
  for rel in "${!NODE_INFO[@]}"; do
    deps="${NODE_DEPS[$rel]}"
    auto_links="${NODE_AUTO_LINKED[$rel]:-}"
    edges="${deps}${deps:+,}${auto_links}"
    blocks="${NODE_BLOCKS[$rel]:-}"
    if [ -z "$(echo "$edges" | xargs)" ] && [ -z "$(echo "$blocks" | xargs)" ]; then
      IFS='|' read -r nid _ <<< "${NODE_INFO[$rel]}"
      echo "- ⚪ ORPHAN: \`$rel\` ($nid) — no edges in either direction"
      warnings=$((warnings + 1))
    fi
  done

  # Node size check (warn if > 200 lines)
  for rel in "${!NODE_INFO[@]}"; do
    fpath="${PROJECT_ROOT}/${rel}"
    if [ -f "$fpath" ]; then
      lines=$(wc -l < "$fpath" 2>/dev/null || echo 0)
      if [ "$lines" -gt 200 ]; then
        IFS='|' read -r nid _ <<< "${NODE_INFO[$rel]}"
        echo "- 📦 OVERSIZED: \`$rel\` ($nid) — $lines lines. Consider splitting into sub-nodes."
        warnings=$((warnings + 1))
      fi
    fi
  done

  # Deprecated contracts check
  declare -A DEPRECATED_NODES
  for rel in "${!NODE_INFO[@]}"; do
    fpath="${PROJECT_ROOT}/${rel}"
    if [ -f "$fpath" ]; then
      if awk '/^---$/{fm++} fm==1 && /deprecated:[[:space:]]*[0-9]/{found=1} END{exit !found}' "$fpath" 2>/dev/null; then
        IFS='|' read -r nid _ <<< "${NODE_INFO[$rel]}"
        DEPRECATED_NODES["$rel"]="$nid"
      fi
    fi
  done

  if [ ${#DEPRECATED_NODES[@]} -gt 0 ]; then
    echo ""
    echo "### Deprecated Contracts"
    echo ""
    for dep_rel in "${!DEPRECATED_NODES[@]}"; do
      dep_nid="${DEPRECATED_NODES[$dep_rel]}"
      echo "- ⏳ DEPRECATED: $dep_rel ($dep_nid) contains deprecated contract version(s)"

      # Find nodes that depend_on this deprecated node
      for rel in "${!NODE_DEPS[@]}"; do
        deps="${NODE_DEPS[$rel]}"
        [ -z "$deps" ] && continue
        if echo "$deps," | grep -qF "${dep_rel},"; then
          IFS='|' read -r nid _ <<< "${NODE_INFO[$rel]}"
          echo "   ↳ Referenced by: $rel ($nid) — consider updating dependency"
          warnings=$((warnings + 1))
        fi
      done
    done
  fi

  # Stale nodes check (updated > 30 days ago)
  get_epoch() {
    local d="$1"
    date -d "$d" +%s 2>/dev/null && return
    date -j -f "%Y-%m-%d" "$d" +%s 2>/dev/null && return
    echo ""
  }
  today_epoch=$(get_epoch "$(date +%Y-%m-%d)")
  if [ -n "$today_epoch" ]; then
    stale_found=0
    for rel in "${!NODE_INFO[@]}"; do
      result="${NODE_INFO[$rel]}"
      nstatus=$(echo "$result" | cut -d'|' -f3)
      nupdated=$(echo "$result" | cut -d'|' -f4)
      [ -z "$nupdated" ] && continue
      case "$nstatus" in
        in-progress|stable) ;;
        *) continue ;;
      esac
      updated_epoch=$(get_epoch "$nupdated")
      [ -z "$updated_epoch" ] && continue
      age_days=$(( (today_epoch - updated_epoch) / 86400 ))
      if [ "$age_days" -gt 30 ]; then
        if [ "$stale_found" -eq 0 ]; then
          echo ""
          echo "### Stale Nodes"
          echo ""
          echo "> Nodes not updated in 30+ days. Consider reviewing status."
          echo ""
          stale_found=1
        fi
        nid=$(echo "$result" | cut -d'|' -f1)
        echo "- 🕰 STALE: \`$rel\` ($nid) — last updated ${nupdated} (${age_days} days ago)"
        warnings=$((warnings + 1))
      fi
    done
  fi

  if [ "$warnings" -eq 0 ]; then
    echo "✅ No topology issues detected."
  fi

  echo
  echo "---"
  echo "Generated $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "${#ALL_NODES[@]} active nodes, ${#TAG_MAP[@]} tags, ${#KEYWORD_MAP[@]} keywords, $warnings warnings"

} > "$OUTPUT"
set -eu

# ─── Write MEMORY_MAP.json (machine-readable mirror) ───────────────────
JSON_OUTPUT="${PROJECT_ROOT}/MEMORY_MAP.json"

# Helper: comma-separated string → JSON array
to_json_array() {
  local s="$1"
  [ -z "$s" ] && echo "[]" && return
  echo "[\"$(echo "$s" | sed 's/, /", "/g')\"]"
}

# Helper: change log entries → JSON array of {date, summary}
to_json_changelog() {
  local entries="$1"
  [ -z "$entries" ] && echo "[]" && return
  local first_ch=1
  echo "["
  while IFS='|' read -r ch_date ch_summary; do
    [ -z "$ch_date" ] && continue
    [ "$first_ch" -eq 0 ] && echo ","
    first_ch=0
    local esc_summary
    esc_summary=$(echo "$ch_summary" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
    echo "      { \"date\": \"${ch_date}\", \"summary\": \"${esc_summary}\" }"
  done <<< "$entries"
  echo "    ]"
}

{
  echo "{"
  echo "  \"generated\": \"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\","
  echo "  \"stats\": {"
  echo "    \"nodes\": ${#ALL_NODES[@]},"
  echo "    \"tags\": ${#TAG_MAP[@]},"
  echo "    \"keywords\": ${#KEYWORD_MAP[@]},"
  echo "    \"warnings\": $warnings"
  echo "  },"
  echo "  \"nodes\": ["

  first=1
  for entry in "${ALL_NODES[@]}"; do
    IFS='|' read -r nid ntype nstatus nupdated ntags ndeps nauto_linked nsummary nkeywords naliases ntokens nrel <<< "$entry"
    nblocks=$(echo "${NODE_BLOCKS[$nrel]:-}" | xargs | tr ' ' ',')

    [ "$first" -eq 0 ] && echo ","
    first=0

    tags_json=$(to_json_array "$ntags")
    deps_json=$(to_json_array "$ndeps")
    auto_linked_json=$(to_json_array "$nauto_linked")
    blocks_json=$(to_json_array "$nblocks")
    kw_json=$(to_json_array "$nkeywords")
    aliases_json=$(to_json_array "$naliases")
    ch_entries="${CHANGELOG_PER_NODE[$nrel]:-}"
    ch_json=$(to_json_changelog "$ch_entries")

    echo "    {"
    echo "      \"id\": \"$nid\","
    echo "      \"type\": \"$ntype\","
    echo "      \"status\": \"$nstatus\","
    echo "      \"updated\": \"${nupdated:-}\","
    echo "      \"summary\": \"${nsummary:-}\","
    echo "      \"tags\": $tags_json,"
    echo "      \"aliases\": $aliases_json,"
    echo "      \"depends_on\": $deps_json,"
    echo "      \"auto_linked\": $auto_linked_json,"
    echo "      \"blocks\": $blocks_json,"
    echo "      \"keywords\": $kw_json,"
    echo "      \"changelog\": $ch_json,"
    echo "      \"tokens\": $ntokens,"
    echo "      \"rel\": \"$nrel\""
    echo -n "    }"
  done

  echo ""
  echo "  ]"
  echo "}"
} > "$JSON_OUTPUT"

echo "MEMORY_MAP.md regenerated: ${#ALL_NODES[@]} nodes, ${#TAG_MAP[@]} tags, ${#KEYWORD_MAP[@]} keywords, ${#CHANGELOG_INDEX[@]} change-log months, $warnings warnings."
echo "MEMORY_MAP.json regenerated: ${#ALL_NODES[@]} nodes."

# ─── SQLite cache sync ──────────────────────────────────────────────────
if [ "$USE_DB" = true ] && [ -n "$DB_PATH" ] && command -v python3 >/dev/null 2>&1; then
  DB_INIT_SCRIPT="${SCRIPT_DIR}/db_init.py"
  DB_INDEX_SCRIPT="${SCRIPT_DIR}/db_index.py"

  if [ -f "$DB_INDEX_SCRIPT" ]; then
    # Ensure DB exists
    if [ ! -f "$DB_PATH" ]; then
      python3 "$DB_INIT_SCRIPT" --db "$DB_PATH" 2>&1 || true
    fi

    # Incremental or full sync
    if [ "$FULL_REBUILD" = true ]; then
      python3 "$DB_INDEX_SCRIPT" --project "$PROJECT_ROOT" --db "$DB_PATH" --full 2>&1
    elif [ -n "$CHANGED_FILE" ]; then
      node_id=$(basename "$CHANGED_FILE" .md)
      python3 "$DB_INDEX_SCRIPT" --project "$PROJECT_ROOT" --db "$DB_PATH" --changed "$node_id" 2>&1
    else
      python3 "$DB_INDEX_SCRIPT" --project "$PROJECT_ROOT" --db "$DB_PATH" 2>&1
    fi
  fi
fi

# ─── Stats output (--stats mode) ───────────────────────────────────────
if [ "$STATS_MODE" = true ]; then
  END_TIME=$(date +%s)
  ELAPSED=$((END_TIME - START_TIME))

  # File sizes (cross-platform stat)
  map_md_size=$(stat -c %s "$OUTPUT" 2>/dev/null || stat -f %z "$OUTPUT" 2>/dev/null || echo 0)
  map_json_size=$(stat -c %s "$JSON_OUTPUT" 2>/dev/null || stat -f %z "$JSON_OUTPUT" 2>/dev/null || echo 0)

  # Cache hit rate
  total_nodes=${#ALL_NODES[@]}
  if [ "$total_nodes" -gt 0 ]; then
    cache_hits=$((total_nodes - parsed_count))
    cache_hit_rate=$((cache_hits * 100 / total_nodes))
  else
    cache_hits=0
    cache_hit_rate=0
  fi

  # Total tokens across all nodes
  total_tokens=0
  for entry in "${ALL_NODES[@]}"; do
    tok=$(echo "$entry" | cut -d'|' -f10)
    total_tokens=$((total_tokens + ${tok:-0}))
  done

  cat << STATS
{
  "elapsed_seconds": $ELAPSED,
  "nodes": $total_nodes,
  "tags": ${#TAG_MAP[@]},
  "keywords": ${#KEYWORD_MAP[@]},
  "changelog_months": ${#CHANGELOG_INDEX[@]},
  "warnings": $warnings,
  "cache_hit_rate_percent": $cache_hit_rate,
  "re_parsed": $parsed_count,
  "cached": $cache_hits,
  "total_tokens": $total_tokens,
  "map_md_bytes": $map_md_size,
  "map_json_bytes": $map_json_size
}
STATS
fi

