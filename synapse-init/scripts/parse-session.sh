#!/usr/bin/env bash
# parse-session.sh — Analyze a Claude Code session transcript for Synapse BFS protocol compliance.
#
# Usage:
#   bash scripts/parse-session.sh <transcript.jsonl>     # audit single session
#   bash scripts/parse-session.sh --summary              # summarize all sessions
#   bash scripts/parse-session.sh --audit <transcript>   # full BFS compliance audit
#
# The --audit mode is the key upgrade: it compares actual Read paths against
# theoretical legal BFS paths from MEMORY_MAP.json, outputting:
#   - Compliance rate: % of loaded nodes within BFS boundary
#   - Out-of-bounds reads: nodes read that were NOT reachable via bounded BFS
#   - Omission risks: nodes within BFS boundary that were NOT read
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "Error: requires bash 4+ (current: $BASH_VERSION)" >&2
  echo "macOS: brew install bash; ensure /opt/homebrew/bin or /usr/local/bin in PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"
MAP_JSON="${PROJECT_ROOT}/MEMORY_MAP.json"

mode="${1:---summary}"
transcript="${2:-}"

# ─── Parse MEMORY_MAP.json into shell-friendly associative arrays ─────
load_memory_map() {
  if [ ! -f "$MAP_JSON" ]; then
    echo "WARNING: MEMORY_MAP.json not found at $MAP_JSON" >&2
    return 1
  fi

  declare -gA NODE_DEPS
  declare -gA NODE_TAGS
  declare -gA NODE_ID_TO_REL
  declare -ga ALL_RELS

  local raw=""

  # Primary: jq
  if command -v jq >/dev/null 2>&1; then
    raw=$(jq -r '.nodes[]? | "\(.rel)|\(.depends_on | join(","))|\(.tags | join(","))"' "$MAP_JSON" 2>/dev/null || true)
  # Fallback: python3
  elif command -v python3 >/dev/null 2>&1; then
    raw=$(python3 -c "
import json
with open('$MAP_JSON') as f: data = json.load(f)
for n in data.get('nodes', []):
    rel = n.get('rel','')
    deps = ','.join(n.get('depends_on',[]))
    tags = ','.join(n.get('tags',[]))
    print(f'{rel}|{deps}|{tags}')
" 2>/dev/null || true)
  else
    echo "WARNING: neither jq nor python3 available. Cannot perform BFS audit." >&2
    return 1
  fi

  [ -z "$raw" ] && return 1

  while IFS='|' read -r rel deps tags; do
    [ -z "$rel" ] && continue
    NODE_DEPS["$rel"]="$deps"
    NODE_TAGS["$rel"]="$tags"
    NODE_ID_TO_REL["$rel"]="$rel"
    ALL_RELS+=("$rel")
  done <<< "$raw"

  return 0
}

# ─── Compute legal BFS boundary for a set of root nodes ───────────────
# Returns: newline-separated list of rel paths within BFS boundary
compute_bfs_boundary() {
  local roots="$1"
  local boundary=""
  local -A visited

  for root in $roots; do
    [ -z "$root" ] && continue
    boundary="${boundary}${root}
"
    visited["$root"]=1

    # Depth 1: all depends_on (mandatory)
    local deps="${NODE_DEPS[$root]:-}"
    IFS=',' read -ra DEP_ARR <<< "$deps"
    for d in "${DEP_ARR[@]}"; do
      d=$(echo "$d" | xargs)
      [ -z "$d" ] && continue
      # Resolve relative to project root if needed
      if [ "${d:0:5}" != "meta/" ]; then
        d="meta/$d"
      fi
      if [ -z "${visited[$d]:-}" ]; then
        boundary="${boundary}${d}
"
        visited["$d"]=1

        # Depth 2: depends_on of depends_on (conditional in protocol, but we
        # include them as "potential boundary" and flag omissions at this level
        # separately from depth 1)
        local deps2="${NODE_DEPS[$d]:-}"
        IFS=',' read -ra DEP2_ARR <<< "$deps2"
        for d2 in "${DEP2_ARR[@]}"; do
          d2=$(echo "$d2" | xargs)
          [ -z "$d2" ] && continue
          if [ "${d2:0:5}" != "meta/" ]; then
            d2="meta/$d2"
          fi
          if [ -z "${visited[$d2]:-}" ]; then
            boundary="${boundary}${d2}
"
            visited["$d2"]=1
          fi
        done
      fi
    done
  done

  echo "$boundary" | sed '/^$/d' | sort -u
}

# ─── Extract node file reads from transcript ──────────────────────────
# Returns: newline-separated list of rel paths, in chronological order
extract_node_reads() {
  local transcript="$1"

  if [ ! -f "$transcript" ]; then
    echo "File not found: $transcript" >&2
    return 1
  fi

  # Parse JSONL: extract Read tool calls to meta/*.md (excluding MEMORY_MAP.md)
  # Each line is a JSON object. We look for tool_use events with tool_name=Read.
  while IFS= read -r line; do
    [ -z "$line" ] && continue

    # Check if this is a Read tool call
    if echo "$line" | grep -q '"tool_name"[[:space:]]*:[[:space:]]*"Read"'; then
      local file_path
      file_path=$(echo "$line" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
      [ -z "$file_path" ] && continue

      # Only care about meta/*.md, exclude MEMORY_MAP.md and archive
      if echo "$file_path" | grep -qE '^meta/[^/]+\.md$' && \
         ! echo "$file_path" | grep -q 'MEMORY_MAP.md'; then
        echo "$file_path"
      fi
    fi
  done < "$transcript"
}

# ─── Identify likely root nodes from read sequence ────────────────────
# Heuristic: the first 1-3 unique node reads are likely the "target nodes"
# (Layer 2 in the protocol). Agent should read MAP first, then pick roots.
identify_roots() {
  local reads="$1"
  # Take first 3 unique reads as potential roots
  echo "$reads" | awk '!seen[$0]++' | head -3
}

# ─── Full BFS compliance audit for a single transcript ────────────────
audit_transcript() {
  local transcript="$1"

  echo "=== Synapse BFS Protocol Compliance Audit ==="
  echo "Transcript: $(basename "$transcript")"
  echo ""

  # Step 1: Load MEMORY_MAP.json
  if ! load_memory_map; then
    echo "Falling back to basic metrics (no MEMORY_MAP.json or jq missing)."
    echo ""
    parse_one_basic "$transcript"
    return
  fi

  # Step 2: Extract actual node reads
  local actual_reads
  actual_reads=$(extract_node_reads "$transcript")

  if [ -z "$actual_reads" ]; then
    echo "No meta/*.md node reads found in this transcript."
    echo "(Agent may not have used Synapse memory system in this session.)"
    return
  fi

  local read_count
  read_count=$(echo "$actual_reads" | wc -l)

  # Step 3: Identify likely root nodes (Layer 2 targets)
  local roots
  roots=$(identify_roots "$actual_reads")
  local root_count
  root_count=$(echo "$roots" | wc -l)

  echo "Actual node reads: $read_count"
  echo "Likely root nodes (Layer 2 targets): $root_count"
  echo "$roots" | while IFS= read -r r; do
    echo "  - $r"
  done
  echo ""

  # Step 4: Compute legal BFS boundary from roots
  local legal_boundary
  legal_boundary=$(compute_bfs_boundary "$roots")
  local boundary_count
  boundary_count=$(echo "$legal_boundary" | wc -l)

  echo "Legal BFS boundary (roots + depth≤2 deps): $boundary_count nodes"
  echo "$legal_boundary" | while IFS= read -r r; do
    local deps="${NODE_DEPS[$r]:-}"
    local tag="${NODE_TAGS[$r]:-}"
    [ -n "$deps" ] && echo "  - $r (deps: $deps)" || echo "  - $r"
  done
  echo ""

  # Step 5: Compare actual vs legal
  local out_of_bounds=""
  local in_bounds=0
  local -A is_legal

  while IFS= read -r node; do
    [ -z "$node" ] && continue
    is_legal["$node"]=1
  done <<< "$legal_boundary"

  echo "--- Per-Node Analysis ---"
  while IFS= read -r node; do
    [ -z "$node" ] && continue
    if [ -n "${is_legal[$node]:-}" ]; then
      echo "  ✅ $node (within BFS boundary)"
      in_bounds=$((in_bounds + 1))
    else
      echo "  ❌ $node (OUT OF BOUNDS — not reachable via bounded BFS from roots)"
      out_of_bounds="${out_of_bounds}${node}
"
    fi
  done <<< "$actual_reads"
  echo ""

  # Step 6: Check for omissions (depth 1 deps that were NOT read)
  local omissions=""
  local -A was_read
  while IFS= read -r node; do
    [ -z "$node" ] && continue
    was_read["$node"]=1
  done <<< "$actual_reads"

  while IFS= read -r root; do
    [ -z "$root" ] && continue
    local deps="${NODE_DEPS[$root]:-}"
    IFS=',' read -ra DEP_ARR <<< "$deps"
    for d in "${DEP_ARR[@]}"; do
      d=$(echo "$d" | xargs)
      [ -z "$d" ] && continue
      if [ "${d:0:5}" != "meta/" ]; then
        d="meta/$d"
      fi
      if [ -z "${was_read[$d]:-}" ]; then
        omissions="${omissions}${d}
"
      fi
    done
  done <<< "$roots"

  # Step 7: Summary metrics
  echo "=== Compliance Summary ==="

  if [ "$read_count" -gt 0 ]; then
    local compliance_rate=$(( in_bounds * 100 / read_count ))
    echo "Compliance rate: ${compliance_rate}% ($in_bounds / $read_count)"

    if [ "$compliance_rate" -ge 90 ]; then
      echo "✅ Strong protocol compliance"
    elif [ "$compliance_rate" -ge 70 ]; then
      echo "⚠ Partial compliance — some out-of-bounds reads detected"
    else
      echo "❌ Poor compliance — likely flat scan or protocol violation"
    fi
  fi

  local oob_count=0
  if [ -n "$out_of_bounds" ]; then
    oob_count=$(echo "$out_of_bounds" | sed '/^$/d' | wc -l)
    echo ""
    echo "Out-of-bounds reads ($oob_count):"
    echo "$out_of_bounds" | sed '/^$/d' | while IFS= read -r node; do
      echo "  - $node"
    done
    echo ""
    echo "Interpretation: These nodes were loaded but were NOT reachable via"
    echo "bounded BFS (depth≤2, width≤5) from the identified root nodes."
    echo "Possible causes:"
    echo "  - Agent performed flat scan (read all meta/*.md)"
    echo "  - Agent jumped to unrelated nodes without MAP triage"
    echo "  - Root identification heuristic failed (unusual read order)"
  fi

  local omission_count=0
  if [ -n "$omissions" ]; then
    # Deduplicate
    omission_count=$(echo "$omissions" | sed '/^$/d' | sort -u | wc -l)
    echo ""
    echo "Depth-1 omission risks ($omission_count):"
    echo "$omissions" | sed '/^$/d' | sort -u | while IFS= read -r node; do
      echo "  - $node (depends_on of a root node but NOT read)"
    done
    echo ""
    echo "Interpretation: Per BFS protocol, depth-1 dependencies of target"
    echo "nodes should be loaded for cross-module tasks. Missing these may"
    echo "lead to incomplete context."
    echo "Possible causes:"
    echo "  - Agent skipped mandatory depth-1 deps"
    echo "  - Agent hit token budget and skipped non-essential deps"
    echo "  - Task was trivial (no cross-module context needed)"
  fi

  echo ""
  echo "---"
  echo "Audit complete."
}

# ─── Basic metrics (fallback when MEMORY_MAP.json unavailable) ────────
parse_one_basic() {
  local transcript="$1"

  local reads=0
  local read_bytes=0
  local writes=0
  local edits=0
  local map_read=0

  while IFS= read -r line; do
    if echo "$line" | grep -q '"tool_name"[[:space:]]*:[[:space:]]*"Read"'; then
      file_path=$(echo "$line" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
      if echo "$file_path" | grep -q 'meta/.*\.md'; then
        reads=$((reads + 1))
        if echo "$file_path" | grep -q 'MEMORY_MAP.md'; then
          map_read=$((map_read + 1))
        fi
      fi
    fi

    if echo "$line" | grep -q '"tool_name"[[:space:]]*:[[:space:]]*"\(Write\|Edit\)"'; then
      file_path=$(echo "$line" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
      if echo "$file_path" | grep -q 'meta/.*\.md'; then
        if echo "$line" | grep -q '"Write"'; then
          writes=$((writes + 1))
        else
          edits=$((edits + 1))
        fi
      fi
    fi
  done < "$transcript"

  node_reads=$((reads - map_read))

  echo "  MEMORY_MAP reads: $map_read"
  echo "  Node file reads:  $node_reads"
  echo "  Node writes:      $writes"
  echo "  Node edits:       $edits"
  echo "  Total meta/ ops:  $((reads + writes + edits))"

  if [ "$node_reads" -gt 0 ]; then
    echo ""
    if [ "$node_reads" -le 5 ]; then
      echo "  ✅ Synapse protocol appears active (≤5 node files loaded)"
    elif [ "$node_reads" -le 10 ]; then
      echo "  ⚠ Possible partial flat scan ($node_reads files)"
    else
      echo "  ❌ Likely flat scan — $node_reads files loaded (Synapse protocol not followed)"
    fi
  fi
}

# ─── Summary mode: scan all transcripts ───────────────────────────────
summary() {
  local transcripts_dir="${HOME}/.claude/transcripts"

  echo "=== Synapse Session Metrics ==="
  echo "Scanning transcripts..."
  echo ""

  local total=0
  local synapse_active=0
  local audited=0

  for dir in "${HOME}/.claude/transcripts" "${HOME}/.claude/projects/"*"/transcripts"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.jsonl; do
      [ -f "$f" ] || continue
      if grep -q 'meta/.*\.md' "$f" 2>/dev/null; then
        total=$((total + 1))
        local meta_ops=$(grep -c 'meta/.*\.md' "$f" 2>/dev/null || echo 0)
        local map_ops=$(grep -c 'MEMORY_MAP.md' "$f" 2>/dev/null || echo 0)
        local node_ops=$((meta_ops - map_ops))

        echo "  $(basename "$f" .jsonl | cut -c1-20): $node_ops node reads, $map_ops MAP reads"
        if [ "$node_ops" -le 5 ] && [ "$map_ops" -ge 1 ]; then
          synapse_active=$((synapse_active + 1))
        fi
      fi
    done
  done

  echo ""
  echo "Synapse sessions: $synapse_active / $total"
  if [ "$total" -gt 0 ]; then
    compliance=$((synapse_active * 100 / total))
    echo "Protocol compliance rate: ${compliance}%"
    if [ "$compliance" -ge 90 ]; then
      echo "✅ Hook enforcement is working"
    else
      echo "⚠ Compliance < 90% — check hook configuration"
    fi
  fi

  echo ""
  echo "Tip: Run 'bash scripts/parse-session.sh --audit <transcript.jsonl>'"
  echo "for full BFS boundary analysis of a specific session."
}

# ─── Main dispatch ────────────────────────────────────────────────────
case "$mode" in
  --audit)
    if [ -z "$transcript" ]; then
      echo "Usage: bash scripts/parse-session.sh --audit <transcript.jsonl>"
      exit 1
    fi
    audit_transcript "$transcript"
    ;;
  --summary)
    summary
    ;;
  *)
    if [ -f "$mode" ]; then
      audit_transcript "$mode"
    else
      echo "Usage:"
      echo "  bash scripts/parse-session.sh --summary"
      echo "  bash scripts/parse-session.sh --audit <transcript.jsonl>"
      echo "  bash scripts/parse-session.sh <transcript.jsonl>"
      exit 1
    fi
    ;;
esac
