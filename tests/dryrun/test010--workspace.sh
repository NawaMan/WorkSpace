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

# The workspace is set to be non default
WORKSPACE=".."

export TIMEZONE="America/Toronto"

ACTUAL=$(../../workspace.sh --verbose --dryrun --workspace ${WORKSPACE} --variant container -- sleep 1)
ACTUAL=$(printf "%s\n" "$ACTUAL" | tail -n 1)

VERSION="$(cat ../../version.txt)"

# Notice that there is not `-rm`
EXPECT="\
docker run \
-i \
--rm \
--name dryrun \
-e 'HOST_UID=${HOST_UID}' \
-e 'HOST_GID=${HOST_GID}' \
-v ${WORKSPACE}:/home/coder/workspace \
-w /home/coder/workspace \
-p 10000:10000 \
-e 'WS_SETUPS_DIR=/opt/workspace/setups' \
-e 'WS_CONTAINER_NAME=dryrun' \
-e 'WS_DAEMON=false' \
-e 'WS_HOST_PORT=10000' \
-e 'WS_IMAGE_NAME=nawaman/workspace:container-${VERSION}' \
-e 'WS_RUNMODE=COMMAND' \
-e 'WS_VARIANT_TAG=container' \
-e 'WS_VERBOSE=true' \
-e 'WS_VERSION_TAG=${VERSION}' \
-e 'WS_WORKSPACE_PATH=..' \
-e 'WS_WORKSPACE_PORT=NEXT' \
-e 'WS_HAS_NOTEBOOK=false' \
-e 'WS_HAS_VSCODE=false' \
-e 'WS_HAS_DESKTOP=false' \
'--pull=never' \
-e 'TZ=America/Toronto' \
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
