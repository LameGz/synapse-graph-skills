#!/usr/bin/env bash
# synapse-init/scripts/init.sh — Thin wrapper for cold-start wizard.
# All logic lives in synapse-graph-memory/scripts/init.sh.
# This file delegates with a transparent passthrough.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate the core engine init.sh
ENGINE_INIT=""

if [ -n "${SYNAPSE_ENGINE_PATH:-}" ] && [ -f "$SYNAPSE_ENGINE_PATH" ]; then
  ENGINE_INIT="$SYNAPSE_ENGINE_PATH"
elif [ -f "${SCRIPT_DIR}/../../synapse-graph-memory/scripts/init.sh" ]; then
  ENGINE_INIT="${SCRIPT_DIR}/../../synapse-graph-memory/scripts/init.sh"
elif [ -f "${HOME}/.claude/skills/synapse-graph-memory/scripts/init.sh" ]; then
  ENGINE_INIT="${HOME}/.claude/skills/synapse-graph-memory/scripts/init.sh"
fi

if [ -z "$ENGINE_INIT" ] || [ ! -f "$ENGINE_INIT" ]; then
  echo "Error: synapse-graph-memory (core engine) not found."
  echo ""
  echo "synapse-init is a thin wrapper — it requires the core engine to function."
  echo "Install it first:"
  echo "  cp -r synapse-graph-skills/synapse-graph-memory ~/.claude/skills/"
  echo ""
  echo "Expected locations:"
  echo "  - ${SCRIPT_DIR}/../../synapse-graph-memory/scripts/init.sh"
  echo "  - ~/.claude/skills/synapse-graph-memory/scripts/init.sh"
  echo "  - SYNAPSE_ENGINE_PATH environment variable"
  exit 1
fi

# Transparent passthrough — all args forwarded to core engine
exec bash "$ENGINE_INIT" "$@"
