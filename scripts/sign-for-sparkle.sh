#!/bin/bash
set -euo pipefail
# Usage: SPARKLE_BIN=/path/to/Sparkle/bin ./scripts/sign-for-sparkle.sh App.app [version]
# Uses QuickMotion's dedicated account unless an explicit key file is selected.
if [[ -z "${SPARKLE_KEY_FILE:-}" ]]; then
    export SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-quickmotion}"
fi
exec python3 "$(dirname "$0")/package-sparkle.py" "$@"
