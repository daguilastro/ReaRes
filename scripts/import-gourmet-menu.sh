#!/usr/bin/env sh

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$(dirname -- "$SCRIPT_DIRECTORY")
TSX="$PROJECT_DIRECTORY/node_modules/.bin/tsx"

if [ ! -x "$TSX" ]; then
  echo "No se encontró tsx. Ejecuta primero: npm ci" >&2
  exit 1
fi

cd "$PROJECT_DIRECTORY"
if [ "${1:-}" = "--d1" ]; then
  exec "$TSX" scripts/import-gourmet-menu.ts --d1
fi
exec "$TSX" scripts/import-gourmet-menu.ts
