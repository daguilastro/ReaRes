#!/data/data/com.termux/files/usr/bin/sh

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$(dirname -- "$SCRIPT_DIRECTORY")
STATE_DIRECTORY=${XDG_STATE_HOME:-"$HOME/.local/state"}/restaurante-app
PID_FILE="$STATE_DIRECTORY/server.pid"
LOG_FILE="$STATE_DIRECTORY/server.log"
ADMIN_PORT_FILE=${RESTAURANTE_ADMIN_PORT_FILE:-"${EXTERNAL_STORAGE:-/storage/emulated/0}/Download/restaurante-app/admin-port.txt"}

mkdir -p "$STATE_DIRECTORY"

if [ -f "$PID_FILE" ]; then
  EXISTING_PID=$(sed -n '1p' "$PID_FILE")
  case "$EXISTING_PID" in
    ''|*[!0-9]*) ;;
    *)
      if kill -0 "$EXISTING_PID" 2>/dev/null; then
        EXISTING_COMMAND=$(ps -p "$EXISTING_PID" -o args= 2>/dev/null || true)
        case "$EXISTING_COMMAND" in
          *source/backend/server.ts*|*npm\ start*) ;;
          *)
            echo "El PID guardado pertenece a otro proceso; no se detendrá." >&2
            EXISTING_PID=''
            ;;
        esac
      fi

      if [ -n "$EXISTING_PID" ] && kill -0 "$EXISTING_PID" 2>/dev/null; then
        echo "Reiniciando servidor anterior (PID $EXISTING_PID)..."

        # Las versiones antiguas del script iniciaban el servidor mediante
        # npm, por lo que también detenemos sus procesos hijos.
        if command -v pkill >/dev/null 2>&1; then
          pkill -TERM -P "$EXISTING_PID" 2>/dev/null || true
        fi
        kill -TERM "$EXISTING_PID" 2>/dev/null || true

        ATTEMPTS=0
        while kill -0 "$EXISTING_PID" 2>/dev/null && [ "$ATTEMPTS" -lt 25 ]; do
          sleep 0.2
          ATTEMPTS=$((ATTEMPTS + 1))
        done
        if kill -0 "$EXISTING_PID" 2>/dev/null; then
          kill -KILL "$EXISTING_PID" 2>/dev/null || true
        fi
      fi
      ;;
  esac
fi

rm -f "$PID_FILE"
# Un cierre abrupto puede dejar información de runtime obsoleta. Este archivo
# solo publica endpoints efímeros; la base de datos nunca se toca aquí.
rm -f "$ADMIN_PORT_FILE"

cd "$PROJECT_DIRECTORY"

if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock
fi

nohup ./node_modules/.bin/tsx source/backend/server.ts \
  </dev/null >>"$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" >"$PID_FILE"

ATTEMPTS=0
while [ "$ATTEMPTS" -lt 75 ]; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    rm -f "$PID_FILE"
    echo "El servidor no pudo iniciarse. Últimas líneas del log:" >&2
    tail -n 40 "$LOG_FILE" >&2
    exit 1
  fi
  if [ -s "$ADMIN_PORT_FILE" ]; then
    break
  fi
  sleep 0.2
  ATTEMPTS=$((ATTEMPTS + 1))
done

if [ ! -s "$ADMIN_PORT_FILE" ]; then
  kill -TERM "$SERVER_PID" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo "Node siguió vivo, pero no publicó sus puertos después de 15 segundos." >&2
  echo "Comprueba que Termux tenga acceso al almacenamiento compartido." >&2
  echo "Últimas líneas del log:" >&2
  tail -n 40 "$LOG_FILE" >&2
  exit 1
fi

echo "Servidor iniciado en segundo plano (PID $SERVER_PID)."
echo "Log: $LOG_FILE"
echo "Endpoints: $ADMIN_PORT_FILE"
