#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/synapse-graph-memory/examples/solo-saas"
SCRIPT="$REPO_ROOT/synapse-graph-memory/scripts/suggest_edges.sh"

output="$(bash "$SCRIPT" --project "$PROJECT")"

edge="Suggested edge: mod_auth-api depends_on feat_login"
count="$(printf '%s\n' "$output" | grep -c "$edge" || true)"

if [ "$count" -ne 1 ]; then
  echo "Expected exactly one suggestion for '$edge', got $count" >&2
  exit 1
fi

echo "suggest_edges de-duplication: OK"
