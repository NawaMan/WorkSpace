#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
PWD=$(pwd)

PORT=7654

ACTUAL=$(../../workspace.sh --verbose --dryrun --port $PORT --variant container -- sleep 1)
ACTUAL=$(printf "%s\n" "$ACTUAL" | tail -n 1)

HERE="$PWD"
VERSION="$(cat ../../version.txt)"

# Notice that there is not `-rm`
EXPECT="\
docker run \
-i \
--rm \
--name dryrun \
-e 'HOST_UID=1000' \
-e 'HOST_GID=1000' \
-v ${HERE}:/home/coder/workspace \
-w /home/coder/workspace \
-p ${PORT}:10000 \
-e 'WS_CONTAINER_NAME=dryrun' \
-e 'WS_DAEMON=false' \
-e 'WS_HOST_PORT=${PORT}' \
-e 'WS_IMAGE_NAME=nawaman/workspace:container-${VERSION}' \
-e 'WS_RUNMODE=COMMAND' \
-e 'WS_VARIANT_TAG=container' \
-e 'WS_VERBOSE=true' \
-e 'WS_VERSION_TAG=${VERSION}' \
-e 'WS_WORKSPACE_PATH=${HERE}' \
-e 'WS_WORKSPACE_PORT=${PORT}' \
'--pull=never' \
nawaman/workspace:container-${VERSION} \
bash -lc 'sleep 1' \
"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  echo "✅ Match"
else
  echo "❌ Differ"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
