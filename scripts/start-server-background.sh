#!/data/data/com.termux/files/usr/bin/sh

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$(dirname -- "$SCRIPT_DIRECTORY")
STATE_DIRECTORY=${XDG_STATE_HOME:-"$HOME/.local/state"}/restaurante-app
PID_FILE="$STATE_DIRECTORY/server.pid"
LOG_FILE="$STATE_DIRECTORY/server.log"

mkdir -p "$STATE_DIRECTORY"

if [ -f "$PID_FILE" ]; then
  EXISTING_PID=$(sed -n '1p' "$PID_FILE")
  case "$EXISTING_PID" in
    ''|*[!0-9]*) ;;
    *)
      if kill -0 "$EXISTING_PID" 2>/dev/null; then
        echo "El servidor ya está ejecutándose (PID $EXISTING_PID)."
        echo "Log: $LOG_FILE"
        exit 0
      fi
      ;;
  esac
fi

if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock
fi

cd "$PROJECT_DIRECTORY"
nohup npm start </dev/null >>"$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" >"$PID_FILE"

echo "Servidor iniciado en segundo plano (PID $SERVER_PID)."
echo "Log: $LOG_FILE"
