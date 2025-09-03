#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
PWD=$(pwd)

ACTUAL=$(../../workspace.sh --dryrun --daemon -- tree -C)

EXPECT="docker run -d \
--name basic \
-e 'HOST_UID=$HOST_UID' \
-e 'HOST_GID=$HOST_GID' \
-v $PWD:/home/coder/workspace \
-w /home/coder/workspace \
-p 10000:10000 \
nawaman/workspace:container-latest \
bash -lc 'while true; do sleep 3600; done'"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  echo "✅ Match"
else
  echo "❌ Differ"
  exit 1
fi
