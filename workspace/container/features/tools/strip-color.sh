#!/usr/bin/env bash
set -euo pipefail
sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'