#!/bin/bash
set -euo pipefail

# ---------- Defaults ----------
IMAGE_REPO_DEFAULT="nawaman/workspace"
VARIANT_DEFAULT="container"
VERSION_DEFAULT="latest"

IMAGE_REPO="${IMAGE_REPO:-${IMAGE_REPO_DEFAULT}}"
VARIANT="${VARIANT:-${VARIANT_DEFAULT}}"
VERSION_TAG="${VERSION_TAG:-${VERSION_DEFAULT}}"

IMAGE_TAG="${IMAGE_TAG:-${VARIANT}-${VERSION_TAG}}"
IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"

CONTAINER_NAME="${CONTAINER_NAME:-${VARIANT}-run}"
WORKSPACE="/home/coder/workspace"

# Respect overrides like docker-compose does, else detect host values
HOST_UID="${HOST_UID:-$(id -u)}"
HOST_GID="${HOST_GID:-$(id -g)}"

SHELL_NAME="bash"

DAEMON=false
DO_PULL=false
RUN_ARGS=()
CMDS=()

show_help() {
  cat <<'EOF'
Starting a workspace container.

Usage:
  run-workspace.sh [OPTIONS] [RUN_ARGS]                 # interactive shell
  run-workspace.sh [OPTIONS] [RUN_ARGS] -- <command...> # run a command then exit
  run-workspace.sh [OPTIONS] [RUN_ARGS] --daemon        # run container detached

Options:
  -d, --daemon            Run container detached (background)
      --pull              Pull/refresh the image from registry (also pulls if image missing)
      --variant <name>    Variant prefix        (default: container)
      --version <tag>     Version suffix        (default: latest)
      --name    <name>    Container name        (default: <variant>-run)
  -h, --help              Show this help message

Notes:
  • Bind: . -> /home/coder/workspace; Working dir: /home/coder/workspace
EOF
}

# --------- Parse arguments ---------
parsing_cmds=false

while [[ $# -gt 0 ]]; do
  if [[ "$parsing_cmds" == true ]]; then
    # Everything after '--' goes to CMDS
    CMDS+=("$1")
    shift
  else
    case $1 in
      -d|--daemon) DAEMON=true  ; shift ;;
      --pull)      DO_PULL=true ; shift ;;
      --variant)   [[ -n "$2" ]] && { VARIANT="$2"        ; shift 2; } || { echo "Error: --variant requires a value"; exit 1; } ;;
      --version)   [[ -n "$2" ]] && { VERSION_TAG="$2"    ; shift 2; } || { echo "Error: --version requires a value"; exit 1; } ;;
      --name)      [[ -n "$2" ]] && { CONTAINER_NAME="$2" ; shift 2; } || { echo "Error: --name requires a value";    exit 1; } ;;
      -h|--help)   show_help ; exit 0 ;;
      --)          parsing_cmds=true ; shift ;;
      *)           RUN_ARGS+=("$1")  ; shift ;;
    esac
  fi
done


IMAGE_TAG="${VARIANT}-${VERSION_TAG}"
IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"
CONTAINER_NAME="${CONTAINER_NAME:-${VARIANT}-run}"

# --------- Pull if requested or missing ---------
if $DO_PULL || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Pulling image: $IMAGE_NAME"
  docker pull "$IMAGE_NAME" || { echo "Error: failed to pull '$IMAGE_NAME'." >&2; exit 1; }
fi

# Final check
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Error: image '$IMAGE_NAME' not available locally. Try '--pull'." >&2
  exit 1
fi

# Clean up any previous container with the same name
docker rm -f "$CONTAINER_NAME" &>/dev/null || true

TTY_ARGS="-i"
if [ -t 1 ]; then TTY_ARGS="-it"; fi

COMMON_ARGS=(
  --name "$CONTAINER_NAME"
  -e HOST_UID="$HOST_UID"
  -e HOST_GID="$HOST_GID"
  -e CHOWN_RECURSIVE=1
  -v "$PWD":"$WORKSPACE"
  -w "$WORKSPACE"
)

if [[ "$VARIANT" == "notebook" ]]; then
    COMMON_ARGS+=(-p 8888:8888)
fi
if [[ "$VARIANT" == "codeserver" ]]; then
    COMMON_ARGS+=(-p 8888:8888)
    COMMON_ARGS+=(-p 8080:8080)
fi

# # Display parsed results (for demonstration)
# echo "=== Parsed Arguments ==="
# echo "DAEMON:         $DAEMON"
# echo "DO_PULL:        $DO_PULL"
# echo "VARIANT:        $VARIANT"
# echo "VERSION_TAG:    $VERSION_TAG"
# echo "CONTAINER_NAME: $CONTAINER_NAME"
# echo "RUN_ARGS:       ${RUN_ARGS[*]}"
# echo "CMDS:           ${CMDS[*]}"

if $DAEMON; then
  SHELL_CMD=()
  if [[ "$VARIANT" == "container" ]]; then
      SHELL_CMD=("$SHELL_NAME" -lc "while true; do sleep 3600; done")
  fi

  exec docker run -d \
      "${COMMON_ARGS[@]}" \
      "${RUN_ARGS[@]}" \
      "$IMAGE_NAME" \
      "${SHELL_CMD[@]}"
  
elif [[ ${#CMDS[@]} -eq 0 ]]; then
  exec docker run --rm $TTY_ARGS \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMAGE_NAME"

else
  USER_CMD="${CMDS[*]}"
  exec docker run --rm $TTY_ARGS \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMAGE_NAME" \
    "$SHELL_NAME" -lc "$USER_CMD"
fi
