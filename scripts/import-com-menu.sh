#!/usr/bin/env sh

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$(dirname -- "$SCRIPT_DIRECTORY")
TSX="$PROJECT_DIRECTORY/node_modules/.bin/tsx"

if [ ! -x "$TSX" ]; then
  echo "No se encontró tsx. Ejecuta primero: npm ci" >&2
  exit 1
fi

if [ "${1:-}" = "--yes" ]; then
  shift
  "$SCRIPT_DIRECTORY/clear-menus-products.sh" --yes
else
  "$SCRIPT_DIRECTORY/clear-menus-products.sh"
fi

cd "$PROJECT_DIRECTORY"
exec "$TSX" scripts/import-com-menu.ts "$@"
