#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$ROOT_DIR/bin"

# Build first if binary does not exist
if [[ ! -x "$BIN_DIR/treemoji" ]]; then
  "$ROOT_DIR/build.sh"
fi

exec "$BIN_DIR/treemoji" "$@"
