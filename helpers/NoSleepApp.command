#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if [[ -d "/Applications/NoSleepApp.app" ]]; then
    open "/Applications/NoSleepApp.app"
    echo "⚡ NoSleepApp launched from /Applications!"
elif [[ -d "$ROOT_DIR/NoSleepApp.app" ]]; then
    open "$ROOT_DIR/NoSleepApp.app"
    echo "⚡ NoSleepApp launched!"
else
    echo "NoSleepApp not found. Running installer..."
    "$ROOT_DIR/scripts/install.sh"
fi
