#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- configurable args (safe defaults) ----
PY_VERSION=${1:-3.11}              # accepts X.Y or X.Y.Z (exact patch recommended)
VARIANT_TAG=${VARIANT_TAG:-container}

echo PY_VERSION: $PY_VERSION
echo VARIANT_TAG: $VARIANT_TAG
