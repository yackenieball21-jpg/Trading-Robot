#!/bin/bash
set -euo pipefail

# One-line install for macOS auto-sync.
# Run this from inside the repo folder: ./mac-sync/install.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST_NAME="com.yackenie.tradingrobot.sync.plist"
PLIST_SOURCE="$SCRIPT_DIR/$PLIST_NAME"
LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_DEST="$LAUNCHAGENTS_DIR/$PLIST_NAME"

# Make sure git and launchctl are available
if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is not installed." >&2
  exit 1
fi

if ! command -v launchctl >/dev/null 2>&1; then
  echo "Error: launchctl not found (this script is only for macOS)." >&2
  exit 1
fi

mkdir -p "$LAUNCHAGENTS_DIR"

# Fill in the actual repo path in the plist
sed "s|__REPO_DIR__|$REPO_DIR|g" "$PLIST_SOURCE" > "$PLIST_DEST"
chmod 644 "$PLIST_DEST"

# Unload any previous version of the same agent, then load it
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"

echo "Installed and started $PLIST_NAME"
echo "The repo at $REPO_DIR will auto-sync every 30 seconds."
echo "Logs: $REPO_DIR/mac-sync/sync.log"
