#!/usr/bin/env bash
set -euo pipefail
umask 077

RUNTIME_DIR="${HINDSIGHT_RUNTIME_DIR:-$HOME/.local/share/hindsight}"
ENV_FILE="$RUNTIME_DIR/config.env"
ADMIN="$RUNTIME_DIR/.venv/bin/hindsight-admin"
PYTHON="$RUNTIME_DIR/.venv/bin/python"
BACKUP_DIR="${HINDSIGHT_BACKUP_DIR:-$HOME/Library/Application Support/Hindsight/backups}"
KEEP="${HINDSIGHT_BACKUP_KEEP:-30}"
MODE="backup"
BANK_ID=""

usage() {
  echo "Usage: $0 [--bank BANK_ID] [--keep COUNT]"
  echo "  no --bank: official full-database backup"
  echo "  --bank:    official portable bank export"
}

while (( $# > 0 )); do
  case "$1" in
    --bank)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      MODE="export"
      BANK_ID="$2"
      shift 2
      ;;
    --keep)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      KEEP="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || { echo "--keep must be a positive integer." >&2; exit 2; }
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
[[ -x "$ADMIN" ]] || { echo "Missing working $ADMIN; rerun setup-standalone.sh." >&2; exit 1; }
[[ -x "$PYTHON" ]] || { echo "Missing $PYTHON" >&2; exit 1; }

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

LOCK_DIR="$RUNTIME_DIR/.backup.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  LOCK_PID="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ "$LOCK_PID" =~ ^[0-9]+$ ]] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "Another Hindsight backup is already running (PID $LOCK_PID)."
    exit 0
  fi
  rm -f "$LOCK_DIR/pid"
  rmdir "$LOCK_DIR"
  mkdir "$LOCK_DIR"
fi
echo "$$" >"$LOCK_DIR/pid"

TEMP_ARCHIVE=""
cleanup() {
  [[ -z "$TEMP_ARCHIVE" ]] || rm -f "$TEMP_ARCHIVE"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

set -a
# hindsight-admin officially reads the same environment as the API service.
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ "$MODE" == "backup" ]]; then
  BASENAME="hindsight-full-$TIMESTAMP.zip"
  ROTATION_PREFIX="hindsight-full-"
else
  SAFE_BANK="$(printf '%s' "$BANK_ID" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
  [[ -n "$SAFE_BANK" ]] || SAFE_BANK="bank"
  BASENAME="hindsight-bank-$SAFE_BANK-$TIMESTAMP.zip"
  ROTATION_PREFIX="hindsight-bank-$SAFE_BANK-"
fi

FINAL_ARCHIVE="$BACKUP_DIR/$BASENAME"
TEMP_ARCHIVE="$BACKUP_DIR/.$BASENAME.in-progress.zip"

if [[ "$MODE" == "backup" ]]; then
  "$ADMIN" backup "$TEMP_ARCHIVE"
else
  "$ADMIN" export-bank --bank "$BANK_ID" --output "$TEMP_ARCHIVE"
fi

# Validate the completed ZIP before publishing it atomically.
"$PYTHON" - "$TEMP_ARCHIVE" "$MODE" <<'PY'
import json
import sys
import zipfile

archive, mode = sys.argv[1:]
with zipfile.ZipFile(archive) as zf:
    broken = zf.testzip()
    if broken:
        raise SystemExit(f"corrupt ZIP member: {broken}")
    if not zf.namelist():
        raise SystemExit("backup archive is empty")
    if mode == "backup":
        manifest = json.loads(zf.read("manifest.json"))
        if not manifest.get("tables"):
            raise SystemExit("backup manifest contains no tables")
PY

chmod 600 "$TEMP_ARCHIVE"
mv "$TEMP_ARCHIVE" "$FINAL_ARCHIVE"
TEMP_ARCHIVE=""

# Rotate only matching, successfully published archives, newest first.
"$PYTHON" - "$BACKUP_DIR" "$ROTATION_PREFIX" "$KEEP" <<'PY'
import pathlib
import sys

directory = pathlib.Path(sys.argv[1]).resolve()
prefix = sys.argv[2]
keep = int(sys.argv[3])
archives = sorted(directory.glob(f"{prefix}*.zip"), key=lambda p: p.stat().st_mtime, reverse=True)
for archive in archives[keep:]:
    if archive.is_file() and archive.parent.resolve() == directory:
        archive.unlink()
PY

echo "Hindsight archive saved: $FINAL_ARCHIVE"
