#!/bin/bash

set -euo pipefail

# This is to be run by sudo
# Ensure script is run as root (EUID == 0)
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

apt-get update
apt-get install -y \
    --no-install-recommends \
    python3 \
    python3-venv \
    python3-dev \
    build-essential

apt-get clean
rm -rf /var/lib/apt/lists/*

if [ ! -d "/opt/venv" ]; then 
    python3 -m venv /opt/venv
fi

/opt/venv/bin/python -m ensurepip --upgrade

# Pin the version to avoid CVEs.
/opt/venv/bin/pip      \
    install            \
    --no-cache-dir     \
    --no-compile       \
    pip==25.2          \
    setuptools==80.9.0 \
    wheel==0.44.0
