#!/bin/bash
# VERSION: 0.2.0--rc
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

Main() {
  SCRIPT_NAME="$(basename "$0")"
  SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
  LIB_DIR=${SCRIPT_DIR}/libs
  PREBUILD_REPO="nawaman/workspace"
  FILE_NOT_USED=none

  DRYRUN=${DRYRUN:-false}
  VERBOSE=${VERBOSE:-false}
  CONFIG_FILE=${CONFIG_FILE:-./ws--config.sh}

  HOST_UID="${HOST_UID:-$(id -u)}"
  HOST_GID="${HOST_GID:-$(id -g)}"
  WORKSPACE_PATH="${WORKSPACE_PATH:-$PWD}"
  PROJECT_NAME="$(project_name "${WORKSPACE_PATH}")"

  DOCKER_FILE="${DOCKER_FILE:-}"
  IMAGE_NAME="${IMAGE_NAME:-}"
  VARIANT=${VARIANT:-container}
  VERSION=${VERSION:-latest}

  DO_PULL=${DO_PULL:-false}

  CONTAINER_NAME="${CONTAINER_NAME:-${PROJECT_NAME}}"
  DAEMON=${DAEMON:-false}
  WORKSPACE_PORT="${WORKSPACE_PORT:-10000}"

  CONTAINER_ENV_FILE=${CONTAINER_ENV_FILE:-}

  DIND=${DIND:-false}

  ARGS=("$@")
  COMMON_ARGS=()
  BUILD_ARGS=()
  RUN_ARGS=()
  CMDS=( )

  SET_CONFIG_FILE=false

  IMAGE_NAME="${IMAGE_NAME:-}"
  DOCKER_FILE="${DOCKER_FILE:-}"
  WORKSPACE_PATH="${WORKSPACE_PATH:-}"

  IMAGE_MODE="${IMAGE_MODE:-}"
  LOCAL_BUILD=false


  PopulateArgs
  ParseArgs "${ARGS[@]}"
  ValidateVariant

  EnsureDockerImage
  ApplyEnvFile
  PortDetermination
  ShowDebugBanner

  SetupDind

  PrepareCommonArgs
  PrepareTtyArgs

  if   $DAEMON;                 then RunAsDaemon
  elif [[ ${#CMDS[@]} -eq 0 ]]; then RunAsForground
  else                               RunAsCommand
  fi
}


#== FUNCTIONS ==================================================================

function args_to_string() {
  for arg in "$@"; do
    printf ' "%s"' "$arg"
  done
  echo
}

function default_file_if_exists() {
  local current="${1:-}"
  local candidate="${2:-}"
  local not_used="${3:-}"

  # If current is empty (or equals the special "not used" token), and candidate exists → pick candidate
  if [[ -z "$current" || ( -n "$not_used" && "$current" == "$not_used" ) ]] && \
     [[ -n "$candidate" && -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  # Otherwise keep current (even if nonexistent — caller decides what to do)
  printf '%s\n' "${current}"
  return 0
}

function is_port_free() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$p )" 2>/dev/null | grep -q ":$p"
  elif command -v lsof >/dev/null 2>&1; then
    ! lsof -iTCP:"$p" -sTCP:LISTEN -Pn 2>/dev/null | grep -q .
  else
    ! (command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$p" >/dev/null 2>&1)
  fi
}

function parse_args_file() {
  local f="${1:-}"

  # No file specified → no-op
  if [[ -z "$f" || "$f" == "none" ]]; then
    return 0
  fi

  # File must exist
  if [[ ! -f "$f" ]]; then
    echo "Error: '$f' is not a file" >&2
    return 1
  fi

  # Normalize CRLF and skip blanks/comments; echo each line as-is
  # so the caller can do: while read -r line; do ...; done < <(parse_args_file "$f")
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    printf '%s\n' "$line"
  done < <(sed $'s/\r$//' "$f")
}

function project_name() {
  WS_PATH=$(readlink -f "${1:-$PWD}")
  PROJECT="$(basename "${WS_PATH}")"
  PROJECT="$(printf '%s' "$PROJECT" | tr '[:upper:] ' '[:lower:]-' | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//')"
  [[ -z "$PROJECT" ]] && PROJECT="workspace"
  echo "${PROJECT}"
}

function require_arg() {
  opt="$1"
  val="$2"
  if [[ -z "$val" || "$val" == --* ]]; then
      echo "Error: $opt requires a value" >&2
      exit 1
  fi
}

function strip_network_flags() {
  skip_next=false
  for arg in "$@"; do
    if $skip_next; then
      skip_next=false
      continue
    fi
    case "$arg" in
      --network|--net)
        skip_next=true ;;              # drop this and the *next* token
      --network=*|--net=*)
        ;;                             # drop this single token
      *)
        printf '%s\n' "$arg" ;;
    esac
  done
}

#== PROCEDURES ==================================================================

ApplyEnvFile() {
  # If VAR has no value and default file exists, use the default.
  if [[ -z "${CONTAINER_ENV_FILE}" ]] && [[ -f "${WORKSPACE_PATH:-.}/.env" ]]; then
    CONTAINER_ENV_FILE="${WORKSPACE_PATH:-.}/.env"
  fi
  if [[ -n "${CONTAINER_ENV_FILE}" ]] && [[ "$CONTAINER_ENV_FILE" != "$FILE_NOT_USED" ]]; then
    if [[ ! -f "${CONTAINER_ENV_FILE}" ]]; then
      echo "Container ENV file most be a file: ${CONTAINER_ENV_FILE}" >&2
    fi
    COMMON_ARGS+=(--env-file "$CONTAINER_ENV_FILE")
  fi
}

DockerBuild() {
  # Print the command if dry-run or verbose
  if [[ "${DRYRUN:-false}" == true || "${VERBOSE:-false}" == true ]]; then
    PrintCmd docker build "$@"
  fi
  # Actually run unless dry-run
  if [[ "${DRYRUN:-false}" != true ]]; then
    # TODO -- find a good way to let user control : --progress=plain --no-cache
    command docker build "$@"
    return $?   # propagate exit code
  fi
}

DockerRun() {
  # Print the command if dry-run or verbose
  if [[ "${DRYRUN:-false}" == "true" || "${VERBOSE:-false}" == "true" ]]; then
    PrintCmd docker run "$@"
    echo ""
  fi
  # Actually run unless dry-run
  if [[ "${DRYRUN:-false}" != "true" ]]; then
    command docker run "$@"
    return $?   # propagate exit code
  fi
}

EnsureDockerImage() {
  if [[ -z "$IMAGE_MODE" ]]; then
    if [[ -d "$DOCKER_FILE" && -f "$DOCKER_FILE/Dockerfile" ]]; then
      DOCKER_FILE="$DOCKER_FILE/Dockerfile"
    elif [[ -z "$DOCKER_FILE" && -d "$WORKSPACE_PATH" && -f "$WORKSPACE_PATH/Dockerfile" ]]; then
      DOCKER_FILE="$WORKSPACE_PATH/Dockerfile"
    fi

    if [[ -n "${DOCKER_FILE:-}" ]]; then
      if [[ ! -f "$DOCKER_FILE" ]]; then
        echo "DOCKER_FILE ($DOCKER_FILE) is not a file." >&2
        return 1
      fi
      IMAGE_MODE="LOCAL-BUILD"
    fi
  else
    IMAGE_MODE="CUSTOM-BUILD"
  fi

  [[ "$IMAGE_MODE" == "LOCAL-BUILD" ]] && LOCAL_BUILD=true || LOCAL_BUILD=false

  # There are three mode of image selection:
  #   - Direction selection: IMAGE_NAME is given.
  #   - Local build:
  #     - ${DOCKER_FILE}               is a file (assume to be Dockerfile)
  #     - ${DOCKER_FILE}/Dockerfile    is a file (assume to be Dockerfile)
  #     - ${WORKSPACE_PATH}/Dockerfile is a file (assume to be Dockerfile)
  #   - Pre-built: use VARIANT and VERSION to select the pre-built

  if [[ -z "${IMAGE_NAME}" ]] ; then
    # -- Local --
    if [[ "${LOCAL_BUILD}" == "true" ]] ; then
      IMAGE_NAME="workspace-local:${PROJECT_NAME}"
      if $VERBOSE ; then
        echo ""
        echo "Build local image: $IMAGE_NAME"
      fi
      DockerBuild \
        -f "$DOCKER_FILE" \
        -t "$IMAGE_NAME"  \
        --build-arg VARIANT_TAG="${VARIANT}" \
        --build-arg VERSION_TAG="${VERSION}" \
        "${BUILD_ARGS[@]}" \
        "${WORKSPACE_PATH}"
    else
      # Construct the full image name.
      IMAGE_NAME="${PREBUILD_REPO}:${VARIANT}-${VERSION}"

      if $DO_PULL; then
        $VERBOSE && echo "Pulling image (forced): $IMAGE_NAME"
        if ! output=$(docker pull "$IMAGE_NAME" 2>&1); then
          echo "Error: failed to pull '$IMAGE_NAME':"
          echo "$output" >&2
          exit 1
        fi
        $VERBOSE && { echo "$output"; echo; }
      elif ! $DRYRUN && ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        $VERBOSE && echo "Image not found locally. Pulling: $IMAGE_NAME"
        if ! output=$(docker pull "$IMAGE_NAME" 2>&1); then
          echo "Error: failed to pull '$IMAGE_NAME':"
          echo "$output" >&2
          exit 1
        fi
        $VERBOSE && { echo "$output"; echo; }
      fi
    fi
  fi  # else => Custom image

  # Ensure the image exists.
  if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Error: image '$IMAGE_NAME' not available locally. Try '--pull'." >&2
    exit 1
  fi
}

ValidateVariant() {
  case "${VARIANT}" in
    container|notebook|codeserver|desktop-xfce|desktop-kde|desktop-lxqt) ;;
    xfce|kde|lxqt) VARIANT="desktop-${VARIANT}" ;;
    *) echo "Error: unknown --variant '$VARIANT' (expected: container|notebook|codeserver)"; exit 1 ;;
  esac
}

ParseArgs() {
  parsing_cmds=false
  while [[ $# -gt 0 ]]; do
    if [[ "$parsing_cmds" == "true" ]]; then
      CMDS+=("$1")
      shift
    else
      case $1 in
        --dryrun)   DRYRUN=true  ; shift  ;;
        --verbose)  VERBOSE=true ; shift  ;;
        --pull)     DO_PULL=true ; shift  ;;
        --daemon)   DAEMON=true  ; shift  ;;
        --help)     ShowHelp     ; exit 0 ;;

        --dind)     DIND=true    ; shift ;;

        # General
        --config)     [[ -n "${2:-}" ]] && { CONFIG_FILE="$2"    ; shift 2; } || { echo "Error: --config requires a path";      exit 1; } ;;
        --workspace)  [[ -n "${2:-}" ]] && { WORKSPACE_PATH="$2" ; shift 2; } || { echo "Error: --workspace requires a path";   exit 1; } ;;

        # Image selection
        --image)       [[ -n "${2:-}" ]] && { IMAGE_NAME="$2"   ; shift 2; } || { echo "Error: --image requires a path";       exit 1; } ;;
        --variant)     [[ -n "${2:-}" ]] && { VARIANT="$2"      ; shift 2; } || { echo "Error: --variant requires a value";    exit 1; } ;;
        --version)     [[ -n "${2:-}" ]] && { VERSION="$2"      ; shift 2; } || { echo "Error: --version requires a value";    exit 1; } ;;
        --dockerfile)  [[ -n "${2:-}" ]] && { DOCKER_FILE="$2"  ; shift 2; } || { echo "Error: --dockerfile requires a path";  exit 1; } ;;

        # Build
        --build-arg)        [[ -n "${2:-}" ]] && { BUILD_ARGS+=(--build-arg "$2") ; shift 2; } || { echo "Error: --build-arg requires a value";  exit 1; } ;;

        # Run
        --name)           [[ -n "${2:-}" ]] && { CONTAINER_NAME="$2"        ; shift 2; } || { echo "Error: --name requires a value";       exit 1; } ;;
        --port)           [[ -n "${2:-}" ]] && { WORKSPACE_PORT="$2"        ; shift 2; } || { echo "Error: --port requires a value";       exit 1; } ;;
        --env-file)       [[ -n "${2:-}" ]] && { CONTAINER_ENV_FILE="$2"    ; shift 2; } || { echo "Error: --env-file requires a path";    exit 1; } ;;
        --)               parsing_cmds=true ; shift ;;
        *)                RUN_ARGS+=("$1") ;  shift ;;
      esac
    fi
  done
}

PopulateArgs() {
  local -a PARAMETERS_ARGS CONFIG_ARGS
  local -i i

  # --- First pass: read flags from initial ARGS (assumes ARGS is set as an array)
  for (( i=0; i<${#ARGS[@]}; i++ )); do
    case "${ARGS[i]}" in
      --verbose) VERBOSE=true ;;
      --config)
        require_arg "--config" "${ARGS[i+1]:-}"
        CONFIG_FILE="${ARGS[i+1]}"
        SET_CONFIG_FILE=true
        ((++i))
        ;;
    esac
  done

  PARAMETERS_ARGS=("${ARGS[@]}")
  unset ARGS   # from here on, don't expand ${ARGS[@]} unless you guard it

  # --- Load config (arrays won't export with set -a, but harmless)
  if [[ -n "${CONFIG_FILE:-}" && -f "${CONFIG_FILE}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    set +a
  fi

  # Pull ARGS from config if it exists *and* is an array; otherwise empty.
  if declare -p ARGS &>/dev/null && declare -p ARGS 2>/dev/null | grep -q 'declare \-a'; then
    CONFIG_ARGS=("${ARGS[@]}")
  else
    CONFIG_ARGS=()
  fi

  # Merge: config first, then original parameters
  ARGS=("${CONFIG_ARGS[@]}" "${PARAMETERS_ARGS[@]}")

  # --- Reprocess after merge
  for (( i=0; i<${#ARGS[@]}; i++ )); do
    case "${ARGS[i]}" in
      --verbose)    VERBOSE=true ;;
      --workspace)
        require_arg "--workspace" "${ARGS[i+1]:-}"
        WORKSPACE_PATH="${ARGS[i+1]}"
        ((++i))
        ;;
      --dockerfile)
        require_arg "--dockerfile" "${ARGS[i+1]:-}"
        DOCKER_FILE="${ARGS[i+1]}"
        ((++i))
        ;;
    esac
  done

  # Only print when VERBOSE is explicitly true; avoid nounset with default.
  if [[ "${VERBOSE:-false}" == "true" ]]; then
    echo -n "ARGS: "
    args_to_string "${ARGS[@]}"
  fi
}

PortBanner() {
  port="${1:?host port required}"
  cat <<EOF

============================================================
🚀 WORKSPACE PORT SELECTED
============================================================
$(printf '🔌 Using host port: \033[1;32m%s\033[0m -> container: \033[1;34m10000\033[0m\n' "$port")
🌐 Open: http://localhost:${port}
============================================================

EOF
}

PortDetermination() {
  # Track whether port was auto-generated
  PORT_GENERATED=false

  # Resolve WORKSPACE_PORT into a concrete host port
  HOST_PORT="${WORKSPACE_PORT}"
  UPPER_PORT="${HOST_PORT^^}"

  if [[ "$UPPER_PORT" == "RANDOM" ]]; then
    for _ in $(seq 1 200); do
      cand=$(( (RANDOM % (65535 - 10000)) + 10001 ))
      if is_port_free "$cand"; then
        HOST_PORT="$cand"
        PORT_GENERATED=true
        break
      fi
    done
    if [[ "$PORT_GENERATED" != "true" ]]; then
      echo "Error: unable to find a free RANDOM port above 10000." >&2
      exit 1
    fi
  elif [[ "$UPPER_PORT" == "NEXT" ]]; then
    cand=10000
    while [[ "$cand" -le 65535 ]]; do
      if is_port_free "$cand"; then
        HOST_PORT="$cand"
        PORT_GENERATED=true
        break
      fi
      cand=$((cand + 1))
    done
    if [[ "$PORT_GENERATED" != "true" ]]; then
      echo "Error: unable to find the NEXT free port above 10000." >&2
      exit 1
    fi
  else
    # Ensure numeric if not RANDOM/NEXT
    if ! [[ "$HOST_PORT" =~ ^[0-9]+$ ]]; then
      echo "Error: WORKSPACE_PORT/--port must be a number, 'RANDOM', or 'NEXT' (got '$HOST_PORT')." >&2
      exit 1
    fi
  fi

  # Print banner only if (auto-generated OR VERBOSE) AND no CMDS
  if [[ ( "$PORT_GENERATED" == "true" || "$VERBOSE" == "true" ) && ${#CMDS[@]} -eq 0 ]]; then
    PortBanner "$HOST_PORT"
  fi
}

PrepareCommonArgs() {
  COMMON_ARGS+=(
    --name "$CONTAINER_NAME"
    -e HOST_UID="$HOST_UID"
    -e HOST_GID="$HOST_GID"
    -v "$WORKSPACE_PATH":"/home/coder/workspace"
    -w "/home/coder/workspace"
    -p "${HOST_PORT:-10000}:10000"

    # Metadata
    -e "WS_DAEMON=${DAEMON}"
    -e "WS_IMAGE_NAME=${IMAGE_NAME}"
    -e "WS_VARIANT_TAG=${VARIANT}"
    -e "WS_VERSION_TAG=${VERSION}"
    -e "WS_CONTAINER_NAME=${CONTAINER_NAME}"
    -e "WS_WORKSPACE_PATH=${WORKSPACE_PATH}"
    -e "WS_WORKSPACE_PORT=${WORKSPACE_PORT}"
  )

  if [[ "$DO_PULL" == false ]]; then
    COMMON_ARGS+=( "--pull=never" )
  fi
}

PrepareTtyArgs() {
  TTY_ARGS="-i"
  if [ -t 0 ] && [ -t 1 ]; then TTY_ARGS="-it"; fi
}

PrintCmd() {
  printf ''
  for a in "$@"; do
    if [[ "$a" =~ ^[A-Za-z0-9_./:-]+$ ]]; then
      printf '%s ' "$a"
    else
      q=${a//\'/\'\\\'\'}
      printf "'%s' " "$q"
    fi
  done
  printf '\n'
}

RunAsCommand() {
  # Foreground with explicit command
  USER_CMDS="${CMDS[*]}"
  DockerRun --rm "$TTY_ARGS" "${COMMON_ARGS[@]}" "${RUN_ARGS[@]}" "$IMAGE_NAME" bash -lc "$USER_CMDS"

  # Foreground-with-command cleanup for DinD
  if [[ "$DIND" == "true" ]]; then
    command docker stop "$DIND_NAME" >/dev/null 2>&1 || true
    if [[ "${CREATED_DIND_NET}" == "true" ]]; then
      command docker network rm "$DIND_NET" >/dev/null 2>&1 || true
    fi
  fi
}

RunAsDaemon() {
  if [[ ${#CMDS[@]} -ne 0 ]]; then
    echo "Running command in daemon mode is not allowed: "${CMDS[@]} >&2
    exit 1
  fi

  # Detached: no TTY args
  echo "📦 Running workspace in daemon mode."
  echo "👉 Stop with '${SCRIPT_NAME} -- exit'. The container will be removed (--rm) when stop."
  echo "👉 Visit 'http://localhost:${WORKSPACE_PORT}'"
  echo "👉 To open an interactive shell instead: ${SCRIPT_NAME} -- bash"
  echo -n "👉 Container ID: "
  if [[ ${DRYRUN} ]]; then echo "<--dryrun-->" ; echo ""; fi

  DockerRun -d "${COMMON_ARGS[@]}" "${RUN_ARGS[@]}" "$IMAGE_NAME"

  # If DinD is enabled in daemon mode, leave sidecar running but inform user how to stop it
  if [[ "$DIND" == "true" ]]; then
    echo "🔧 DinD sidecar running: $DIND_NAME (network: $DIND_NET)"
    echo "   Stop with:  docker stop $DIND_NAME && docker network rm $DIND_NET"
  fi
}

RunAsForground() {
  echo "📦 Running workspace in foreground."
  echo "👉 Stop with Ctrl+C. The container will be removed (--rm) when stop."
  echo "👉 To open an interactive shell instead: '${SCRIPT_NAME} -- bash'"
  echo ""
  DockerRun --rm "$TTY_ARGS" "${COMMON_ARGS[@]}"  "${RUN_ARGS[@]}" "$IMAGE_NAME"

  # Foreground cleanup: stop sidecar & network if DinD was used
  if [[ "$DIND" == "true" ]]; then
    command docker stop "$DIND_NAME" >/dev/null 2>&1 || true
    if [[ "${CREATED_DIND_NET}" == "true" ]]; then
      command docker network rm "$DIND_NET" >/dev/null 2>&1 || true
    fi
  fi
}

SetupDind() {
  DIND_NET=""
  DIND_NAME=""
  DOCKER_BIN=""
  CREATED_DIND_NET=false

  if [[ "$DIND" == "true" ]]; then
    # Unique per-instance network + sidecar (always)
    DIND_NET="${CONTAINER_NAME}-${HOST_PORT}-net"
    DIND_NAME="${CONTAINER_NAME}-${HOST_PORT}-dind"

    # Create network if missing (quietly)
    if ! docker network inspect "$DIND_NET" >/dev/null 2>&1; then
      $VERBOSE && echo "Creating network: $DIND_NET"
      if [[ "${DRYRUN:-false}" != "true" ]]; then
        command docker network create "$DIND_NET" >/dev/null
      else
        PrintCmd docker network create "$DIND_NET"
      fi
      CREATED_DIND_NET=true
    fi

    # Start DinD sidecar on our private network (silence ID)
    if ! docker ps --filter "name=^/${DIND_NAME}$" --format '{{.Names}}' | grep -qx "$DIND_NAME"; then
      $VERBOSE && echo "Starting DinD sidecar: $DIND_NAME"
      DockerRun -d --rm --privileged \
        --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        --name "$DIND_NAME" \
        --network "$DIND_NET" \
        -e DOCKER_TLS_CERTDIR= \
        docker:dind >/dev/null
    else
      $VERBOSE && echo "DinD sidecar already running: $DIND_NAME"
    fi

    # Wait until the sidecar daemon is ready (fast loop, ~10s max)
    if [[ "${DRYRUN:-false}" != "true" ]]; then
      $VERBOSE && echo "Waiting for DinD to become ready at tcp://${DIND_NAME}:2375 ..."
      ready=false
      for i in $(seq 1 40); do
        if docker run --rm --network "$DIND_NET" docker:cli \
            -H "tcp://${DIND_NAME}:2375" version >/dev/null 2>&1; then
          ready=true; break
        fi
        sleep 0.25
      done
      if [[ "$ready" != true ]]; then
        echo "⚠️  DinD did not become ready. Check: docker logs $DIND_NAME" >&2
      fi
    fi

    # Remove any user-provided --network from RUN_ARGS to avoid duplication
    mapfile -t RUN_ARGS < <(strip_network_flags "${RUN_ARGS[@]}")

    # Wire main container to DinD network + endpoint
    COMMON_ARGS+=( --network "$DIND_NET" -e "DOCKER_HOST=tcp://${DIND_NAME}:2375" )

    # Mount host docker CLI binary if present (so your image need not include it)
    if DOCKER_BIN="$(command -v docker 2>/dev/null)"; then
      # Resolve to absolute path for safety
      if command -v readlink >/dev/null 2>&1; then
        DOCKER_BIN="$(readlink -f "$DOCKER_BIN" || echo "$DOCKER_BIN")"
      fi
      COMMON_ARGS+=( -v "${DOCKER_BIN}:/usr/bin/docker:ro" )
    else
      $VERBOSE && echo "⚠️  docker CLI not found on host; not mounting into container."
    fi
  fi
}

ShowDebugBanner() {
  if [[ "${VERBOSE}" == "true" ]] ; then
    echo ""
    echo "CONTAINER_NAME: $CONTAINER_NAME"
    echo "DAEMON:         $DAEMON"
    echo "DOCKER_FILE:    $DOCKER_FILE"
    echo "DRYRUN:         $DRYRUN"
    echo "HOST_UID:       $HOST_UID"
    echo "HOST_GID:       $HOST_GID"
    echo "HOST_PORT:      $HOST_PORT" 
    echo "IMAGE_NAME:     $IMAGE_NAME"
    echo "IMAGE_MODE:     $IMAGE_MODE"
    echo "WORKSPACE_PATH: $WORKSPACE_PATH"
    echo "WORKSPACE_PORT: $WORKSPACE_PORT"
    echo "DIND:           $DIND"
    echo ""
    echo "CONTAINER_ENV_FILE: $CONTAINER_ENV_FILE"
    echo ""
    echo "BUILD_ARGS: "$(args_to_string "${BUILD_ARGS[@]}")
    echo "RUN_ARGS:   "$(args_to_string "${RUN_ARGS[@]}")
    echo ""
    echo "CMDS: "$(args_to_string "${CMDS[@]}")
    echo ""

    if [[ ${#BUILD_ARGS[@]} -gt 0 ]] && [[ "${LOCAL_BUILD}" == "false" ]] && [[ "${VERBOSE}" == "true" ]]; then
      echo "⚠️  Warning: BUILD_ARGS provided, but no build is being performed (using prebuilt image)." >&2
      echo ""
    fi
  fi
}

ShowHelp() {
  local sname="${SCRIPT_NAME:-$(basename "$0")}"

  cat <<EOF
$sname — launch a Docker-based workspace

USAGE:
  $sname [options] [--] [command ...]
  $sname --help

GENERAL:
  --help                 Show this help and exit
  --verbose              Print extra debugging information
  --dryrun               Print the docker commands but do not execute them
  --pull                 Force pulling the image (when using prebuilt images)
  --daemon               Run the workspace container in the background
  --dind                 Enable Docker-in-Docker sidecar and wire DOCKER_HOST
  --config <file>        Load defaults from a config shell file
  --workspace <path>     Host workspace path to mount at /home/coder/workspace

IMAGE SELECTION (choose one path):
  --image <name>         Use an existing image (e.g., repo/name:tag)
  --dockerfile <path>    Build locally from Dockerfile (file or dir)
  --variant <name>       Prebuilt variant: container|notebook|codeserver|desktop-{xfce,kde,lxqt}
  --version <tag>        Prebuilt version tag (default: latest)

BUILD OPTIONS (when building):
  --build-arg <KEY=VAL>  Add a build-arg (repeatable)

RUNTIME OPTIONS:
  --name <container>     Container name (default: project name)
  --port <n|RANDOM|NEXT> Map host port -> container 10000
  --env-file <file>      Pass an --env-file to docker run

COMMANDS:
  Everything after '--' is executed inside the container instead of starting
  the default workspace service. Example: '$sname -- bash -lc "echo hi"'

NOTES:
  - RANDOM/NEXT for --port will auto-pick a free host port >= 10000.
  - With --dind, a sidecar 'docker:dind' runs on a private network and the
    main container gets DOCKER_HOST=tcp://<sidecar>:2375.
  - In daemon mode, do not pass commands after '--'.

EXAMPLES:
  # Prebuilt, foreground
  $sname --variant container --version latest --workspace /path/to/ws

  # Local build from Dockerfile in workspace
  $sname --dockerfile ./Dockerfile --workspace . --build-arg FOO=bar

  # Daemon mode with random port
  $sname --daemon --variant codeserver --port RANDOM

  # Run a one-off command inside the image
  $sname --image my/image:tag -- -- env | sort
EOF
}


Main "$@"
