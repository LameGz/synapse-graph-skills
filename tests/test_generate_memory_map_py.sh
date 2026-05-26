#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/synapse-graph-memory/examples/solo-saas"
ENGINE="$REPO_ROOT/synapse-graph-memory/scripts/generate_memory_map.py"
OUT="$PROJECT/.synapse-map-py-test.out"

python "$ENGINE" --project "$PROJECT" --full > "$OUT"

grep -q "MEMORY_MAP.md regenerated" "$OUT"
grep -q "feat_login" "$PROJECT/MEMORY_MAP.md"
grep -q "mod_auth-api" "$PROJECT/MEMORY_MAP.md"
grep -q "## Tag Index" "$PROJECT/MEMORY_MAP.md"
grep -q "## Progress Summary" "$PROJECT/MEMORY_MAP.md"
grep -q '"id": "feat_login"' "$PROJECT/MEMORY_MAP.json"
grep -q '"tags": \[' "$PROJECT/MEMORY_MAP.json"

echo "generate_memory_map.py: OK"
