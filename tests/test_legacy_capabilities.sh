#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/synapse-graph-memory"
PROJECT="$SKILL/examples/solo-saas"
TMP_ROOT="$REPO_ROOT/.tmp-legacy-capabilities"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"
cp -R "$PROJECT" "$TMP_ROOT/project"
PROJECT_COPY="$TMP_ROOT/project"
mkdir -p "$PROJECT_COPY/scripts" "$PROJECT_COPY/scripts/hooks"
cp "$SKILL/scripts/"*.sh "$PROJECT_COPY/scripts/"
cp "$SKILL/scripts/"*.py "$PROJECT_COPY/scripts/"
cp "$SKILL/scripts/hooks/"*.sh "$PROJECT_COPY/scripts/hooks/"

python_bin="${PYTHON_BIN:-python}"

bash "$SKILL/scripts/generate_memory_map.sh" --project "$PROJECT_COPY" --changed "feat_login.md" > "$TMP_ROOT/changed.out"
grep -Eq "Incremental|changed|MEMORY_MAP.md regenerated" "$TMP_ROOT/changed.out"
grep -q "feat_login" "$PROJECT_COPY/MEMORY_MAP.json"

bash "$SKILL/scripts/generate_memory_map.sh" --project "$PROJECT_COPY" --full --db > "$TMP_ROOT/db.out"
test -f "$PROJECT_COPY/.synapse/cache/memory.db"

bash "$SKILL/scripts/watch.sh" --project "$PROJECT_COPY" --once > "$TMP_ROOT/watch.out"
grep -Eq "STALE|No stale nodes|SQLite cache not found" "$TMP_ROOT/watch.out"

bash "$SKILL/scripts/generate_memory_map.sh" --project "$PROJECT_COPY" --trace-from feat_subscription --traverse-types feature,module > "$TMP_ROOT/trace.out"
grep -Eq '"paths"|"partial"|"error"' "$TMP_ROOT/trace.out"

(
  cd "$PROJECT_COPY"
  bash scripts/init.sh --project "$PROJECT_COPY" --fullstack > "$TMP_ROOT/fullstack.out"
)
test -f "$PROJECT_COPY/meta/proj_project.md"
grep -q "type: project" "$PROJECT_COPY/meta/proj_project.md"
test -f "$PROJECT_COPY/scripts/generate_memory_map.py"
test -f "$PROJECT_COPY/scripts/memory_inbox.py"
test -f "$PROJECT_COPY/scripts/project_resume.py"
test -f "$PROJECT_COPY/scripts/auto_observe.py"

bash "$SKILL/scripts/synapse_note.sh" --project "$PROJECT_COPY" --text "[mod_auth-api] Added login regression note" --edge-mode none --auto-confirm > "$TMP_ROOT/auto-confirm.out"
grep -q "Auto-recorded" "$TMP_ROOT/auto-confirm.out"

"$python_bin" "$SKILL/scripts/project_resume.py" --project "$PROJECT_COPY" > "$TMP_ROOT/resume.out"
grep -q "Synapse Project Resume" "$TMP_ROOT/resume.out"

"$python_bin" "$SKILL/scripts/memory_inbox.py" add --project "$PROJECT_COPY" --proposal "$TMP_ROOT/sample-proposal.json" > "$TMP_ROOT/inbox-empty.out" 2>&1 || true
grep -Eq "not found|Missing" "$TMP_ROOT/inbox-empty.out"

rm -rf "$TMP_ROOT"
echo "legacy capabilities: OK"
