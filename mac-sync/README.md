# macOS Auto-Sync for Trading-Robot

This makes the MQL5 repo stay in sync between your Mac and Devin.

## How it works

- A macOS `launchd` LaunchAgent runs `mac-sync/sync.sh` every 30 seconds.
- The script `git pull`s the latest changes from GitHub, then commits and `git push`es any edits you made on your Mac.
- Devin uses the same GitHub repo, so changes from either side appear on the other after the next sync cycle.

## One-time setup on your Mac

1. Clone the repo (if you haven't already):
   ```bash
   git clone https://github.com/yackenieball21-jpg/Trading-Robot.git
   cd Trading-Robot
   ```

2. Run the installer:
   ```bash
   ./mac-sync/install.sh
   ```

3. Edit any `.mq5` or `.mqh` file in `Trading-Robot/` with MetaEditor or any editor.
   Your changes are committed and pushed automatically within 30 seconds.

## Stop or restart sync

```bash
launchctl unload ~/Library/LaunchAgents/com.yackenie.tradingrobot.sync.plist
launchctl load   ~/Library/LaunchAgents/com.yackenie.tradingrobot.sync.plist
```

## Notes

- Sync logs are written to `mac-sync/sync.log`.
- If both sides edit the same file at the same time, the script stops and asks you to resolve the conflict manually.
- The Devin blueprint (once approved) auto-clones/pulls the same repo at session start.
