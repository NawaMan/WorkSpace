#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

export PY_VERSION=${PY_VERSION:-3.12}

if [[ "$WS_VARIANT_TAG" == "notebook" ]]; then
    /opt/workspace/setups/notebook-setup.sh "${PY_VERSION}"
fi
if [[ "$WS_VARIANT_TAG" == "codeserver" ]]; then
    /opt/workspace/setups/codeserver-setup.sh "${PY_VERSION}"
fi