#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
PWD=$(pwd)

ACTUAL=$(../../workspace.sh --dryrun --name test-container -- tree -C)

EXPECT="docker run --rm -i \
--name test-container \
-e 'HOST_UID=$HOST_UID' \
-e 'HOST_GID=$HOST_GID' \
-v $PWD:/home/coder/workspace \
-w /home/coder/workspace \
nawaman/workspace:container-latest \
bash -lc 'tree -C'"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  echo "✅ Match"
else
  echo "❌ Differ"
  exit 1
fi
