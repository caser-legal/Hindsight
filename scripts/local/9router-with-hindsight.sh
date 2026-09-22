#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROUTER_BIN="/usr/local/bin/9router"
ROUTER_HEALTH="http://127.0.0.1:20128/api/health"
ROUTER_DASHBOARD="http://127.0.0.1:20128/dashboard"
HINDSIGHT_HEALTH="http://127.0.0.1:8888/health"
HINDSIGHT_CONTROL_PLANE="http://localhost:9999"
HINDSIGHT_LABEL="io.vectorize.hindsight"
HINDSIGHT_CONTROL_PLANE_LABEL="io.vectorize.hindsight-control-plane"
RUNTIME_DIR="${HINDSIGHT_RUNTIME_DIR:-$HOME/.local/share/hindsight}"
RUNTIME_START="$RUNTIME_DIR/start-service.sh"
RUNTIME_CONTROL_PLANE_START="$RUNTIME_DIR/start-control-plane.sh"
HINDSIGHT_LOG="$RUNTIME_DIR/hindsight.log"
CONTROL_PLANE_CLI="$RUNTIME_DIR/control-plane/node_modules/@vectorize-io/hindsight-control-plane/bin/cli.js"
CONTROL_PLANE_LOG="$RUNTIME_DIR/control-plane.log"
LOG_DIR="$ROOT_DIR/logs"

health_ok() {
  curl --fail --silent --max-time 5 "$1" >/dev/null
}

# Hindsight issue #3099 documents that a busy event loop can miss a 2-second
# /health probe even though the process is alive. Give an existing process the
# official 30-second liveness grace before launchd is allowed to replace it.
wait_for_health() {
  local url="$1"
  local budget_seconds="$2"
  local started_at=$SECONDS

  while (( SECONDS - started_at < budget_seconds )); do
    if health_ok "$url"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Preserve every 9Router subcommand. Only the bare `9router` command launches the pair.
if (( $# > 0 )); then
  exec "$ROUTER_BIN" "$@"
fi

mkdir -p "$LOG_DIR" "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
/usr/bin/install -m 700 "$ROOT_DIR/scripts/local/start-service.sh" "$RUNTIME_START"
/usr/bin/install -m 700 "$ROOT_DIR/scripts/local/start-control-plane.sh" "$RUNTIME_CONTROL_PLANE_START"
/usr/bin/install -m 600 "$ROOT_DIR/.env" "$RUNTIME_DIR/config.env"

if ! health_ok "$ROUTER_HEALTH"; then
  nohup "$ROUTER_BIN" --tray --skip-update >>"$LOG_DIR/9router.log" 2>&1 &
  echo $! >"$LOG_DIR/9router.pid"

  for _ in {1..60}; do
    if health_ok "$ROUTER_HEALTH"; then
      break
    fi
    sleep 1
  done
fi

if ! health_ok "$ROUTER_HEALTH"; then
  echo "9Router did not become healthy. See $LOG_DIR/9router.log"
  exit 1
fi

START_HINDSIGHT=0
if ! health_ok "$HINDSIGHT_HEALTH"; then
  if launchctl print "gui/$(id -u)/$HINDSIGHT_LABEL" >/dev/null 2>&1; then
    wait_for_health "$HINDSIGHT_HEALTH" 30 || START_HINDSIGHT=1
  else
    START_HINDSIGHT=1
  fi
fi

if (( START_HINDSIGHT )); then
  # A launchd-owned process survives after the terminal command exits.
  launchctl remove "$HINDSIGHT_LABEL" >/dev/null 2>&1 || true
  launchctl submit \
    -l "$HINDSIGHT_LABEL" \
    -o "$HINDSIGHT_LOG" \
    -e "$HINDSIGHT_LOG" \
    -- /bin/bash "$RUNTIME_START"

  for _ in {1..180}; do
    if health_ok "$HINDSIGHT_HEALTH"; then
      break
    fi
    sleep 1
  done
fi

START_CONTROL_PLANE=0
if health_ok "$HINDSIGHT_HEALTH" && ! health_ok "$HINDSIGHT_CONTROL_PLANE"; then
  if launchctl print "gui/$(id -u)/$HINDSIGHT_CONTROL_PLANE_LABEL" >/dev/null 2>&1; then
    wait_for_health "$HINDSIGHT_CONTROL_PLANE" 30 || START_CONTROL_PLANE=1
  else
    START_CONTROL_PLANE=1
  fi
fi

if (( START_CONTROL_PLANE )); then
  if [[ ! -f "$CONTROL_PLANE_CLI" ]]; then
    echo "Hindsight Control Plane is not installed at $CONTROL_PLANE_CLI"
    exit 1
  fi

  launchctl remove "$HINDSIGHT_CONTROL_PLANE_LABEL" >/dev/null 2>&1 || true
  launchctl submit \
    -l "$HINDSIGHT_CONTROL_PLANE_LABEL" \
    -o "$CONTROL_PLANE_LOG" \
    -e "$CONTROL_PLANE_LOG" \
    -- /bin/bash "$RUNTIME_CONTROL_PLANE_START"

  for _ in {1..120}; do
    if health_ok "$HINDSIGHT_CONTROL_PLANE"; then
      break
    fi
    sleep 1
  done
fi

if [[ "${HINDSIGHT_OPEN_ONLY:-0}" != "1" ]]; then
  /usr/bin/open "$ROUTER_DASHBOARD"
fi

if health_ok "$HINDSIGHT_CONTROL_PLANE"; then
  /usr/bin/open "$HINDSIGHT_CONTROL_PLANE"
  echo "9Router, Hindsight, and the Hindsight Control Plane are running."
elif health_ok "$HINDSIGHT_HEALTH"; then
  echo "Hindsight is running; its Control Plane is still starting. See $CONTROL_PLANE_LOG"
else
  echo "9Router is running; Hindsight is still starting. See $HINDSIGHT_LOG"
fi
