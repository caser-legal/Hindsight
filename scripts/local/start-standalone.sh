#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_DIR="${HINDSIGHT_RUNTIME_DIR:-$HOME/.local/share/hindsight}"
SOURCE_ENV_FILE="$ROOT_DIR/.env"
RUNTIME_ENV_FILE="$RUNTIME_DIR/config.env"
RUNTIME_START="$RUNTIME_DIR/start-service.sh"

if [[ ! -x "$RUNTIME_DIR/.venv/bin/python" ]]; then
  echo "Hindsight is not installed. Run ./scripts/local/setup-standalone.sh first."
  exit 1
fi

if [[ ! -f "$SOURCE_ENV_FILE" ]]; then
  echo "Missing .env. Copy .env.9router.example to .env and fill in the key and model."
  exit 1
fi

mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
/usr/bin/install -m 700 "$ROOT_DIR/scripts/local/start-service.sh" "$RUNTIME_START"
/usr/bin/install -m 600 "$SOURCE_ENV_FILE" "$RUNTIME_ENV_FILE"

exec "$RUNTIME_START" "$@"
