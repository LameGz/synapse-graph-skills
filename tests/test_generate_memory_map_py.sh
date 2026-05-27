#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/synapse-graph-memory/examples/solo-saas"
ENGINE="$REPO_ROOT/synapse-graph-memory/scripts/generate_memory_map.py"
TMP_ROOT="$REPO_ROOT/.tmp-generate-memory-map-py"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"
cp -R "$PROJECT" "$TMP_ROOT/project"
PROJECT_COPY="$TMP_ROOT/project"
OUT="$TMP_ROOT/full.out"

SYNAPSE_MAP_GENERATED_AT=1970-01-01T00:00:00Z python "$ENGINE" --project "$PROJECT_COPY" --full > "$OUT"

grep -q "MEMORY_MAP.md regenerated" "$OUT"
grep -q "feat_login" "$PROJECT_COPY/MEMORY_MAP.md"
grep -q "mod_auth-api" "$PROJECT_COPY/MEMORY_MAP.md"
grep -q "## Tag Index" "$PROJECT_COPY/MEMORY_MAP.md"
grep -q "## Progress Summary" "$PROJECT_COPY/MEMORY_MAP.md"
grep -q '"id": "feat_login"' "$PROJECT_COPY/MEMORY_MAP.json"
grep -q '"tags": \[' "$PROJECT_COPY/MEMORY_MAP.json"

SYNAPSE_MAP_GENERATED_AT=1970-01-01T00:00:00Z python "$ENGINE" --project "$PROJECT_COPY" --full > "$TMP_ROOT/full.out"

python - "$PROJECT_COPY/meta/feat_login.md" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("Login feature connects", "Changed login feature connects"), encoding="utf-8")
PY

python - "$PROJECT_COPY/meta/feat_subscription.md" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("Subscription feature displays", "UNDECLARED subscription feature displays"), encoding="utf-8")
PY

SYNAPSE_MAP_GENERATED_AT=1970-01-01T00:00:00Z python "$ENGINE" --project "$PROJECT_COPY" --changed feat_login.md > "$TMP_ROOT/changed.out"
grep -q "Incremental update" "$TMP_ROOT/changed.out"
grep -q "Changed login feature connects" "$PROJECT_COPY/MEMORY_MAP.json"
if grep -q "UNDECLARED subscription" "$PROJECT_COPY/MEMORY_MAP.json"; then
  echo "--changed reparsed a node outside the changed target" >&2
  exit 1
fi

rm -rf "$TMP_ROOT"

echo "generate_memory_map.py: OK"
