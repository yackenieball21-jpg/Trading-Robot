#!/bin/bash
set -euo pipefail

# Auto-sync script for the Trading-Robot MQL5 repo on macOS.
# Run from a launchd LaunchAgent every 30 seconds.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_DIR/mac-sync/sync.log"

exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync start: $REPO_DIR"

cd "$REPO_DIR"

# Make sure the local branch is tracking origin/main
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "Not on main branch (on $CURRENT_BRANCH), skipping sync."
  exit 0
fi

# Stash any local uncommitted changes before pulling, then restore them.
STASHED=0
if ! git diff --quiet HEAD; then
  echo "Local changes detected; stashing before pull."
  git stash push -m "auto-sync autosave $(date +%s)"
  STASHED=1
fi

# Pull latest changes from GitHub
git pull --rebase origin main || {
  echo "Pull failed; aborting rebase and restoring stash if present."
  git rebase --abort 2>/dev/null || true
  if [ "$STASHED" = "1" ]; then
    git stash pop 2>/dev/null || true
  fi
  exit 1
}

# Restore stashed changes, if any
if [ "$STASHED" = "1" ]; then
  git stash pop 2>/dev/null || true
fi

# If a merge conflict remains, do not push; let the user resolve.
if git diff --name-only --diff-filter=U | grep -q .; then
  echo "Merge conflict detected. Resolve manually in $REPO_DIR"
  exit 1
fi

# Commit and push any remaining local changes (e.g., edits made on the Mac)
if [ -n "$(git status --porcelain)" ]; then
  echo "Committing local changes."
  git add -A
  git commit -m "auto-sync from Mac $(date '+%Y-%m-%d %H:%M:%S')"
  git push origin main
  echo "Pushed local changes."
else
  echo "No local changes to push."
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync done."
