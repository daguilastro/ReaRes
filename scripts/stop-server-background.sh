#!/usr/bin/env sh

set -eu

STATE_DIRECTORY=${XDG_STATE_HOME:-"$HOME/.local/state"}/restaurante-app
PID_FILE="$STATE_DIRECTORY/server.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "El servidor no está registrado como activo."
  if command -v termux-wake-unlock >/dev/null 2>&1; then
    termux-wake-unlock 2>/dev/null || true
  fi
  exit 0
fi

SERVER_PID=$(sed -n '1p' "$PID_FILE")
case "$SERVER_PID" in
  ''|*[!0-9]*)
    echo "El archivo PID no contiene un valor válido; no se detuvo ningún proceso." >&2
    rm -f "$PID_FILE"
    exit 1
    ;;
esac

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "El proceso $SERVER_PID ya no está ejecutándose."
  rm -f "$PID_FILE"
else
  SERVER_COMMAND=$(ps -p "$SERVER_PID" -o args= 2>/dev/null || true)
  case "$SERVER_COMMAND" in
    *source/backend/server.ts*|*npm\ start*) ;;
    *)
      echo "El PID $SERVER_PID pertenece a otro proceso; no se detendrá." >&2
      exit 1
      ;;
  esac

  echo "Deteniendo servidor (PID $SERVER_PID)..."
  if command -v pkill >/dev/null 2>&1; then
    pkill -TERM -P "$SERVER_PID" 2>/dev/null || true
  fi
  kill -TERM "$SERVER_PID" 2>/dev/null || true

  ATTEMPTS=0
  while kill -0 "$SERVER_PID" 2>/dev/null && [ "$ATTEMPTS" -lt 25 ]; do
    sleep 0.2
    ATTEMPTS=$((ATTEMPTS + 1))
  done
  if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "El servidor no respondió a SIGTERM; se forzará su cierre." >&2
    kill -KILL "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  echo "Servidor detenido."
fi

if command -v termux-wake-unlock >/dev/null 2>&1; then
  termux-wake-unlock 2>/dev/null || true
fi
