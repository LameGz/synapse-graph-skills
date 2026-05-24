#!/usr/bin/env bash
set -euo pipefail

PROJECT="."
TEXT=""
PROPOSAL=""
EDGE_MODE="auto"
YES=0
DRY_RUN=0
KEEP_PROPOSAL=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/synapse_note.sh --project <path> --text "..." [options]

Options:
  --proposal <path>       Save proposal JSON to this path
  --edge-mode <mode>      auto | explicit | none | issue (default: auto)
  --dry-run              Generate proposal and edge suggestions only
  --keep-proposal        Keep proposal file after successful apply
  --yes                  Apply without interactive confirmation

Edge modes:
  auto      Apply high-confidence machine edges to auto_linked
  explicit  Promote suggested edges to depends_on
  none      Apply node updates only, no edge changes
  issue     Add suggested edges to Open Issues for later review
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --text)
      TEXT="$2"
      shift 2
      ;;
    --proposal)
      PROPOSAL="$2"
      KEEP_PROPOSAL=1
      shift 2
      ;;
    --edge-mode)
      EDGE_MODE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      KEEP_PROPOSAL=1
      shift
      ;;
    --keep-proposal)
      KEEP_PROPOSAL=1
      shift
      ;;
    --yes)
      YES=1
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

if [ -z "$TEXT" ]; then
  echo "Missing required --text" >&2
  usage >&2
  exit 2
fi

case "$EDGE_MODE" in
  auto|explicit|none|issue) ;;
  *)
    echo "Invalid --edge-mode: $EDGE_MODE" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ABS="$(cd "$PROJECT" && pwd)"
DEFAULT_PROPOSAL=0
if [ -z "$PROPOSAL" ]; then
  PROPOSAL="$PROJECT_ABS/.synapse-proposal.json"
  DEFAULT_PROPOSAL=1
fi

python "$SCRIPT_DIR/ingest_memory.py" --project "$PROJECT_ABS" --text "$TEXT" > "$PROPOSAL"

TARGET_NODE="$(python - "$PROPOSAL" <<'PY'
import json
import sys
from pathlib import Path
proposal = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
print(proposal.get("target_node", "unknown"))
PY
)"

cleanup_proposal() {
  if [ "$DEFAULT_PROPOSAL" -eq 1 ] && [ "$KEEP_PROPOSAL" -ne 1 ] && [ -f "$PROPOSAL" ]; then
    rm -f "$PROPOSAL"
  fi
}
trap cleanup_proposal EXIT

echo "Synapse Solo proposal saved: $PROPOSAL"
echo
bash "$SCRIPT_DIR/suggest_edges.sh" --proposal "$PROPOSAL" || true

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "Synapse Solo dry run complete."
  echo "- target: $TARGET_NODE"
  echo "- proposal: $PROPOSAL"
  echo "- applied: no"
  trap - EXIT
  exit 0
fi

echo
if [ "$YES" -ne 1 ]; then
  echo "Choose action:"
  echo "1) apply auto_linked (recommended)"
  echo "2) promote to depends_on"
  echo "3) apply node only"
  echo "4) record edge review as Open Issues"
  echo "5) cancel"
  read -r answer
  case "$answer" in
    1) EDGE_MODE="auto" ;;
    2) EDGE_MODE="explicit" ;;
    3) EDGE_MODE="none" ;;
    4) EDGE_MODE="issue" ;;
    5) echo "Proposal not applied."; exit 0 ;;
    *) echo "Proposal not applied."; exit 0 ;;
  esac
fi

python "$SCRIPT_DIR/apply_memory_proposal.py" --project "$PROJECT_ABS" --proposal "$PROPOSAL" --edge-mode "$EDGE_MODE"
# Incremental MAP update: only re-index the modified node
if [ "$TARGET_NODE" != "unknown" ] && [ -f "${PROJECT_ABS}/meta/${TARGET_NODE}.md" ]; then
  bash "$SCRIPT_DIR/generate_memory_map.sh" --project "$PROJECT_ABS" --changed "${TARGET_NODE}.md"
else
  bash "$SCRIPT_DIR/generate_memory_map.sh" --project "$PROJECT_ABS" --full
fi
doctor_output="$(bash "$SCRIPT_DIR/doctor.sh" --project "$PROJECT_ABS")"
echo "$doctor_output"

if printf '%s\n' "$doctor_output" | grep -q "Synapse doctor passed"; then
  DOCTOR_STATUS="OK"
else
  DOCTOR_STATUS="check output"
fi

echo "Synapse Solo note applied."
echo "- target: $TARGET_NODE"
echo "- edge mode: $EDGE_MODE"
echo "- map: regenerated"
echo "- doctor: $DOCTOR_STATUS"
