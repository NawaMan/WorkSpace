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

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

ACTUAL=$(../../workspace.sh --variant container --dryrun | strip_ansi)

HERE="$CURRENT_PATH"
VERSION="$(cat ../../version.txt)"

EXPECT="\

============================================================
🚀 WORKSPACE PORT SELECTED
============================================================
🔌 Using host port: 10000 -> container: 10000
🌐 Open: http://localhost:10000
============================================================

📦 Running workspace in foreground.
👉 Stop with Ctrl+C. The container will be removed (--rm) when stop.
👉 To open an interactive shell instead: 'workspace.sh -- bash'

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
-e 'WS_RUNMODE=FOREGROUND' \
-e 'WS_VARIANT_TAG=container' \
-e 'WS_VERBOSE=false' \
-e 'WS_VERSION_TAG=${VERSION}' \
-e 'WS_WORKSPACE_PATH=${HERE}' \
-e 'WS_WORKSPACE_PORT=NEXT' \
-e 'WS_HAS_NOTEBOOK=false' \
-e 'WS_HAS_VSCODE=false' \
-e 'WS_HAS_DESKTOP=false' \
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
