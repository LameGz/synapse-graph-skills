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
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/examples/solo-saas"

cd "$ROOT_DIR"

echo "Synapse Solo release check"
echo "Project: $ROOT_DIR"
echo ""

if [ "$SKIP_TESTS" -eq 1 ]; then
  echo "- tests: skipped"
else
  python -m unittest discover -s tests -p "test_*.py" -v
  echo "- tests: OK"
fi

bash "$SCRIPT_DIR/generate_memory_map.sh" --project "$EXAMPLE_DIR" --full
echo "- solo-saas map: rebuilt"

bash "$SCRIPT_DIR/doctor.sh" --project "$EXAMPLE_DIR"
echo "- solo-saas doctor: OK"

bash "$SCRIPT_DIR/demo_solo_saas.sh" --project "$EXAMPLE_DIR" --dry-run
echo "- solo-saas demo: OK"

for doc in README.md README.zh-CN.md USAGE.md CHANGELOG.md; do
  if [ ! -f "$ROOT_DIR/$doc" ]; then
    echo "Missing required doc: $doc" >&2
    exit 1
  fi
done
echo "- docs: OK"

echo ""
echo "Synapse Solo release check passed."
