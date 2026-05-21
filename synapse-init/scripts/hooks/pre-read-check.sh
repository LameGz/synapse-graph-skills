#!/usr/bin/env bash
# PreToolUse hook: enforces Layer 1 MAP triage before reading individual node files.
#
# The BFS retrieval protocol requires Agent to read MEMORY_MAP.md (Layer 1)
# before loading any meta/*.md node files (Layer 2). This hook tracks whether
# the MAP has been read in the current session and warns when the protocol
# is violated.
#
# Registration: "PreToolUse": [{ "matcher": "Read", "command": "..." }]
set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$PWD}"
MARKER="${PROJECT_ROOT}/.claude/.synapse_cache/.map_read"

# ─── Parse tool call from stdin (JSON) ─────────────────────────────────
input_line=$(cat <&0 || true)
[ -z "${input_line:-}" ] && exit 0

tool_name=$(echo "$input_line" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true)
file_path=$(echo "$input_line" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true)

[ -z "$tool_name" ] && exit 0
[ -z "$file_path" ] && exit 0

# Only act on Read operations
[ "$tool_name" = "Read" ] || exit 0

# Only act on meta/*.md files
# Allow MEMORY_MAP.md itself (we mark it), but warn on other meta/*.md

case "$file_path" in
  MEMORY_MAP.md)
    # Mark that Layer 1 triage has been performed
    mkdir -p "$(dirname "$MARKER")"
    touch "$MARKER"
    exit 0
    ;;
  meta/*.md) ;;
  *) exit 0 ;;
esac

# ─── Check if MAP has been read this session ───────────────────────────
if [ -f "$MARKER" ]; then
  # Protocol satisfied
  exit 0
fi

# ─── Protocol violation: Layer 2 before Layer 1 ────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ⚠️  SYNAPSE RETRIEVAL PROTOCOL"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📁  You are about to read: $file_path"
echo ""
echo "🛑  Layer 1 triage was skipped."
echo ""
echo "    Required sequence:"
echo "      1. Read MEMORY_MAP.md   (Layer 1: Tag/Keyword/Alias Index)"
echo "      2. Identify 1–3 candidate nodes from MAP summaries"
echo "      3. Read full node files  (Layer 2: only after confirming relevance)"
echo ""
echo "    Cost of MAP scan: ~200–500 tokens."
echo "    Cost of over-reading nodes: 400–1,200 tokens EACH."
echo ""
echo "📋  RECOMMENDATION:"
echo "    Cancel this Read. Open MEMORY_MAP.md first."
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

exit 0
