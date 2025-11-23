#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
PWD=$(pwd)

ACTUAL=$(../../workspace.sh --variant container --dryrun)

HERE="$PWD"
VERSION="$(cat ../../version.txt)"

EXPECT="\
📦 Running workspace in foreground.
👉 Stop with Ctrl+C. The container will be removed (--rm) when stop.
👉 To open an interactive shell instead: 'workspace.sh -- bash'

docker run \
-i \
--rm \
--name dryrun \
-e 'HOST_UID=1000' \
-e 'HOST_GID=1000' \
-v ${HERE}:/home/coder/workspace \
-w /home/coder/workspace \
-p 10000:10000 \
-e 'WS_CONTAINER_NAME=dryrun' \
-e 'WS_DAEMON=false' \
-e 'WS_HOST_PORT=10000' \
-e 'WS_IMAGE_NAME=nawaman/workspace:container-${VERSION}' \
-e 'WS_RUNMODE=FOREGROUND' \
-e 'WS_VARIANT_TAG=container' \
-e 'WS_VERBOSE=false' \
-e 'WS_VERSION_TAG=${VERSION}' \
-e 'WS_WORKSPACE_PATH=${HERE}' \
-e 'WS_WORKSPACE_PORT=10000' \
'--pull=never' \
nawaman/workspace:container-${VERSION} "

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
