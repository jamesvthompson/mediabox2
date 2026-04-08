#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -t 1 ]; then
    echo "[DEPRECATED] mediabox2.sh has moved to mediabox.sh. Please use ./mediabox.sh." >&2
fi

exec "$SCRIPT_DIR/mediabox.sh" "$@"
