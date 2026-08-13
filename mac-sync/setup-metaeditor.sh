#!/bin/bash
set -euo pipefail

# Create a symlink so MetaEditor sees the repo under MQL5/Experts/Trading-Robot.
# Run this once on your Mac from inside the Trading-Robot folder:
#   ./mac-sync/setup-metaeditor.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Common locations for the MetaTrader 5 MQL5 folder on macOS
CANDIDATES=(
  "$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5"
  "$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files (x86)/MetaTrader 5"
  "$HOME/Library/Application Support/MetaTrader 5"
  "$HOME/.wine/drive_c/Program Files/MetaTrader 5"
  "$HOME/.wine/drive_c/Program Files (x86)/MetaTrader 5"
  "/Applications/MetaTrader 5.app/Contents/drive_c/Program Files/MetaTrader 5"
  "/Applications/MetaTrader 5.app/Contents/drive_c/Program Files (x86)/MetaTrader 5"
)

MT5_DIR=""
for c in "${CANDIDATES[@]}"; do
  if [ -d "$c/MQL5" ]; then
    MT5_DIR="$c"
    break
  fi
done

if [ -z "${1:-}" ]; then
  if [ -z "$MT5_DIR" ]; then
    echo "Could not find your MetaTrader 5 MQL5 folder automatically." >&2
    echo "Please open MetaEditor, choose File → Open Data Folder, then run:" >&2
    echo "  ./mac-sync/setup-metaeditor.sh '/path/to/MetaTrader 5'" >&2
    exit 1
  fi
else
  MT5_DIR="$1"
  if [ ! -d "$MT5_DIR/MQL5" ]; then
    echo "$MT5_DIR/MQL5 not found. Please pass the folder that contains the MQL5 directory." >&2
    exit 1
  fi
fi

EXPERTS_DIR="$MT5_DIR/MQL5/Experts"
mkdir -p "$EXPERTS_DIR"
LINK_TARGET="$EXPERTS_DIR/Trading-Robot"

# Remove any previous symlink or stale folder
if [ -L "$LINK_TARGET" ]; then
  rm "$LINK_TARGET"
elif [ -e "$LINK_TARGET" ]; then
  echo "$LINK_TARGET already exists and is not a symlink. Move or remove it first." >&2
  exit 1
fi

ln -s "$REPO_DIR" "$LINK_TARGET"

echo "Linked repo to: $LINK_TARGET"
echo "In MetaEditor, open Experts → Trading-Robot → MY BOT.mq5"
