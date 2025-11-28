#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
PWD=$(pwd)

HERE="$PWD"
VERSION="$(cat ../../version.txt)"

# Each entry is WANT_VARIANT:GOT_VARIANT
VARIANTS=(
  "container:container"
  "ide-notebook:ide-notebook"
  "ide-codeserver:ide-codeserver"
  "desktop-xfce:desktop-xfce"
  "desktop-kde:desktop-kde"
  "desktop-lxqt:desktop-lxqt"

  # aliases
  "default:ide-codeserver"
  "ide:ide-codeserver"
  "desktop:desktop-xfce"
  "notebook:ide-notebook"
  "codeserver:ide-codeserver"
  "xfce:desktop-xfce"
  "kde:desktop-kde"
  "lxqt:desktop-lxqt"
)

for entry in "${VARIANTS[@]}"; do
  WANT_VARIANT="${entry%%:*}"
  GOT_VARIANT="${entry#*:}"

  ACTUAL=$(../../workspace.sh --verbose --dryrun --variant "${WANT_VARIANT}" -- sleep 1)
  ACTUAL=$(printf "%s\n" "$ACTUAL" | tail -n 1)

  case "${GOT_VARIANT}" in
    container)      HAS_NOTEBOOK=false ; HAS_VSCODE=false ; HAS_DESKTOP=false ;;
    ide-notebook)   HAS_NOTEBOOK=true  ; HAS_VSCODE=false ; HAS_DESKTOP=false ;;
    ide-codeserver) HAS_NOTEBOOK=true  ; HAS_VSCODE=true  ; HAS_DESKTOP=false ;;
    desktop-*)      HAS_NOTEBOOK=true  ; HAS_VSCODE=true  ; HAS_DESKTOP=true  ;;
    *)              echo "Error: unknown variant '$VARIANT'." >&2 ; exit 1    ;;
  esac

  # Notice that there is not `-rm`
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
-e 'WS_IMAGE_NAME=nawaman/workspace:${GOT_VARIANT}-${VERSION}' \
-e 'WS_RUNMODE=COMMAND' \
-e 'WS_VARIANT_TAG=${GOT_VARIANT}' \
-e 'WS_VERBOSE=true' \
-e 'WS_VERSION_TAG=${VERSION}' \
-e 'WS_WORKSPACE_PATH=${HERE}' \
-e 'WS_WORKSPACE_PORT=10000' \
-e 'WS_HAS_NOTEBOOK=${HAS_NOTEBOOK}' \
-e 'WS_HAS_VSCODE=${HAS_VSCODE}' \
-e 'WS_HAS_DESKTOP=${HAS_DESKTOP}' \
'--pull=never' \
nawaman/workspace:${GOT_VARIANT}-${VERSION} \
bash -lc 'sleep 1' \
"

  if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
    echo "✅ Match: variant '${WANT_VARIANT}' -> '${GOT_VARIANT}'"
  else
    echo "❌ Differ: variant '${WANT_VARIANT}' -> '${GOT_VARIANT}'"
    echo "-------------------------------------------------------------------------------"
    echo "Expected (${WANT_VARIANT} -> ${GOT_VARIANT}):"
    echo "$EXPECT"
    echo "-------------------------------------------------------------------------------"
    echo "Actual:"
    echo "$ACTUAL"
    echo "-------------------------------------------------------------------------------"
    exit 1
  fi
done

echo "✅ All variants and aliases produced the expected docker command."
