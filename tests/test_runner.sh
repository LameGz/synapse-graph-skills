#!/usr/bin/env bash
# Synapse Graph Skills — Test Runner
# Runs eval suites for one or all skills.
#
# Usage:
#   bash tests/test_runner.sh --skill synapse-timeline
#   bash tests/test_runner.sh --all
#   bash tests/test_runner.sh --skill synapse-graph-memory --eval 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
    echo -e "${RED}ERROR: runnable python or python3 is required${NC}" >&2
    exit 1
fi

SKILL=""
ALL=false
EVAL_ID=""

usage() {
    cat <<EOF
Usage: test_runner.sh [OPTIONS]

Options:
  --skill <name>   Test a specific skill (e.g., synapse-timeline)
  --all            Test all skills
  --eval <id>      Run a specific eval case by ID (requires --skill)
  -h, --help       Show this help

Examples:
  bash tests/test_runner.sh --skill synapse-timeline
  bash tests/test_runner.sh --all
  bash tests/test_runner.sh --skill synapse-graph-memory --eval 1
EOF
    exit 0
}

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skill) SKILL="$2"; shift 2 ;;
        --all) ALL=true; shift ;;
        --eval) EVAL_ID="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [ "$ALL" = false ] && [ -z "$SKILL" ]; then
    echo -e "${RED}ERROR: Must specify --skill or --all${NC}"
    usage
fi

# Validate skill directory
validate_skill() {
    local skill_dir="$1"
    local skill_name
    skill_name="$(basename "$skill_dir")"

    echo -n "  $skill_name ... "

    # Check required files
    local errors=0
    if [ ! -f "$skill_dir/SKILL.md" ]; then
        echo -e "${RED}FAIL${NC} (missing SKILL.md)"
        return 1
    fi
    if [ ! -f "$skill_dir/evals/evals.json" ]; then
        echo -e "${RED}FAIL${NC} (missing evals/evals.json)"
        return 1
    fi

    # Validate frontmatter
    if ! head -10 "$skill_dir/SKILL.md" | grep -q "^---$"; then
        echo -e "${RED}FAIL${NC} (bad frontmatter)"
        return 1
    fi

    # Validate evals.json
    if ! "$PYTHON_BIN" -m json.tool "$skill_dir/evals/evals.json" >/dev/null 2>&1; then
        echo -e "${RED}FAIL${NC} (invalid evals.json)"
        return 1
    fi

    # Count eval cases
    local eval_count
    eval_count=$(grep -c '"id"' "$skill_dir/evals/evals.json" || true)
    echo -e "${GREEN}OK${NC} ($eval_count eval cases)"
    return 0
}

# Run a single eval case
run_eval() {
    local skill_dir="$1"
    local eval_id="$2"
    local skill_name
    skill_name="$(basename "$skill_dir")"

    echo ""
    echo -e "${YELLOW}Running eval-$eval_id for $skill_name...${NC}"

    # Read the eval prompt from evals.json
    local prompt
    prompt=$(awk -v id="$eval_id" '
        $0 ~ "\"id\"[[:space:]]*:[[:space:]]*" id { found=1 }
        found && /"prompt"/ {
          sub(/^[[:space:]]*"prompt"[[:space:]]*:[[:space:]]*"/, "")
          sub(/",[[:space:]]*$/, "")
          print
          exit
        }
    ' "$skill_dir/evals/evals.json")

    if [ -z "$prompt" ]; then
        echo -e "${RED}ERROR: eval case $eval_id not found${NC}"
        return 1
    fi

    echo "  Prompt: $prompt"
    echo "  (Full eval execution requires Claude Code — this is a dry-run)"

    # In a real CI environment, this would spawn a Claude Code subprocess:
    # claude --skill "$skill_dir" --prompt "$prompt" --output-dir "$workspace/eval-$eval_id/"

    echo -e "  ${GREEN}Dry-run OK${NC}"
}

# Main
echo "=== Synapse Skill Test Runner ==="
echo ""

SKILLS_TO_TEST=()
if [ "$ALL" = true ]; then
    for d in "$REPO_ROOT"/synapse-*/; do
        [ -d "$d" ] || continue
        [ -f "$d/SKILL.md" ] || continue
        SKILLS_TO_TEST+=("$d")
    done
else
    SKILLS_TO_TEST+=("$REPO_ROOT/$SKILL")
fi

if [ "${#SKILLS_TO_TEST[@]}" -eq 0 ]; then
    echo -e "${RED}ERROR: No synapse-* skill directories found under $REPO_ROOT${NC}"
    exit 1
fi

PASSED=0
FAILED=0

for skill_dir in "${SKILLS_TO_TEST[@]}"; do
    if [ ! -d "$skill_dir" ]; then
        echo -e "${RED}ERROR: Skill directory not found: $skill_dir${NC}"
        FAILED=$((FAILED + 1))
        continue
    fi

    if validate_skill "$skill_dir"; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        continue
    fi

    # Run specific eval if requested
    if [ -n "$EVAL_ID" ]; then
        run_eval "$skill_dir" "$EVAL_ID" || FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
