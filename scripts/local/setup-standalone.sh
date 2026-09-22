#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_DIR="${HINDSIGHT_RUNTIME_DIR:-$HOME/.local/share/hindsight}"
VENV_DIR="$RUNTIME_DIR/.venv"
CONTROL_PLANE_DIR="$RUNTIME_DIR/control-plane"
CONTROL_PLANE_VERSION="${HINDSIGHT_CONTROL_PLANE_VERSION:-0.9.0}"

PYTHON_BIN="${HINDSIGHT_PYTHON:-}"
if [[ -z "$PYTHON_BIN" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    # Hindsight v0.9.0 pins a macOS LiteLLM build that does not support Python 3.14.
    for candidate in python3.13 python3.12 python3.11; do
      if command -v "$candidate" >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v "$candidate")"
        break
      fi
    done
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
  fi
fi

if [[ -z "$PYTHON_BIN" ]]; then
  echo "A compatible Python version is required. Use Python 3.11-3.13 on macOS."
  exit 1
fi

"$PYTHON_BIN" - <<'PY'
import sys

if sys.version_info < (3, 11):
    raise SystemExit("Python 3.11 or newer is required.")
PY

mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"

# A virtualenv cannot be relocated: its console-script shebangs contain the
# absolute path used at creation. Replace any previously moved environment and
# create the replacement directly at its final runtime path.
VENV_BACKUP=""
if [[ -d "$VENV_DIR" ]]; then
  EXPECTED_SHEBANG="#!$VENV_DIR/bin/python"
  API_SHEBANG="$(head -n 1 "$VENV_DIR/bin/hindsight-api" 2>/dev/null || true)"
  ADMIN_SHEBANG="$(head -n 1 "$VENV_DIR/bin/hindsight-admin" 2>/dev/null || true)"
  if [[ "$API_SHEBANG" != "$EXPECTED_SHEBANG" ]] ||
     [[ "$ADMIN_SHEBANG" != "$EXPECTED_SHEBANG" ]]; then
    VENV_BACKUP="$RUNTIME_DIR/.venv.stale.$(date -u +%Y%m%dT%H%M%SZ)"
    mv "$VENV_DIR" "$VENV_BACKUP"
    echo "Moved relocated virtualenv to $VENV_BACKUP"
  fi
fi

restore_previous_venv() {
  if [[ -n "$VENV_BACKUP" ]] && [[ -d "$VENV_BACKUP" ]]; then
    if [[ -d "$VENV_DIR" ]]; then
      mv "$VENV_DIR" "$RUNTIME_DIR/.venv.failed.$(date -u +%Y%m%dT%H%M%SZ)"
    fi
    mv "$VENV_BACKUP" "$VENV_DIR"
  fi
}
trap restore_previous_venv ERR

"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/python" -m pip install "$ROOT_DIR/hindsight-api-slim[local-onnx,embedded-db]"

if ! command -v npm >/dev/null 2>&1; then
  echo "Node.js and npm are required for the official Hindsight Control Plane."
  exit 1
fi
npm install --prefix "$CONTROL_PLANE_DIR" \
  "@vectorize-io/hindsight-control-plane@$CONTROL_PLANE_VERSION"
if [[ ! -f "$CONTROL_PLANE_DIR/node_modules/@vectorize-io/hindsight-control-plane/bin/cli.js" ]]; then
  echo "Hindsight Control Plane $CONTROL_PLANE_VERSION was not installed correctly."
  exit 1
fi

EXPECTED_SHEBANG="#!$VENV_DIR/bin/python"
for entrypoint in hindsight-api hindsight-admin; do
  if [[ "$(head -n 1 "$VENV_DIR/bin/$entrypoint")" != "$EXPECTED_SHEBANG" ]]; then
    echo "$entrypoint was not installed with the runtime virtualenv path."
    false
  fi
done
"$VENV_DIR/bin/hindsight-admin" --help >/dev/null
trap - ERR

echo
echo "Hindsight is installed in $VENV_DIR"
echo "Hindsight Control Plane $CONTROL_PLANE_VERSION is installed in $CONTROL_PLANE_DIR"
echo "Start it with: ./scripts/local/start-standalone.sh"
