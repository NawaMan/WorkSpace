#!/bin/bash

###########################################################
# Example bash script for running things on the container.
###########################################################


set -euo pipefail

# ---------- Defaults ----------
CONTAINER_NAME="${CONTAINER_NAME:-workspace-run}"
WORKSPACE="/home/coder/workspace"

# Respect overrides like docker-compose does, else detect host values
HOST_UID="${HOST_UID:-$(id -u)}"
HOST_GID="${HOST_GID:-$(id -g)}"

SHELL_NAME="bash"

RUN_ARGS=()
CMD=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="nawaman/workspace:codeserver-local"

show_help() {
  cat <<'EOF'
Usage:
  run.sh [OPTIONS]                 # interactive shell (bash)
  run.sh [OPTIONS] -- <command...> # run a command then exit

Options:
  -h, --help       Show this help message
EOF
}

# --------- Parse CLI ---------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --) shift; CMD=("$@"); break ;;
    -*) RUN_ARGS+=("$1"); shift ;;
    *)  echo "Error: unrecognized argument: '$1'"; echo "Use '--' before commands. Try '$0 --help'."; exit 2 ;;
  esac
done

# --------- Ensure image exists ---------
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Image $IMAGE_NAME not found. Building it via build-locally.sh..."
  if [[ ! -x "${SCRIPT_DIR}/build-locally.sh" ]]; then
    echo "Error: build-locally.sh not found or not executable in ${SCRIPT_DIR}" >&2
    exit 1
  fi
  "${SCRIPT_DIR}/build-locally.sh"
fi

# Clean up any previous container with the same name
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

TTY_ARGS="-i"
if [ -t 1 ]; then TTY_ARGS="-it"; fi

COMMON_ARGS=(
  --name "$CONTAINER_NAME"
  -e HOST_UID="$HOST_UID"
  -e HOST_GID="$HOST_GID"
  -e CHOWN_RECURSIVE=1
  -v "$PWD":"$WORKSPACE"     # same bind as docker-compose
  -w "$WORKSPACE"            # same working_dir as docker-compose
  -p 8888:8888
  -p 8080:8080
)

# --------- Run container ---------
if [[ ${#CMD[@]} -eq 0 ]]; then
  exec docker run --rm $TTY_ARGS \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMAGE_NAME"
else
  USER_CMD="${CMD[*]}"
  exec docker run --rm $TTY_ARGS \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMAGE_NAME" \
    "$SHELL_NAME" -lc "$USER_CMD"
fi
