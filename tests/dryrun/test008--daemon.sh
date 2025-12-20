#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Cross-shell PWD : Detect MSYS/Git Bash and convert to Windows path
CURRENT_PATH=$(pwd)
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # pwd -W returns C:/Users/... instead of /c/Users/...
    CURRENT_PATH="$(pwd -W)"
fi

export TIMEZONE="America/Toronto"

ACTUAL=$(../../workspace.sh --variant container --dryrun --daemon -- tree -C)

HERE="$CURRENT_PATH"
VERSION="$(cat ../../version.txt)"

EXPECT="\
📦 Running workspace in daemon mode.
👉 Stop with 'workspace.sh -- exit'. The container will be removed (--rm) when stop.
👉 Visit 'http://localhost:10000'
👉 To open an interactive shell instead: workspace.sh -- bash
👉 To stop the running contaienr:

      docker stop dryrun

👉 Container Name: dryrun
👉 Container ID: <--dryrun-->

docker run \
-d \
--rm \
--name dryrun \
-e 'HOST_UID=${HOST_UID}' \
-e 'HOST_GID=${HOST_GID}' \
-v ${HERE}:/home/coder/workspace \
-w /home/coder/workspace \
-p 10000:10000 \
-e 'WS_SETUPS_DIR=/opt/workspace/setups' \
-e 'WS_CONTAINER_NAME=dryrun' \
-e 'WS_DAEMON=true' \
-e 'WS_HOST_PORT=10000' \
-e 'WS_IMAGE_NAME=nawaman/workspace:container-${VERSION}' \
-e 'WS_RUNMODE=DAEMON' \
-e 'WS_VARIANT_TAG=container' \
-e 'WS_VERBOSE=false' \
-e 'WS_VERSION_TAG=${VERSION}' \
-e 'WS_WORKSPACE_PATH=${HERE}' \
-e 'WS_WORKSPACE_PORT=NEXT' \
-e 'WS_HAS_NOTEBOOK=false' \
-e 'WS_HAS_VSCODE=false' \
-e 'WS_HAS_DESKTOP=false' \
'--pull=never' \
-e 'TZ=America/Toronto' \
nawaman/workspace:container-${VERSION} \
bash -lc tree -C "

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
