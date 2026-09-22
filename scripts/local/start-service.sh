#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${HINDSIGHT_RUNTIME_DIR:-$HOME/.local/share/hindsight}"
ENV_FILE="$RUNTIME_DIR/config.env"
HINDSIGHT_PYTHON="$RUNTIME_DIR/.venv/bin/python"
HINDSIGHT_ENTRYPOINT="$RUNTIME_DIR/.venv/bin/hindsight-api"

if [[ ! -x "$HINDSIGHT_PYTHON" ]] || [[ ! -f "$HINDSIGHT_ENTRYPOINT" ]]; then
  echo "Hindsight runtime is missing. Run ./scripts/local/setup-standalone.sh first."
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Hindsight runtime configuration is missing."
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [[ "${HINDSIGHT_API_LLM_MODEL:-}" == "TO_BE_SELECTED" ]] ||
   [[ "${HINDSIGHT_API_LLM_MODEL:-}" == "replace-with-a-model-id-from-9router" ]]; then
  echo "Set HINDSIGHT_API_LLM_MODEL in .env to an exact 9Router model or combo ID."
  exit 1
fi

if ! /usr/bin/curl --fail --silent --show-error --max-time 5 \
  -H "Authorization: Bearer $HINDSIGHT_API_LLM_API_KEY" \
  "$HINDSIGHT_API_LLM_BASE_URL/models" >/dev/null; then
  echo "9Router is not responding at $HINDSIGHT_API_LLM_BASE_URL."
  exit 1
fi

exec "$HINDSIGHT_PYTHON" "$HINDSIGHT_ENTRYPOINT" "$@"
