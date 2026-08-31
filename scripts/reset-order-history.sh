#!/usr/bin/env sh

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$(dirname -- "$SCRIPT_DIRECTORY")
STATE_DIRECTORY=${XDG_STATE_HOME:-"$HOME/.local/state"}/restaurante-app
PID_FILE="$STATE_DIRECTORY/server.pid"
DATA_HOME=${XDG_DATA_HOME:-"$HOME/.local/share"}
DATABASE_FILE=${RESTAURANTE_DB_FILE:-"$DATA_HOME/restaurante-app/restaurant.sqlite"}
BACKUP_DIRECTORY=${RESTAURANTE_BACKUP_DIR:-"$DATA_HOME/restaurante-app/backups"}
BACKUP_FILE="$BACKUP_DIRECTORY/restaurant-before-history-reset-$(date +%Y%m%d-%H%M%S).sqlite"
SERVER_WAS_RUNNING=0

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "No se encontró sqlite3. En Termux instálalo con: pkg install sqlite" >&2
  exit 1
fi

if [ ! -f "$DATABASE_FILE" ]; then
  echo "No se encontró la base de datos: $DATABASE_FILE" >&2
  exit 1
fi

if [ -f "$PID_FILE" ]; then
  SERVER_PID=$(sed -n '1p' "$PID_FILE")
  case "$SERVER_PID" in
    ''|*[!0-9]*) ;;
    *)
      if kill -0 "$SERVER_PID" 2>/dev/null; then
        SERVER_WAS_RUNNING=1
        echo "Deteniendo servidor (PID $SERVER_PID)..."
        kill "$SERVER_PID"
        ATTEMPTS=0
        while kill -0 "$SERVER_PID" 2>/dev/null && [ "$ATTEMPTS" -lt 10 ]; do
          sleep 1
          ATTEMPTS=$((ATTEMPTS + 1))
        done
        if kill -0 "$SERVER_PID" 2>/dev/null; then
          echo "El servidor no se detuvo; no se modificó la base de datos." >&2
          exit 1
        fi
      fi
      ;;
  esac
  rm -f "$PID_FILE"
fi

mkdir -p "$BACKUP_DIRECTORY"
sqlite3 "$DATABASE_FILE" "PRAGMA wal_checkpoint(TRUNCATE);"
sqlite3 "$DATABASE_FILE" ".backup '$BACKUP_FILE'"

sqlite3 "$DATABASE_FILE" <<'SQL'
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

DELETE FROM order_item_deliveries;
DELETE FROM order_item_removed_ingredients;
DELETE FROM order_modifications;
DELETE FROM removed_order_items;
DELETE FROM order_items;
DELETE FROM orders;
DELETE FROM activity_log WHERE type = 'Pedido';

UPDATE hall_tables SET status = 'available';
UPDATE table_groups SET status = 'available';

DELETE FROM sqlite_sequence
WHERE name IN (
  'orders',
  'order_items',
  'removed_order_items',
  'order_modifications'
);

COMMIT;
VACUUM;
SQL

REMAINING=$(sqlite3 "$DATABASE_FILE" \
  "SELECT (SELECT COUNT(*) FROM orders) +
          (SELECT COUNT(*) FROM order_items) +
          (SELECT COUNT(*) FROM order_modifications) +
          (SELECT COUNT(*) FROM removed_order_items) +
          (SELECT COUNT(*) FROM order_item_deliveries);")

if [ "$REMAINING" -ne 0 ]; then
  echo "La verificación falló: todavía existen $REMAINING registros." >&2
  echo "La copia de seguridad está en: $BACKUP_FILE" >&2
  exit 1
fi

echo "Historial de pedidos eliminado correctamente."
echo "Copia de seguridad: $BACKUP_FILE"

if [ "$SERVER_WAS_RUNNING" -eq 1 ]; then
  "$SCRIPT_DIRECTORY/start-server-background.sh"
fi
