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

cd "$REPO_ROOT"

echo "Synapse Solo release check"
echo "Project: $REPO_ROOT"
echo ""

if [ "$SKIP_TESTS" -eq 1 ]; then
  echo "- tests: skipped"
else
  bash "$REPO_ROOT/tests/test_runner.sh" --all
  echo "- tests: OK"
fi

bash "$SCRIPT_DIR/generate_memory_map.sh" --project "$EXAMPLE_DIR" --full
echo "- solo-saas map: rebuilt"

bash "$SCRIPT_DIR/doctor.sh" --project "$EXAMPLE_DIR"
echo "- solo-saas doctor: OK"

bash "$SCRIPT_DIR/demo_solo_saas.sh" --project "$EXAMPLE_DIR" --dry-run
echo "- solo-saas demo: OK"

for doc in README.md README.zh-CN.md USAGE.md RELEASE_NOTES.md; do
  if [ ! -f "$REPO_ROOT/$doc" ]; then
    echo "Missing required doc: $doc" >&2
    exit 1
  fi
done
echo "- docs: OK"

echo ""
echo "Synapse Solo release check passed."
