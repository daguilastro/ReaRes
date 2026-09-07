#!/usr/bin/env sh

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STATE_DIRECTORY=${XDG_STATE_HOME:-"$HOME/.local/state"}/restaurante-app
PID_FILE="$STATE_DIRECTORY/server.pid"
DATA_HOME=${XDG_DATA_HOME:-"$HOME/.local/share"}
DATABASE_FILE=${RESTAURANTE_DB_FILE:-"$DATA_HOME/restaurante-app/restaurant.sqlite"}
BACKUP_DIRECTORY=${RESTAURANTE_BACKUP_DIR:-"$DATA_HOME/restaurante-app/backups"}
BACKUP_FILE="$BACKUP_DIRECTORY/restaurant-before-account-reset-$(date +%Y%m%d-%H%M%S).sqlite"
SERVER_WAS_RUNNING=0

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "No se encontró sqlite3. En Termux instálalo con: pkg install sqlite" >&2
  exit 1
fi
if [ ! -f "$DATABASE_FILE" ]; then
  echo "No se encontró la base de datos: $DATABASE_FILE" >&2
  exit 1
fi

REFERENCES=$(sqlite3 "$DATABASE_FILE" "SELECT COUNT(*) FROM orders;")
if [ "$REFERENCES" -ne 0 ]; then
  echo "No se borraron las cuentas: existen $REFERENCES pedidos asociados a usuarios." >&2
  echo "Ejecuta primero: $SCRIPT_DIRECTORY/clear-sales-history.sh" >&2
  exit 1
fi

if [ "${1:-}" != "--yes" ]; then
  if [ ! -t 0 ]; then
    echo "Esta operación requiere confirmación. Ejecuta: $0 --yes" >&2
    exit 2
  fi
  echo "Esto borrará todas las cuentas de administradores y empleados."
  echo "También cerrará todas sus sesiones. Los dispositivos emparejados se conservarán."
  printf "Escribe BORRAR para continuar: "
  IFS= read -r ANSWER
  if [ "$ANSWER" != "BORRAR" ]; then
    echo "Operación cancelada."
    exit 0
  fi
fi

if [ -f "$PID_FILE" ]; then
  SERVER_PID=$(sed -n '1p' "$PID_FILE")
  case "$SERVER_PID" in
    ''|*[!0-9]*) ;;
    *)
      if kill -0 "$SERVER_PID" 2>/dev/null; then
        SERVER_WAS_RUNNING=1
        "$SCRIPT_DIRECTORY/stop-server-background.sh"
      fi
      ;;
  esac
fi

restart_server() {
  STATUS=$?
  trap - EXIT
  if [ "$SERVER_WAS_RUNNING" -eq 1 ]; then
    "$SCRIPT_DIRECTORY/start-server-background.sh" || STATUS=1
  fi
  exit "$STATUS"
}
trap restart_server EXIT

mkdir -p "$BACKUP_DIRECTORY"
sqlite3 "$DATABASE_FILE" "PRAGMA wal_checkpoint(TRUNCATE);"
sqlite3 "$DATABASE_FILE" ".backup '$BACKUP_FILE'"

sqlite3 "$DATABASE_FILE" <<'SQL'
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

DELETE FROM admin_sessions;
DELETE FROM employee_sessions;
DELETE FROM employee_halls;
UPDATE activity_log SET author_id = NULL;
DELETE FROM users;

DELETE FROM sqlite_sequence
WHERE name IN ('admin_sessions', 'employee_sessions', 'users');

COMMIT;
VACUUM;
SQL

REMAINING=$(sqlite3 "$DATABASE_FILE" \
  "SELECT (SELECT COUNT(*) FROM users) +
          (SELECT COUNT(*) FROM admin_sessions) +
          (SELECT COUNT(*) FROM employee_sessions);")
if [ "$REMAINING" -ne 0 ]; then
  echo "La verificación falló: todavía existen $REMAINING registros de cuentas." >&2
  echo "Copia de seguridad: $BACKUP_FILE" >&2
  exit 1
fi

echo "Cuentas y sesiones eliminadas correctamente."
echo "Los dispositivos emparejados se conservaron."
echo "Copia de seguridad: $BACKUP_FILE"
