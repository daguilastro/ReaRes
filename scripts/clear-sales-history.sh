#!/usr/bin/env sh

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "${1:-}" != "--yes" ]; then
  if [ ! -t 0 ]; then
    echo "Esta operación requiere confirmación. Ejecuta: $0 --yes" >&2
    exit 2
  fi
  echo "Esto borrará permanentemente todo el historial de ventas y pedidos."
  printf "Escribe BORRAR para continuar: "
  IFS= read -r ANSWER
  if [ "$ANSWER" != "BORRAR" ]; then
    echo "Operación cancelada."
    exit 0
  fi
fi

exec "$SCRIPT_DIRECTORY/reset-order-history.sh"
