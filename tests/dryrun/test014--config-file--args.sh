#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
PWD=$(pwd)

HERE="$PWD"
VERSION="$(cat ../../version.txt)"

function realpath() {
  local target="$1"
  (
    if [ -d "$target" ]; then
      cd -- "$target" 2>/dev/null || { printf '%s\n' "$target"; exit 0; }
      pwd -P
    else
      local dir base
      dir=$(dirname -- "$target")   || { printf '%s\n' "$target"; exit 0; }
      base=$(basename -- "$target") || { printf '%s\n' "$target"; exit 0; }
      cd -- "$dir" 2>/dev/null      || { printf '%s\n' "$target"; exit 0; }
      printf '%s/%s\n' "$(pwd -P)" "$base"
    fi
  )
}


ACTUAL=$(../../workspace.sh --verbose --dryrun | grep -E '^[A-Z_]+:' | sort)

EXPECT="\
ARGS:  \"--verbose\" \"--dryrun\"
BUILD_ARGS: 
CMDS:       
CONFIG_FILE:    ./ws--config.sh (set: false)
CONTAINER_ENV_FILE: 
CONTAINER_NAME: dryrun
DAEMON:         false
DIND:           false
DOCKER_FILE:    
DO_PULL:        false
DRYRUN:         true
HOST_GID:       $HOST_GID
HOST_PORT:      10000
HOST_UID:       $HOST_UID
IMAGE_MODE:     PREBUILT
IMAGE_NAME:     nawaman/workspace:ide-codeserver-$VERSION
KEEPALIVE:      false
LOCAL_BUILD:    false
PORT_GENERATED: true
PREBUILD_REPO:  nawaman/workspace
RUN_ARGS:   
SCRIPT_DIR:     $(realpath "$HERE/../..")
SCRIPT_NAME:    workspace.sh
VARIANT:        ide-codeserver
VERSION:        $VERSION
WORKSPACE_PATH: $HERE
WORKSPACE_PORT: NEXT
WS_VERSION:     $VERSION"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  echo "✅ Match - Expected default variables"
else
  echo "❌ Differ - Expected default variables"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi

cat > test--.env <<EOF
EOF

cat > test--config.sh <<EOF
ARGS+=(
  "--daemon"
  "--dind"
  "--dockerfile" "test--config.sh"
  "--dryrun"
  "--env-file" "test--.env"
  "--keep-alive"
  "--name" "test-container"
  "--pull"
  "--variant" "codeserver"
  "--verbose"
  "--version" "$VERSION"
  "-p" "10005"                        # Remider : -p is direct to docker run and not part of workspace.
)
EOF


ACTUAL=$(../../workspace.sh --config test--config.sh | grep -E '^[A-Z_]+:' | sort)

EXPECT="\
ARGS:  \"--daemon\" \"--dind\" \"--dockerfile\" \"test--config.sh\" \"--dryrun\" \"--env-file\" \"test--.env\" \"--keep-alive\" \"--name\" \"test-container\" \"--pull\" \"--variant\" \"codeserver\" \"--verbose\" \"--version\" \"$VERSION\" \"-p\" \"10005\" \"--config\" \"test--config.sh\"
BUILD_ARGS: 
CMDS:       
CONFIG_FILE:    test--config.sh (set: true)
CONTAINER_ENV_FILE: test--.env
CONTAINER_NAME: test-container
DAEMON:         true
DIND:           true
DOCKER_FILE:    test--config.sh
DO_PULL:        true
DRYRUN:         true
HOST_GID:       $HOST_GID
HOST_PORT:      10000
HOST_UID:       $HOST_UID
IMAGE_MODE:     LOCAL-BUILD
IMAGE_NAME:     workspace-local:dryrun-ide-codeserver-$VERSION
KEEPALIVE:      true
LOCAL_BUILD:    true
PORT_GENERATED: true
PREBUILD_REPO:  nawaman/workspace
RUN_ARGS:    \"-p\" \"10005\"
SCRIPT_DIR:     $(realpath "$HERE/../..")
SCRIPT_NAME:    workspace.sh
VARIANT:        ide-codeserver
VERSION:        $VERSION
WORKSPACE_PATH: $HERE
WORKSPACE_PORT: NEXT
WS_VERSION:     $VERSION"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  echo "✅ Match - Override variables"
else
  echo "❌ Differ - Override variables"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
