#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
PWD=$(pwd)

ACTUAL=$(../../workspace.sh --variant container --dryrun -- tree -C)

HERE="$PWD"
VERSION="$(cat ../../version.txt)"

EXPECT="\
docker run \
-i \
--rm \
--name dryrun \
-e 'HOST_UID=${HOST_UID}' \
-e 'HOST_GID=${HOST_GID}' \
-v ${HERE}:/home/coder/workspace \
-w /home/coder/workspace \
-p 10000:10000 \
-e 'WS_SETUPS_DIR=/opt/workspace/setups' \
-e 'WS_CONTAINER_NAME=dryrun' \
-e 'WS_DAEMON=false' \
-e 'WS_HOST_PORT=10000' \
-e 'WS_IMAGE_NAME=nawaman/workspace:container-${VERSION}' \
-e 'WS_RUNMODE=COMMAND' \
-e 'WS_VARIANT_TAG=container' \
-e 'WS_VERBOSE=false' \
-e 'WS_VERSION_TAG=${VERSION}' \
-e 'WS_WORKSPACE_PATH=${HERE}' \
-e 'WS_WORKSPACE_PORT=10000' \
-e 'WS_HAS_NOTEBOOK=false' \
-e 'WS_HAS_VSCODE=false' \
-e 'WS_HAS_DESKTOP=false' \
'--pull=never' \
nawaman/workspace:container-${VERSION} \
bash -lc 'tree -C' "

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
