#!/usr/bin/env bash
set -euo pipefail

SKIP_TESTS=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/release_check.sh [options]

Options:
  --skip-tests       Skip the unittest suite
  -h, --help         Show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/.." && pwd)"
EXAMPLE_DIR="$SKILL_DIR/examples/solo-saas"
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

PYTHON_BIN="$(pick_python || true)"
if [ -z "$PYTHON_BIN" ]; then
  echo "Error: runnable python or python3 is required" >&2
  exit 1
fi
export PYTHON_BIN

cd "$REPO_ROOT"

echo "Synapse Solo release check"
echo "Project: $REPO_ROOT"
echo ""

if [ "$SKIP_TESTS" -eq 1 ]; then
  echo "- tests: skipped"
else
  bash "$REPO_ROOT/tests/test_runner.sh" --all
  bash "$REPO_ROOT/tests/test_generate_memory_map_py.sh"
  bash "$REPO_ROOT/tests/test_suggest_edges_fast.sh"
  bash "$REPO_ROOT/tests/test_suggest_edges_dedup.sh"
  "$PYTHON_BIN" "$REPO_ROOT/tests/test_memory_inbox.py"
  "$PYTHON_BIN" "$REPO_ROOT/tests/test_project_resume.py"
  bash "$REPO_ROOT/tests/test_legacy_capabilities.sh"
  echo "- tests: OK"
fi

SYNAPSE_MAP_GENERATED_AT=1970-01-01T00:00:00Z bash "$SCRIPT_DIR/generate_memory_map.sh" --project "$EXAMPLE_DIR" --full
echo "- solo-saas map: rebuilt"

bash "$SCRIPT_DIR/doctor.sh" --project "$EXAMPLE_DIR"
echo "- solo-saas doctor: OK"

bash "$SCRIPT_DIR/demo_solo_saas.sh" --project "$EXAMPLE_DIR" --dry-run
echo "- solo-saas demo: OK"

"$PYTHON_BIN" "$SCRIPT_DIR/project_resume.py" --project "$EXAMPLE_DIR" >/dev/null
echo "- solo-saas resume: OK"

for doc in README.md README.zh-CN.md USAGE.md RELEASE_NOTES.md; do
  if [ ! -f "$REPO_ROOT/$doc" ]; then
    echo "Missing required doc: $doc" >&2
    exit 1
  fi
done
echo "- docs: OK"

echo ""
echo "Synapse Solo release check passed."
