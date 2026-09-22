#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_DIR="${HINDSIGHT_RUNTIME_DIR:-$HOME/.local/share/hindsight}"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/io.vectorize.hindsight-backup.plist"
LABEL="io.vectorize.hindsight-backup"

mkdir -p "$RUNTIME_DIR" "$HOME/Library/LaunchAgents"
chmod 700 "$RUNTIME_DIR"
/usr/bin/install -m 700 "$ROOT_DIR/scripts/local/backup-hindsight.sh" "$RUNTIME_DIR/backup-hindsight.sh"
/usr/bin/install -m 600 "$ROOT_DIR/scripts/local/io.vectorize.hindsight-backup.plist" "$LAUNCH_AGENT"
# The committed plist uses __HOME__ so it does not contain a machine path.
/usr/bin/sed -i '' "s|__HOME__|$HOME|g" "$LAUNCH_AGENT"

plutil -lint "$LAUNCH_AGENT" >/dev/null
launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"

echo "Daily Hindsight backups installed at 03:15 local time."
echo "Backup directory: $HOME/Library/Application Support/Hindsight/backups"
