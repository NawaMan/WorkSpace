#!/usr/bin/env bash
set -euo pipefail
cat "$1" \
| sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'