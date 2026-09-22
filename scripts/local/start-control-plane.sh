#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${HINDSIGHT_RUNTIME_DIR:-$HOME/.local/share/hindsight}"
ENV_FILE="$RUNTIME_DIR/config.env"
CONTROL_PLANE_CLI="$RUNTIME_DIR/control-plane/node_modules/@vectorize-io/hindsight-control-plane/bin/cli.js"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Hindsight runtime configuration is missing."
  exit 1
fi
if [[ ! -f "$CONTROL_PLANE_CLI" ]]; then
  echo "Hindsight Control Plane is not installed at $CONTROL_PLANE_CLI"
  exit 1
fi

set -a
# The official Control Plane reads HINDSIGHT_CP_DATAPLANE_API_KEY and
# HINDSIGHT_CP_ACCESS_KEY from its environment when auth is configured.
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

HINDSIGHT_API_URL="${HINDSIGHT_CP_DATAPLANE_API_URL:-http://127.0.0.1:8888}"

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
exec /usr/local/bin/node "$CONTROL_PLANE_CLI" \
  --hostname localhost \
  --port 9999 \
  --api-url "$HINDSIGHT_API_URL"
