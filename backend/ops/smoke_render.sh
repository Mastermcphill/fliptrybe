#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_SCRIPT="$SCRIPT_DIR/../tools/ship_readiness_smoke.sh"

if [[ ! -f "$TOOLS_SCRIPT" ]]; then
  echo "Missing smoke script: $TOOLS_SCRIPT"
  exit 1
fi

exec bash "$TOOLS_SCRIPT"
