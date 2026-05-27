#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/synapse-graph-memory/examples/solo-saas"
SCRIPT="$REPO_ROOT/synapse-graph-memory/scripts/suggest_edges.sh"

start=$(date +%s)
output="$(bash "$SCRIPT" --project "$PROJECT")"
elapsed=$(( $(date +%s) - start ))

printf '%s\n' "$output" | grep -q "Synapse Edge Suggestions"

if [ "$elapsed" -gt 20 ]; then
  echo "Expected suggest_edges to finish within 20s, took ${elapsed}s" >&2
  exit 1
fi

echo "suggest_edges performance: OK (${elapsed}s)"
