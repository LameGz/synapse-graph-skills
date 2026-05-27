#!/usr/bin/env bash
# suggest_edges.sh — auto-detect potential dependency edges from node content
# Scans Connection Points and cross-references between nodes.
#
# Modes:
#   default (no args)     — Suggest NEW edges from content analysis
#   --check-drift         — Validate EXISTING edges for staleness
#   --auto                — Auto-Link: read co-occurrence db, score by
#                           confidence (co-occurrence + reference + semantic)
#
# Agent's job shifts from "inventing edges" to "confirming/rejecting suggestions".
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "Error: requires bash 4+ (current: $BASH_VERSION)" >&2
  echo "macOS: brew install bash; ensure /opt/homebrew/bin or /usr/local/bin in PATH" >&2
  exit 1
fi

if [ -x /usr/bin/find ]; then
  find() { /usr/bin/find "$@"; }
fi
if [ -x /usr/bin/sort ]; then
  sort() { /usr/bin/sort "$@"; }
fi
if [ -x /usr/bin/head ]; then
  head() { /usr/bin/head "$@"; }
fi
if [ -x /usr/bin/xargs ]; then
  xargs() { /usr/bin/xargs "$@"; }
fi

ORIGINAL_ARGS=("$@")
MODE="suggest"
PROJECT_ROOT_OVERRIDE=""
PROPOSAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-drift)
      MODE="drift"
      shift
      ;;
    --auto)
      MODE="auto"
      shift
      ;;
    --project)
      PROJECT_ROOT_OVERRIDE="$2"
      shift 2
      ;;
    --proposal)
      PROPOSAL="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "$PROJECT_ROOT_OVERRIDE" ]; then
  PROJECT_ROOT="$(cd "$PROJECT_ROOT_OVERRIDE" && pwd)"
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"
fi
META_DIR="${PROJECT_ROOT}/meta"

PY_ENGINE="${SCRIPT_DIR}/suggest_edges.py"
pick_python() {
  local candidate
  for candidate in "${PYTHON_BIN:-}" python3 python; do
    [ -n "$candidate" ] || continue
    command -v "$candidate" >/dev/null 2>&1 || continue
    "$candidate" -c "import json" >/dev/null 2>&1 || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

PY_BIN="$(pick_python || true)"

if [ -z "${SYNAPSE_LEGACY_SUGGEST:-}" ] \
  && [ "$MODE" = "suggest" ] \
  && [ -n "$PY_BIN" ] \
  && [ -f "$PY_ENGINE" ]; then
  exec "$PY_BIN" "$PY_ENGINE" "${ORIGINAL_ARGS[@]}"
fi

if [ ! -d "$META_DIR" ]; then
  echo "No meta/ directory found."
  exit 0
fi

# ─── Extract connection point identifiers from a node ──────────────────
# Returns: one identifier per line, format: "type|value"
# Each grep is suffixed with `|| true` because no-match returns 1 and would
# trip `set -e` in the caller (the function's exit code is the last command's).
extract_connection_points() {
  local file="$1"
  local body
  body=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$file" 2>/dev/null || true)

  # API endpoints
  echo "$body" | grep -oE '(GET|POST|PUT|DELETE|PATCH)[[:space:]]+(/[a-zA-Z0-9_/{}:-]+)' 2>/dev/null | sed 's/^/api|/' || true

  # Table names
  echo "$body" | sed -n 's/.*\*\*[Tt]able\*\*:[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p' | sed 's/^/table|/' || true

  # Shared state references
  echo "$body" | grep -oi 'shared state via [a-zA-Z_][a-zA-Z0-9_]*' 2>/dev/null | sed 's/.*via //I' | sed 's/^/state|/' || true

  return 0
}

# ─── Extract a YAML list (inline or multi-line) into space-separated items ─
extract_list_items() {
  local key="$1" fm="$2"
  # Inline: key: [a, b]
  local inline
  inline=$(echo "$fm" | sed -n "/^${key}:[[:space:]]*\[/s/^${key}:[[:space:]]*//p" | tr -d '[]"')
  if [ -n "$(echo "$inline" | xargs)" ]; then
    echo "$inline" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d'
    return
  fi
  # Multi-line: key:\n  - a\n  - b
  echo "$fm" | awk -v k="$key" '
    $0 ~ ("^" k ":[[:space:]]*$") { in_list=1; next }
    in_list && /^[[:space:]]*-[[:space:]]+/ {
      item = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      gsub(/["'\''\],]/, "", item)
      sub(/[[:space:]]+$/, "", item)
      if (item != "") print item
      next
    }
    in_list && /^[[:space:]]*$/ { next }
    in_list && /^[a-zA-Z]/ { in_list=0 }
  '
}

# ─── Collect identifiers and tags for every node ───────────────────────
# Populates global arrays NODE_IDS and NODE_TAGS, used by both suggest and drift modes.
collect_node_metadata() {
  declare -gA NODE_IDS      # rel_path -> newline-separated "type|value"
  declare -gA NODE_TAGS     # rel_path -> tags

  local file rel ids fm tags
  while IFS= read -r -d '' file; do
    rel="${file#$PROJECT_ROOT/}"
    ids=$(extract_connection_points "$file")
    if [ -n "$ids" ]; then
      NODE_IDS["$rel"]="$ids"
    fi

    fm=$(awk '/^---$/ {c++; next} c==1' "$file" 2>/dev/null || true)
    tags=$(extract_list_items "tags" "$fm" | tr '\n' ' ' | xargs)
    NODE_TAGS["$rel"]="$tags"
  done < <(find "$META_DIR" -maxdepth 2 -name '*.md' ! -name 'MEMORY_MAP.md' -print0 2>/dev/null || true)
}

# ─── Auto-Link helpers (shared with session-end.sh logic) ──────────────
CO_DB="${PROJECT_ROOT}/.claude/.synapse_cache/cooccurrence.db"

normalize_pair() {
  local a="$1" b="$2"
  if [[ "$a" < "$b" ]]; then echo "$a|||$b"; else echo "$b|||$a"; fi
}

apply_decay() {
  local count="$1" last_date="$2"
  local last_epoch days_diff periods
  last_epoch=$(date -d "$last_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$last_date" +%s 2>/dev/null || echo "")
  [ -z "$last_epoch" ] && echo "$count" && return
  days_diff=$(( ( $(date +%s) - last_epoch) / 86400 ))
  periods=$(( days_diff / 7 ))
  if [ "$periods" -gt 0 ]; then
    awk -v c="$count" -v p="$periods" 'BEGIN {for(i=0;i<p;i++) c=c*0.5; print int(c)}'
  else
    echo "$count"
  fi
}

extract_node_keywords() {
  local file="$1"
  local body
  body=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$file" 2>/dev/null || true)
  {
    echo "$body" | grep -oE '(GET|POST|PUT|DELETE|PATCH)[[:space:]]+(/[a-zA-Z0-9_/{}:-]+)' | sed -E 's/^[A-Z]+[[:space:]]+//'
    echo "$body" | grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\(\)'
    echo "$body" | sed -n 's/.*\*\*[Tt]able\*\*:[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p'
    echo "$body" | grep -oE '\b[A-Z][A-Z0-9_]{2,}\b' | grep -vE '^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)$'
  } | sort -u | tr '\n' ' ' | sed 's/^ *//;s/ *$//' || true
}

semantic_score() {
  local kw1="$1" kw2="$2"
  [ -z "$kw1" ] || [ -z "$kw2" ] && echo "0" && return
  local shared
  shared=$(comm -12 <(echo "$kw1" | tr ' ' '\n' | grep . | sort) <(echo "$kw2" | tr ' ' '\n' | grep . | sort) | wc -l)
  echo "$(( shared * 5 ))"
}

# ─── Auto-Link mode: read co-occurrence db, compute confidence ─────────
auto_suggest() {
  if [ ! -f "$CO_DB" ]; then
    echo "No co-occurrence data found. Run a few sessions first to build signals."
    echo "Db expected at: $CO_DB"
    exit 0
  fi

  echo "🤖 Synapse Auto-Link Suggestions"
  echo "   (Three-layer confidence: co-occurrence + reference + semantic)"
  echo ""

  # Load and decay co-occurrence db
  declare -A CO_COUNT
  declare -A CO_LAST_UPDATED

  while IFS='|' read -r na nb count last_up; do
    [ -z "$na" ] && continue
    [ "$count" = "0" ] && continue
    decayed=$(apply_decay "$count" "$last_up")
    if [ "$decayed" -gt 0 ]; then
      key="$na|||$nb"
      CO_COUNT["$key"]="$decayed"
      CO_LAST_UPDATED["$key"]="$last_up"
    fi
  done < "$CO_DB"

  if [ ${#CO_COUNT[@]} -eq 0 ]; then
    echo "No co-occurrence pairs after decay."
    exit 0
  fi

  # Compute confidence for all pairs
  results=""

  for key in "${!CO_COUNT[@]}"; do
    count="${CO_COUNT[$key]}"
    [ "$count" -lt 1 ] && continue

    na="${key%%|||*}"
    nb="${key##*|||}"

    id_a=$(awk '/^---$/{c++;next} c==1 && /^id:/{print $2; exit}' "${PROJECT_ROOT}/${na}" 2>/dev/null || true)
    id_b=$(awk '/^---$/{c++;next} c==1 && /^id:/{print $2; exit}' "${PROJECT_ROOT}/${nb}" 2>/dev/null || true)
    [ -z "$id_a" ] || [ -z "$id_b" ] && continue

    # Check if already linked
    fm_a=$(awk '/^---$/{c++;next} c==1' "${PROJECT_ROOT}/${na}" 2>/dev/null || true)
    fm_b=$(awk '/^---$/{c++;next} c==1' "${PROJECT_ROOT}/${nb}" 2>/dev/null || true)

    deps_a=$(echo "$fm_a" | sed -n 's/^depends_on:[[:space:]]*//p' | tr -d '[]"' | tr ',' '\n' | xargs | tr '\n' ' ')
    deps_b=$(echo "$fm_b" | sed -n 's/^depends_on:[[:space:]]*//p' | tr -d '[]"' | tr ',' '\n' | xargs | tr '\n' ' ')
    auto_a=$(echo "$fm_a" | sed -n 's/^auto_linked:[[:space:]]*//p' | tr -d '[]"' | tr ',' '\n' | xargs | tr '\n' ' ')
    auto_b=$(echo "$fm_b" | sed -n 's/^auto_linked:[[:space:]]*//p' | tr -d '[]"' | tr ',' '\n' | xargs | tr '\n' ' ')

    already_linked=0
    if echo " $deps_a $auto_a " | grep -qF " $nb "; then already_linked=1; fi
    if echo " $deps_b $auto_b " | grep -qF " $na "; then already_linked=1; fi
    [ "$already_linked" -eq 1 ] && continue

    co_score=$(( count * 10 ))

    body_a=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "${PROJECT_ROOT}/${na}" 2>/dev/null || true)
    body_b=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "${PROJECT_ROOT}/${nb}" 2>/dev/null || true)

    ref_a=$(echo "$body_a" | grep -ciF "$id_b" 2>/dev/null || echo 0)
    ref_b=$(echo "$body_b" | grep -ciF "$id_a" 2>/dev/null || echo 0)
    ref_score=$(( (ref_a + ref_b) * 30 ))

    kw_a=$(extract_node_keywords "${PROJECT_ROOT}/${na}")
    kw_b=$(extract_node_keywords "${PROJECT_ROOT}/${nb}")
    sem_score=$(semantic_score "$kw_a" "$kw_b")

    total_score=$(( co_score + ref_score + sem_score ))
    confidence="$(( total_score / 10 )).$(( total_score % 10 ))"

    # Only include if >= 3.0 threshold
    [ "$total_score" -lt 30 ] && continue

    results="${results}${confidence}|${total_score}|${id_a}|${id_b}|${na}|${nb}|${count}|${ref_a}|${ref_b}|${sem_score}
"
  done

  if [ -z "$results" ]; then
    echo "No new suggestions above confidence threshold (3.0)."
    echo ""
    echo "Tip: Run more sessions, or manually add edges to build stronger signals."
    exit 0
  fi

  # Sort by total_score descending
  echo "Ranked by confidence (highest first):"
  echo ""

  printf '%s' "$results" | sort -t'|' -k2,2rn | while IFS='|' read -r conf total id_a id_b na nb count ref_a ref_b sem; do
    [ -z "$conf" ] && continue
    echo "💡 $id_b → $id_a"
    echo "   Confidence: ${conf}/10"
    echo "   Evidence:"
    echo "     • Co-occurrence: ${count} session(s) together"
    echo "     • Reference: ${id_a} mentioned ${ref_b} time(s) in ${id_b}, ${id_b} mentioned ${ref_a} time(s) in ${id_a}"
    echo "     • Semantic: ${sem} shared keyword(s)"
    echo ""
    echo "   Action:"
    if [ "$total" -ge 50 ]; then
      echo "     [AUTO] Confidence >= 5.0 — add to auto_linked:"
      echo "       auto_linked: [${na}]"
      echo "       # or in ${na}: auto_linked: [${nb}]"
    else
      echo "     [SUGGEST] Confidence 3.0-5.0 — review manually:"
      echo "       If valid: add to depends_on or auto_linked"
      echo "       If invalid: ignore (will decay away if not reinforced)"
    fi
    echo ""
  done

  echo "────────────────────────────────────────────────────────────"
  total_pairs=$(printf '%s' "$results" | grep -c '^')
  auto_count=$(printf '%s' "$results" | awk -F'|' '$2 >= 50' | wc -l)
  suggest_count=$(( total_pairs - auto_count ))
  echo "Total: ${total_pairs} candidate pair(s)"
  echo "  Auto-link eligible (>= 5.0): ${auto_count}"
  echo "  Suggested (3.0-5.0): ${suggest_count}"
}

# ─── Suggest mode: propose new edges from content cross-references ─────
suggest_edges() {
  echo "💡 Synapse Edge Suggestions"
  echo "   (Agent: review each suggestion, add confirmed ones to depends_on)"
  echo ""

  local suggestions=0
  local rel_a rel_b ids_a type_a value_a fm_b deps_b id_a id_b tags_b
  local suggestion_key
  declare -A SEEN_SUGGESTIONS

  for rel_a in "${!NODE_IDS[@]}"; do
    ids_a="${NODE_IDS[$rel_a]}"

    while IFS='|' read -r type_a value_a; do
      [ -z "$type_a" ] && continue
      [ -z "$value_a" ] && continue

      for rel_b in "${!NODE_IDS[@]}"; do
        [ "$rel_a" = "$rel_b" ] && continue

        if echo "${NODE_IDS[$rel_b]}" | grep -qF "$value_a"; then
          fm_b=$(awk '/^---$/ {c++; next} c==1' "${PROJECT_ROOT}/${rel_b}" 2>/dev/null || true)
          deps_b=$(echo "$fm_b" | sed -n 's/^depends_on:[[:space:]]*//p' | tr -d '[]"' | tr ',' '\n' | xargs)

          if ! echo "$deps_b" | grep -qF "$rel_a"; then
            id_a=$(basename "$rel_a" .md)
            id_b=$(basename "$rel_b" .md)
            tags_b="${NODE_TAGS[$rel_b]:-}"
            suggestion_key="${id_b}|${id_a}"
            [ "${SEEN_SUGGESTIONS[$suggestion_key]:-}" = "1" ] && continue
            SEEN_SUGGESTIONS["$suggestion_key"]=1

            echo "💡 Suggested edge: $id_b depends_on $id_a"
            echo "   Reason: $id_b's Connection Points reference $value_a ($type_a)"
            [ -n "$tags_b" ] && echo "   Tags: $tags_b"
            echo ""
            suggestions=$((suggestions + 1))
          fi
        fi
      done
    done <<< "$ids_a"
  done

  echo ""
  echo "── Tag-based cross-references (weaker signal, review carefully) ──"
  echo ""

  local tags_a tag
  for rel_a in "${!NODE_TAGS[@]}"; do
    tags_a="${NODE_TAGS[$rel_a]}"
    [ -z "$tags_a" ] && continue

    IFS=' ' read -ra TAGS_A <<< "$tags_a"
    for tag in "${TAGS_A[@]}"; do
      tag=$(echo "$tag" | xargs)
      [ -z "$tag" ] && continue
      [ ${#tag} -lt 4 ] && continue  # skip short tags (too generic)

      for rel_b in "${!NODE_TAGS[@]}"; do
        [ "$rel_a" = "$rel_b" ] && continue

        if echo "${NODE_TAGS[$rel_b]}" | grep -qiw "$tag"; then
          fm_b=$(awk '/^---$/ {c++; next} c==1' "${PROJECT_ROOT}/${rel_b}" 2>/dev/null || true)
          deps_b=$(echo "$fm_b" | sed -n 's/^depends_on:[[:space:]]*//p' | tr -d '[]"' | tr ',' '\n' | xargs)

          if ! echo "$deps_b" | grep -qF "$rel_a"; then
            id_a=$(basename "$rel_a" .md)
            id_b=$(basename "$rel_b" .md)
            suggestion_key="${id_b}|${id_a}"
            [ "${SEEN_SUGGESTIONS[$suggestion_key]:-}" = "1" ] && continue
            SEEN_SUGGESTIONS["$suggestion_key"]=1

            echo "💡 Suggested edge: $id_b depends_on $id_a"
            echo "   Reason: shared tag '$tag' (weak signal — confirm manually)"
            echo ""
            suggestions=$((suggestions + 1))
          fi
        fi
      done
    done
  done

  echo "────────────────────────────────────────────────────────────"
  echo "Total suggestions: $suggestions"
}

# ─── Drift mode: validate existing edges for staleness ─────────────────
check_drift() {
  echo "🔄 Synapse Edge Drift Check"
  echo "   Validating existing depends_on edges against current node content."
  echo "   (An edge is 'stale' if the source node no longer references"
  echo "    any Connection Point identifier from the target node.)"
  echo ""

  local drift_count=0
  local checked=0
  local node_file rel fm deps src_body src_id dep target_path target_ids
  local still_referenced type value

  while IFS= read -r -d '' node_file; do
    [ ! -f "$node_file" ] && continue
    rel="${node_file#$PROJECT_ROOT/}"

    [[ "$rel" == *"MEMORY_MAP.md"* ]] && continue
    [[ "$rel" == *"archive"* ]] && continue

    fm=$(awk '/^---$/ {c++; next} c==1' "$node_file" 2>/dev/null || true)
    deps=$(echo "$fm" | sed -n 's/^depends_on:[[:space:]]*//p' | tr -d '[]"' | tr ',' '\n' | xargs)

    [ -z "$deps" ] && continue

    src_body=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$node_file" 2>/dev/null || true)
    src_id=$(echo "$fm" | sed -n 's/^id:[[:space:]]*//p' | tr -d '"' | xargs)

    IFS=' ' read -ra DEP_ARR <<< "$deps"
    for dep in "${DEP_ARR[@]}"; do
      [ -z "$dep" ] && continue
      checked=$((checked + 1))

      target_path="${PROJECT_ROOT}/${dep}"
      if [ ! -f "$target_path" ]; then
        echo "⚠️  DEAD LINK: $src_id → $dep (file not found)"
        drift_count=$((drift_count + 1))
        continue
      fi

      target_ids=$(extract_connection_points "$target_path")

      if [ -z "$target_ids" ]; then
        continue
      fi

      still_referenced=0
      while IFS='|' read -r type value; do
        [ -z "$value" ] && continue
        if echo "$src_body" | grep -qF "$value"; then
          still_referenced=1
          break
        fi
      done <<< "$target_ids"

      if [ "$still_referenced" -eq 0 ]; then
        echo "🚨 STALE EDGE: $src_id depends_on $dep"
        echo "   Reason: Source node body no longer references any identifier"
        echo "   from target's Connection Points."
        echo "   Target identifiers:"
        while IFS='|' read -r type value; do
          [ -z "$value" ] && continue
          echo "     - $value ($type)"
        done <<< "$target_ids"
        echo "   Recommendation:"
        echo "     1. Verify if the dependency still exists (check imports, API calls)"
        echo "     2. If still valid: update Connection Points in source node"
        echo "     3. If no longer valid: remove from depends_on and rebuild MAP"
        echo ""
        drift_count=$((drift_count + 1))
      fi
    done
  done < <(find "$META_DIR" -maxdepth 2 -name '*.md' ! -name 'MEMORY_MAP.md' -print0 2>/dev/null || true)

  echo "────────────────────────────────────────────────────────────"
  echo "Checked $checked edges, found $drift_count stale/dead edge(s)."
  if [ "$drift_count" -eq 0 ]; then
    echo "✅ All declared edges still reference their targets."
  else
    echo "⚠️  Review each stale edge. Stale edges break BFS traversal —"
    echo "   downstream context silently disappears when edges are wrong."
  fi
}

# ─── Main dispatch ────────────────────────────────────────────────────
collect_node_metadata

if [ "$MODE" = "drift" ]; then
  check_drift
elif [ "$MODE" = "auto" ]; then
  auto_suggest
else
  suggest_edges
fi
