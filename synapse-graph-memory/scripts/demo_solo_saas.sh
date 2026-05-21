#!/usr/bin/env bash
set -euo pipefail

PROJECT=""
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/demo_solo_saas.sh [options]

Options:
  --project <path>   Demo project path (default: examples/solo-saas)
  --dry-run          Print demo commands without changing generated map files
  -h, --help         Show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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
if [ -z "$PROJECT" ]; then
  PROJECT="$ROOT_DIR/examples/solo-saas"
fi
PROJECT_ABS="$(cd "$PROJECT" && pwd)"

run_or_print() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "+ $*"
  else
    "$@"
  fi
}

echo "Synapse Solo solo SaaS demo"
echo "Project: $PROJECT_ABS"
echo ""

run_or_print bash "$SCRIPT_DIR/generate_memory_map.sh" --project "$PROJECT_ABS" --full
if [ "$DRY_RUN" -eq 1 ]; then
  echo "- graph: dry-run"
else
  echo "- graph: rebuilt"
fi

run_or_print bash "$SCRIPT_DIR/doctor.sh" --project "$PROJECT_ABS"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "- doctor: dry-run"
else
  echo "- doctor: OK"
fi

echo ""
echo "Timeline preview:"
run_or_print bash "$SCRIPT_DIR/query_timeline.sh" --project "$PROJECT_ABS" --summary --limit 5
if [ "$DRY_RUN" -eq 1 ]; then
  echo "- timeline: dry-run"
else
  echo "- timeline: latest entries shown"
fi

echo ""
echo "Open issues preview:"
run_or_print bash "$SCRIPT_DIR/query_timeline.sh" --project "$PROJECT_ABS" --issues
if [ "$DRY_RUN" -eq 1 ]; then
  echo "- issues: dry-run"
else
  echo "- issues: pending items shown"
fi

echo ""
echo "Try a daily note preview:"
echo "bash scripts/synapse_note.sh --project examples/solo-saas --text \"后台通知接好了，会员订阅激活后发送 notification。\" --dry-run"
