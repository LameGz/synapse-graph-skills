#!/usr/bin/env bash
# SessionEnd hook: rebuilds MEMORY_MAP, validates topology, outputs change summary.
# Runs automatically at session end — Agent does NOT need to remember.
set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$PWD}"
META_DIR="${PROJECT_ROOT}/meta"

# ─── Step 1: Rebuild index + validate topology ────────────────────────
echo "---"
echo "🔍 Synapse Session End — Running memory integrity checks..."

MAP_SCRIPT="${PROJECT_ROOT}/scripts/generate_memory_map.sh"
WEEKLY_FLAG="${PROJECT_ROOT}/.claude/.synapse_cache/.weekly_full_check"
FULL_CHECK_INTERVAL_DAYS=7

need_full=false

if [ -f "$WEEKLY_FLAG" ]; then
  last_run=$(cat "$WEEKLY_FLAG" 2>/dev/null || echo "0")
  now=$(date +%s)
  days_since=$(( (now - last_run) / 86400 ))
  if [ "$days_since" -ge "$FULL_CHECK_INTERVAL_DAYS" ]; then
    need_full=true
  fi
else
  need_full=true  # First run — do full check
fi

if [ -f "$MAP_SCRIPT" ]; then
  if $need_full; then
    echo "Running full MAP rebuild (weekly health check)..."
    bash "$MAP_SCRIPT" --full 2>&1
    date +%s > "$WEEKLY_FLAG"
  else
    # Incremental: only re-index meta/ files changed in this session
    if git rev-parse --git-dir >/dev/null 2>&1; then
      changed_files=$(git diff --name-only HEAD -- meta/ 2>/dev/null || true)
      if [ -n "$changed_files" ]; then
        echo "Running incremental MAP update for changed nodes..."
        while IFS= read -r f; do
          [ -z "$f" ] && continue
          [[ "$f" == *"MEMORY_MAP.md"* ]] && continue
          # Extract just the filename from meta/ path
          node_name=$(basename "$f")
          bash "$MAP_SCRIPT" --project "$PROJECT_ROOT" --changed "$node_name" 2>&1
        done <<< "$changed_files"
      else
        echo "No meta/ changes detected. Skipping MAP rebuild."
      fi
    else
      bash "$MAP_SCRIPT" 2>&1  # Not a git repo — standard rebuild
    fi
  fi
else
  echo "⚠ generate_memory_map.sh not found"
fi

# ─── Step 2: Scan for nodes modified in this session ──────────────────
# Compare git diff to find changed meta/ files
if git rev-parse --git-dir >/dev/null 2>&1; then
  modified=$(git diff --name-only HEAD -- meta/ 2>/dev/null || true)
  untracked=$(git ls-files --others --exclude-standard -- meta/ 2>/dev/null || true)

  if [ -n "$modified" ] || [ -n "$untracked" ]; then
    echo ""
    echo "📝 Memory Changes"
    echo "─────────────────"
    if [ -n "$modified" ]; then
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        echo "Modified: $f"
      done <<< "$modified"
    fi
    if [ -n "$untracked" ]; then
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        echo "New: $f"
      done <<< "$untracked"
    fi
    echo "─────────────────"
    echo "Changes committed to memory system. Next session will load automatically."
  fi
fi

# ─── Step 2.5: Auto-Link Engine (v0.4) ──────────────────────────────────
# Three-layer confidence scoring:
#   Layer 1 (Co-occurrence): +1/session for nodes touched together,
#                            7-day half-life decay
#   Layer 2 (Reference):     +3 if node body mentions other node's id
#   Layer 3 (Semantic):      +0.5 per shared keyword
# Thresholds:
#   >= 5.0: auto-link candidate
#   3.0-5.0: suggestion
#   < 3.0: silent (accumulate in db)

CO_DB="${PROJECT_ROOT}/.claude/.synapse_cache/cooccurrence.db"
mkdir -p "$(dirname "$CO_DB")"

today=$(date +%Y-%m-%d)
today_epoch=$(date +%s)

# Helper: normalize pair key (sorted alphabetically)
normalize_pair() {
  local a="$1" b="$2"
  if [[ "$a" < "$b" ]]; then echo "$a|||$b"; else echo "$b|||$a"; fi
}

# Helper: apply 7-day half-life decay
apply_decay() {
  local count="$1" last_date="$2"
  local last_epoch days_diff periods
  last_epoch=$(date -d "$last_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$last_date" +%s 2>/dev/null || echo "")
  [ -z "$last_epoch" ] && echo "$count" && return
  days_diff=$(( (today_epoch - last_epoch) / 86400 ))
  periods=$(( days_diff / 7 ))
  if [ "$periods" -gt 0 ]; then
    awk -v c="$count" -v p="$periods" 'BEGIN {for(i=0;i<p;i++) c=c*0.5; print int(c)}'
  else
    echo "$count"
  fi
}

# Helper: extract keywords from node body
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

# Helper: semantic score (*10 integer, actual = /10)
semantic_score() {
  local kw1="$1" kw2="$2"
  [ -z "$kw1" ] || [ -z "$kw2" ] && echo "0" && return
  local shared
  shared=$(comm -12 <(echo "$kw1" | tr ' ' '\n' | grep . | sort) <(echo "$kw2" | tr ' ' '\n' | grep . | sort) | wc -l)
  echo "$(( shared * 5 ))"
}

if [ -d "$META_DIR" ]; then

  # Collect node files touched this session
  all_touched=""
  if git rev-parse --git-dir >/dev/null 2>&1; then
    if [ -n "${modified:-}" ] && [ -n "${untracked:-}" ]; then
      all_touched=$(printf '%s\n%s' "$modified" "$untracked")
    elif [ -n "${modified:-}" ]; then
      all_touched="$modified"
    elif [ -n "${untracked:-}" ]; then
      all_touched="$untracked"
    fi
  fi

  # Filter to valid meta/*.md node files and deduplicate
  declare -A TOUCHED_SET
  if [ -n "$all_touched" ]; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      [[ "$f" == meta/*.md ]] || continue
      [[ "$f" == *"MEMORY_MAP.md"* ]] && continue
      [ -f "${PROJECT_ROOT}/${f}" ] || continue
      TOUCHED_SET["$f"]=1
    done <<< "$all_touched"
  fi

  # ─── Load & decay existing co-occurrence db ──────────────────────────
  declare -A CO_COUNT
  declare -A CO_LAST_UPDATED

  if [ -f "$CO_DB" ]; then
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
  fi

  # ─── Update co-occurrence counts for this session ────────────────────
  touched_array=("${!TOUCHED_SET[@]}")
  touched_len=${#touched_array[@]}

  if [ "$touched_len" -gt 1 ]; then
    for ((i=0; i<touched_len; i++)); do
      f1="${touched_array[$i]}"
      for ((j=i+1; j<touched_len; j++)); do
        f2="${touched_array[$j]}"
        key=$(normalize_pair "$f1" "$f2")
        CO_COUNT["$key"]=$(( ${CO_COUNT[$key]:-0} + 1 ))
        CO_LAST_UPDATED["$key"]="$today"
      done
    done
  fi

  # ─── Write updated co-occurrence db ──────────────────────────────────
  {
    for key in "${!CO_COUNT[@]}"; do
      count="${CO_COUNT[$key]}"
      [ "$count" = "0" ] && continue
      last_up="${CO_LAST_UPDATED[$key]:-$today}"
      na="${key%%|||*}"
      nb="${key##*|||}"
      echo "$na|$nb|$count|$last_up"
    done
  } | sort > "$CO_DB"

  # ─── Compute confidence & generate suggestions ───────────────────────
  if [ ${#CO_COUNT[@]} -gt 0 ]; then
    auto_links=""
    suggestions=""

    for key in "${!CO_COUNT[@]}"; do
      count="${CO_COUNT[$key]}"
      [ "$count" -lt 1 ] && continue

      na="${key%%|||*}"
      nb="${key##*|||}"

      id_a=$(awk '/^---$/{c++;next} c==1 && /^id:/{print $2; exit}' "${PROJECT_ROOT}/${na}" 2>/dev/null || true)
      id_b=$(awk '/^---$/{c++;next} c==1 && /^id:/{print $2; exit}' "${PROJECT_ROOT}/${nb}" 2>/dev/null || true)
      [ -z "$id_a" ] || [ -z "$id_b" ] && continue

      # Check if already linked (depends_on or auto_linked, either direction)
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

      # Layer 1: Co-occurrence score (*10)
      co_score=$(( count * 10 ))

      # Layer 2: Reference signal
      body_a=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "${PROJECT_ROOT}/${na}" 2>/dev/null || true)
      body_b=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "${PROJECT_ROOT}/${nb}" 2>/dev/null || true)

      ref_a=$(echo "$body_a" | grep -ciF "$id_b" 2>/dev/null || echo 0)
      ref_b=$(echo "$body_b" | grep -ciF "$id_a" 2>/dev/null || echo 0)
      ref_score=$(( (ref_a + ref_b) * 30 ))

      # Layer 3: Semantic signal
      kw_a=$(extract_node_keywords "${PROJECT_ROOT}/${na}")
      kw_b=$(extract_node_keywords "${PROJECT_ROOT}/${nb}")
      sem_score=$(semantic_score "$kw_a" "$kw_b")

      # Total confidence
      total_score=$(( co_score + ref_score + sem_score ))
      confidence="$(( total_score / 10 )).$(( total_score % 10 ))"

      if [ "$total_score" -ge 50 ]; then
        auto_links="${auto_links}$id_a ($na) ↔ $id_b ($nb)|$confidence|$count|$ref_a|$ref_b|$sem_score|$na|$nb
"
      elif [ "$total_score" -ge 30 ]; then
        suggestions="${suggestions}$id_a ($na) ↔ $id_b ($nb)|$confidence|$count|$ref_a|$ref_b|$sem_score|$na|$nb
"
      fi
    done

    if [ -n "$auto_links" ]; then
      echo ""
      echo "🔗 Auto-Link Candidates (confidence >= 5.0)"
      echo "────────────────────────────────────────────"
      printf '%s' "$auto_links" | while IFS='|' read -r pair conf co ref_a ref_b sem na nb; do
        [ -z "$pair" ] && continue
        echo "  $pair"
        echo "    Confidence: $conf/10"
        echo "    Signals: co-occurrence=$co, reference=$((ref_a+ref_b)), semantic=$((sem/10))"
        echo "    → Add to frontmatter: auto_linked: [$nb]  # or [$na] in the other direction"
      done
      echo "────────────────────────────────────────────"
    fi

    if [ -n "$suggestions" ]; then
      echo ""
      echo "💡 Suggested Dependencies (confidence 3.0-5.0)"
      echo "──────────────────────────────────────────────"
      printf '%s' "$suggestions" | while IFS='|' read -r pair conf co ref_a ref_b sem na nb; do
        [ -z "$pair" ] && continue
        echo "  $pair"
        echo "    Confidence: $conf/10"
        echo "    Signals: co-occurrence=$co, reference=$((ref_a+ref_b)), semantic=$((sem/10))"
        echo "    → Review with: bash scripts/suggest_edges.sh --auto"
      done
      echo "──────────────────────────────────────────────"
    fi
  fi
fi

# ─── Step 3: Soft-check for source→memory drift ───────────────────────
# Flag: if source files were modified but corresponding meta/ nodes weren't updated
# (Only runs if git is available and there are source changes)
if git rev-parse --git-dir >/dev/null 2>&1 && [ -d "$META_DIR" ]; then
  src_changed=$(git diff --name-only HEAD -- '*.ts' '*.tsx' '*.js' '*.py' '*.go' '*.rs' 2>/dev/null | head -20 || true)
  meta_changed=$(git diff --name-only HEAD -- meta/ 2>/dev/null || true)

  if [ -n "$src_changed" ] && [ -z "$meta_changed" ]; then
    echo ""
    echo "⚠ Source files modified but no meta/ nodes updated."
    echo "  If these changes affect cross-module contracts, update the relevant node files."
    echo "  Changed source files:"
    echo "$src_changed" | while IFS= read -r f; do
      [ -z "$f" ] && continue
      echo "    - $f"
    done
  fi
fi

# ─── Step 4: Validate reference anchors in Connection Points ────────────
# Extract <!-- @ref: path:line --> annotations and verify they still match
if [ -d "$META_DIR" ]; then
  echo ""
  echo "🔍 Checking reference anchors..."

  anchor_issues=0

  while IFS= read -r -d '' node_file; do
    [ ! -f "$node_file" ] && continue
    rel="${node_file#$PROJECT_ROOT/}"
    [[ "$rel" == *"MEMORY_MAP.md"* ]] && continue
    [[ "$rel" == *"archive"* ]] && continue

    # Extract lines with @ref anchors
    anchors=$(grep -n '<!-- @ref:' "$node_file" 2>/dev/null || true)
    [ -z "$anchors" ] && continue

    while IFS= read -r anchor_line; do
      [ -z "$anchor_line" ] && continue

      # Parse: "123:- **Endpoint**: POST /api/v1/auth/refresh  <!-- @ref: src/auth/routes.ts:45 -->"
      line_num=$(echo "$anchor_line" | cut -d: -f1)
      ref_info=$(echo "$anchor_line" | sed -n 's/.*<!-- @ref:[[:space:]]*\([^[:space:]]*\)[[:space:]]*-->.*/\1/p')
      [ -z "$ref_info" ] && continue

      # ref_info format: path:line
      ref_path=$(echo "$ref_info" | cut -d: -f1)
      ref_line=$(echo "$ref_info" | cut -d: -f2)

      # Resolve path relative to project root
      if [ "${ref_path:0:1}" != "/" ] && [ "${ref_path:0:1}" != "." ]; then
        ref_path="${PROJECT_ROOT}/${ref_path}"
      fi

      # Check file exists
      if [ ! -f "$ref_path" ]; then
        echo "  ❌ $rel:$line_num → $ref_info (file not found)"
        anchor_issues=$((anchor_issues + 1))
        continue
      fi

      # Check line exists
      total_lines=$(wc -l < "$ref_path" 2>/dev/null || echo 0)
      if [ "$ref_line" -gt "$total_lines" ] 2>/dev/null || [ "$ref_line" -lt 1 ] 2>/dev/null; then
        echo "  ❌ $rel:$line_num → $ref_info (line $ref_line out of range, file has $total_lines lines)"
        anchor_issues=$((anchor_issues + 1))
        continue
      fi

      # Extract the expected value from the node file (the line content before the anchor)
      expected_value=$(sed -n "${line_num}p" "$node_file" | sed 's/[[:space:]]*<!-- @ref:.*-->[[:space:]]*$//' | sed 's/^[^:]*:[[:space:]]*//' | xargs)

      # Extract actual value from source file (the referenced line + context)
      actual_value=$(sed -n "${ref_line}p" "$ref_path" | xargs)

      # Fuzzy match: check if key terms from expected appear in actual
      # Extract key terms: API paths, function names, etc.
      key_terms=$(echo "$expected_value" | grep -oE '(/[a-zA-Z0-9_/{}:-]+|[a-zA-Z_][a-zA-Z0-9_]*\(\)|[A-Z][A-Z0-9_]{2,})' | sort -u | tr '\n' ' ')

      match_found=1
      if [ -n "$key_terms" ]; then
        for term in $key_terms; do
          if ! echo "$actual_value" | grep -qF "$term"; then
            match_found=0
            break
          fi
        done
      fi

      if [ "$match_found" -eq 0 ]; then
        echo "  ⚠️  $rel:$line_num → $ref_info"
        echo "     Expected (node): $expected_value"
        echo "     Actual (source): $actual_value"
        anchor_issues=$((anchor_issues + 1))
      fi

    done <<< "$anchors"
  done < <(find "$META_DIR" -maxdepth 2 -name '*.md' ! -name 'MEMORY_MAP.md' -print0 2>/dev/null || true)

  if [ "$anchor_issues" -eq 0 ]; then
    echo "  ✅ All reference anchors valid."
  else
    echo ""
    echo "  $anchor_issues anchor(s) drifted. Update Connection Points or source."
  fi
fi

# ─── Step 5: Auto-observe & auto-record (V3.4) ──────────────────────
AUTO_OBSERVE_SCRIPT="${PROJECT_ROOT}/scripts/auto_observe.py"
AUTO_PROPOSAL_DIR="${PROJECT_ROOT}/.claude/.synapse_cache/auto-proposals"
AUTO_CONFIRM_THRESHOLD=70

if [ -f "$AUTO_OBSERVE_SCRIPT" ] && command -v python3 >/dev/null 2>&1; then
  mkdir -p "$AUTO_PROPOSAL_DIR"

  today=$(date +%Y-%m-%d)
  proposal_file="${AUTO_PROPOSAL_DIR}/${today}_proposals.json"

  python3 "$AUTO_OBSERVE_SCRIPT" --project "$PROJECT_ROOT" \
    --min-confidence 40 --output "$proposal_file" 2>&1

  if [ -f "$proposal_file" ]; then
    python3 -c "
import json, sys, os

with open('${proposal_file}') as f:
    data = json.load(f)

high = [p for p in data.get('proposals', []) if p['confidence'] >= ${AUTO_CONFIRM_THRESHOLD}]
low = [p for p in data.get('proposals', []) if p['confidence'] < ${AUTO_CONFIRM_THRESHOLD}]

if high:
    with open('${AUTO_PROPOSAL_DIR}/auto_apply.json', 'w') as f:
        json.dump({'proposals': high}, f, indent=2, ensure_ascii=False)

if low:
    with open('${AUTO_PROPOSAL_DIR}/needs_review.json', 'w') as f:
        json.dump({'proposals': low}, f, indent=2, ensure_ascii=False)

print(f'AUTO:{len(high)}/{len(data.get(\"proposals\", []))} proposals above threshold')
" 2>&1

    if [ -f "${AUTO_PROPOSAL_DIR}/auto_apply.json" ]; then
      auto_count=$(python3 -c "import json; print(len(json.load(open('${AUTO_PROPOSAL_DIR}/auto_apply.json'))['proposals']))" 2>/dev/null || echo 0)

      if [ "$auto_count" -gt 0 ]; then
        echo ""
        echo "📝 Auto-Recorded (V3.4):"
        echo "──────────────────────"

        python3 -c "
import json, os, subprocess

proj = '${PROJECT_ROOT}'
with open('${AUTO_PROPOSAL_DIR}/auto_apply.json') as f:
    data = json.load(f)

note_script = os.path.join(proj, 'scripts/synapse_note.sh')
if not os.path.exists(note_script):
    note_script = os.path.join(os.path.dirname('${SCRIPT_DIR}'), 'synapse_note.sh')

applied = 0
for p in data['proposals']:
    node = p.get('target_node', 'unknown')
    content = p.get('content', '')
    change_type = p.get('change_type', 'change_log')
    confidence = p.get('confidence', 0)
    if not content:
        continue
    text = content
    if node and node != 'unknown' and node != '__all_db__' and node != 'all_db_':
        text = f'[{node}] {content}'
    try:
        result = subprocess.run(
            ['bash', note_script, '--project', proj, '--text', text,
             '--edge-mode', 'auto', '--auto-confirm'],
            capture_output=True, text=True, timeout=15
        )
        if result.returncode == 0:
            applied += 1
            mark = chr(0x2713)
            print(f'  {mark} {node}: {content[:80]}')
        else:
            print(f'  X {node}: failed ({result.stderr[:60]})')
    except Exception as e:
        print(f'  X {node}: error ({e})')

print(f'')
print(f'  {applied}/{len(data[\"proposals\"])} proposals auto-applied')
" 2>&1
      fi
    fi

    if [ -f "${AUTO_PROPOSAL_DIR}/needs_review.json" ]; then
      low_count=$(python3 -c "import json; print(len(json.load(open('${AUTO_PROPOSAL_DIR}/needs_review.json'))['proposals']))" 2>/dev/null || echo 0)

      if [ "$low_count" -gt 0 ]; then
        echo ""
        echo "⚠  Needs Review (confidence < ${AUTO_CONFIRM_THRESHOLD}%):"
        echo "─────────────────────────────────────────"

        python3 -c "
import json
with open('${AUTO_PROPOSAL_DIR}/needs_review.json') as f:
    data = json.load(f)
for i, p in enumerate(data['proposals'][:5]):
    print(f'  {i+1}. [{p.get(\"change_type\", \"?\")}] {p.get(\"content\", \"\")[:100]}')
    print(f'     confidence: {p.get(\"confidence\", 0)}% | target: {p.get(\"target_node\", \"?\")}')
    if p.get('evidence'):
        print(f'     evidence: {p[\"evidence\"]}')
n = len(data['proposals'])
if n > 5:
    print(f'  ... and {n - 5} more. See {AUTO_PROPOSAL_DIR}/needs_review.json')
" 2>&1
      fi
    fi
  fi
fi

echo "---"

# ─── Clear read-protocol marker for next session ───────────────────────
MARKER="${PROJECT_ROOT}/.claude/.synapse_cache/.map_read"
rm -f "$MARKER" 2>/dev/null || true

exit 0
