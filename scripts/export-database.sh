#!/usr/bin/env sh

set -eu

DATA_HOME=${XDG_DATA_HOME:-"$HOME/.local/share"}
DATABASE_FILE=${RESTAURANTE_DB_FILE:-"$DATA_HOME/restaurante-app/restaurant.sqlite"}

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "No se encontró sqlite3. Instálalo con: pkg install sqlite" >&2
  exit 1
fi

if [ ! -f "$DATABASE_FILE" ]; then
  echo "No se encontró la base de datos: $DATABASE_FILE" >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  EXPORT_FILE=$1
elif [ -d "$HOME/storage/downloads" ]; then
  EXPORT_FILE="$HOME/storage/downloads/restaurant-$(date +%Y%m%d-%H%M%S).sqlite"
elif [ -d "$HOME/Downloads" ]; then
  EXPORT_FILE="$HOME/Downloads/restaurant-$(date +%Y%m%d-%H%M%S).sqlite"
else
  echo "No se encontró una carpeta de descargas accesible." >&2
  echo "En Termux ejecuta primero: termux-setup-storage" >&2
  exit 1
fi

EXPORT_DIRECTORY=$(dirname -- "$EXPORT_FILE")
mkdir -p "$EXPORT_DIRECTORY"

# .backup produce una instantánea consistente aunque SQLite esté usando WAL.
sqlite3 "$DATABASE_FILE" ".backup '$EXPORT_FILE'"

if [ ! -s "$EXPORT_FILE" ]; then
  echo "La exportación no generó un archivo válido." >&2
  exit 1
fi

echo "Base de datos exportada correctamente:"
echo "$EXPORT_FILE"
ls -lh "$EXPORT_FILE"
