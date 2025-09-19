#!/bin/bash
set -euo pipefail

#========== CONSTANTS ============

SCRIPT_NAME="$(basename "$0")"
PREBUILD_REPO="nawaman/workspace"
FILE_NOT_USED=none

#========== FUNCTIONS ============

function abs_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd)" "$(basename "$1")")
  fi
}

function docker_build() {
  # Print the command if dry-run or verbose
  if [[ "${DRYRUN:-false}" == true || "${VERBOSE:-false}" == true ]]; then
    print_cmd docker build "$@"
  fi
  # Actually run unless dry-run
  if [[ "${DRYRUN:-false}" != true ]]; then
    command docker build "$@"
    return $?   # propagate exit code
  fi
}

function docker_run() {
  # Print the command if dry-run or verbose
  if [[ "${DRYRUN:-false}" == "true" || "${VERBOSE:-false}" == "true" ]]; then
    print_cmd docker run "$@"
    echo ""
  fi
  # Actually run unless dry-run
  if [[ "${DRYRUN:-false}" != "true" ]]; then
    command docker run "$@"
    return $?   # propagate exit code
  fi
}

function print_cmd() {
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

function print_args() {
  for arg in "$@"; do
    printf ' "%s"' "$arg"
  done
  echo
}

function project_name() {
  WS_PATH=$(readlink -f "${1:-$PWD}")
  PROJECT="$(basename "${WS_PATH}")"
  PROJECT="$(printf '%s' "$PROJECT" | tr '[:upper:] ' '[:lower:]-' | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//')"
  [[ -z "$PROJECT" ]] && PROJECT="workspace"
  echo "${PROJECT}"
}


#=========== DEFAULTS ============

DRYRUN=${DRYRUN:-false}
VERBOSE=${VERBOSE:-false}
CONFIG_FILE=${CONFIG_FILE:-./ws-config.env}

HOST_UID="${HOST_UID:-$(id -u)}"
HOST_GID="${HOST_GID:-$(id -g)}"
WORKSPACE_PATH="${WORKSPACE_PATH:-$PWD}"
PROJECT_NAME="$(project_name ${WORKSPACE_PATH})"

DOCKER_FILE="${DOCKER_FILE:-}"
IMAGE_NAME="${IMAGE_NAME:-}"
VARIANT=${VARIANT:-container}
VERSION=${VERSION:-latest}

DO_PULL=${DO_PULL:-false}

CONTAINER_NAME="${CONTAINER_NAME:-${PROJECT_NAME}}"
DAEMON=${DAEMON:-false}
WORKSPACE_PORT="${WORKSPACE_PORT:-10000}"

DOCKER_BUILD_ARGS_FILE=${DOCKER_BUILD_ARGS_FILE:-}
DOCKER_RUN_ARGS_FILE=${DOCKER_RUN_ARGS_FILE:-}

CONTAINER_ENV_FILE=${CONTAINER_ENV_FILE:-}

COMMON_ARGS=()
BUILD_ARGS=()
RUN_ARGS=()
CMDS=( )


#============ CONFIGS =============

function require_arg() {
  local opt="$1"
  local val="$2"
  if [[ -z "$val" || "$val" == --* ]]; then
    echo "Error: $opt requires a value" >&2
    exit 1
  fi
}

ARGS=("$@")
SET_CONFIG_FILE=false
for (( i=0; i<${#ARGS[@]}; i++ )); do
  case "${ARGS[i]}" in
    --verbose)    VERBOSE=true ;;
    --config)     require_arg "--config"     "${ARGS[i+1]:-}" ; CONFIG_FILE="${ARGS[i+1]}"    ; SET_CONFIG_FILE=true ; ((++i)) ;;
    --workspace)  require_arg "--workspace"  "${ARGS[i+1]:-}" ; WORKSPACE_PATH="${ARGS[i+1]}" ;                        ((++i)) ;;
    --dockerfile) require_arg "--dockerfile" "${ARGS[i+1]:-}" ; DOCKER_FILE="${ARGS[i+1]}" ;                           ((++i)) ;;
  esac
done


#-- Determine the IMAGE_NAME --------------------
LOCAL_BUILD=false
IMAGE_MODE=PRE-BUILD
if [[ -z "${IMAGE_NAME}" ]] ; then
  # Normalize the path to file .... 
  if [[ -d "${DOCKER_FILE}" ]] && [[ -f "${DOCKER_FILE}/Dockerfile" ]]; then
    DOCKER_FILE="${DOCKER_FILE}/Dockerfile"
  elif [[ -z "${DOCKER_FILE}" ]] && [[ -d "${WORKSPACE_PATH}" ]] && [[ -f "${WORKSPACE_PATH}/Dockerfile" ]]; then
    DOCKER_FILE="${WORKSPACE_PATH}/Dockerfile"
  fi

  # If DOCKER_FILE is given at this point, it is expected to be a file.
  if [[ "${DOCKER_FILE:-}" != "" ]]; then
    # -- Local Build --

    if [[ ! -f "${DOCKER_FILE}" ]]; then
      echo "DOCKER_FILE (${DOCKER_FILE}) is not a file." >&2
      exit 1
    fi

    LOCAL_BUILD=true
    IMAGE_MODE=LOCAL-BUILD
  fi
else
  IMAGE_MODE=CUSTOM-BUILD
fi


#========== ARGUMENTS ============

# Usage:
#   load_args_file path/to/file       RUN_ARGS
#   load_args_file path/to/other_file BUILD_ARGS
load_args_file() {
  local f="$1" target="$2"
  if [[      "$f" == "$FILE_NOT_USED" ]]; then                                        return 0; fi
  if [[   -z "$f"                     ]]; then                                        return 0; fi
  if [[ ! -f "$f"                     ]]; then echo "Error: '$f' is not a file" >&2 ; return 1; fi
  if [[   -z "$target"                ]]; then                                        return 0; fi
  # shellcheck disable=SC2016
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue   # blank line
    [[ "$line" =~ ^[[:space:]]*# ]] && continue   # comment
    # shellcheck disable=SC2086
    eval "$target+=($line)"
  done < <(sed $'s/\r$//' "$f")
}


# If VAR has no value and default file exists, use the default.
if [[ -z "${DOCKER_BUILD_ARGS_FILE}" ]] && [[ -f "${WORKSPACE_PATH:-.}/ws-docker-build.args" ]]; then
  DOCKER_BUILD_ARGS_FILE="${WORKSPACE_PATH:-.}/ws-docker-build.args"
fi
if [[ -z "${DOCKER_RUN_ARGS_FILE}" ]] && [[ -f "${WORKSPACE_PATH:-.}/ws-docker-run.args" ]]; then
  DOCKER_RUN_ARGS_FILE="${WORKSPACE_PATH:-.}/ws-docker-run.args"
fi

load_args_file "${DOCKER_BUILD_ARGS_FILE}" BUILD_ARGS
load_args_file "${DOCKER_RUN_ARGS_FILE}"   RUN_ARGS


#========== PARAMETERS ============

parsing_cmds=false
while [[ $# -gt 0 ]]; do
  if [[ "$parsing_cmds" == "true" ]]; then
    CMDS+=("$1")
    shift
  else
    case $1 in
      --dryrun)   DRYRUN=true  ; shift ;;
      --verbose)  VERBOSE=true ; shift ;;
      --pull)     DO_PULL=true ; shift ;;
      --daemon)   DAEMON=true  ; shift ;;
      --help)     show_help    ; exit 0 ;;

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
      --build-args-file)  [[ -n "${2:-}" ]] && { DOCKER_BUILD_ARGS_FILE="$2"    ; shift 2; } || { echo "Error: --build-args requires a path";  exit 1; } ;;

      # Run
      --name)           [[ -n "${2:-}" ]] && { CONTAINER_NAME="$2"        ; shift 2; } || { echo "Error: --name requires a value";       exit 1; } ;;
      --run-args-file)  [[ -n "${2:-}" ]] && { DOCKER_RUN_ARGS_FILE="$2"  ; shift 2; } || { echo "Error: --run-args requires a path";    exit 1; } ;;
      --env-file)       [[ -n "${2:-}" ]] && { CONTAINER_ENV_FILE="$2"    ; shift 2; } || { echo "Error: --env-file requires a path";    exit 1; } ;;
      --)               parsing_cmds=true ; shift ;;
      *)                RUN_ARGS+=("$1") ;  shift ;;
    esac
  fi
done


#========== IMAGE ============

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
    docker_build \
      -q \
      -f "$DOCKER_FILE" \
      -t "$IMAGE_NAME"  \
      --build-arg VARIANT_TAG="${VARIANT}" \
      --build-arg VERSION_TAG="${VERSION}" \
      "${BUILD_ARGS[@]}" \
      "${WORKSPACE_PATH}"
  else
    # -- Prebuild --
    case "${VARIANT}" in
      container|notebook|codeserver) ;;
      *) echo "Error: unknown --variant '$VARIANT' (expected: container|notebook|codeserver)"; exit 1 ;;
    esac

    # Construct the full image name.
    IMAGE_NAME="${PREBUILD_REPO}:${VARIANT}-${VERSION}"

    if ! $DRYRUN || $DO_PULL || ! { docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; }; then
      if $VERBOSE ; then
        echo "Pulling image: $IMAGE_NAME"
      fi
      if ! output=$(docker pull "$IMAGE_NAME" 2>&1); then
        echo "Error: failed to pull '$IMAGE_NAME':"
        echo "$output" >&2
        exit 1
      fi
      if $VERBOSE ; then
        echo "$output"
        echo ""
      fi
    fi
  fi
fi  # else => Custom image

# Ensrure the image exists.
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Error: image '$IMAGE_NAME' not available locally. Try '--pull'." >&2
  exit 1
fi


#========== ENV FILE ============

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


#=========== RUN =============

if [[ "${VERBOSE}" == "true" ]] ; then
  echo ""
  echo "CONTAINER_NAME: $CONTAINER_NAME"
  echo "DAEMON:         $DAEMON"
  echo "DOCKER_FILE:    $DOCKER_FILE"
  echo "DRYRUN:         $DRYRUN"
  echo "HOST_UID:       $HOST_UID"
  echo "HOST_GID:       $HOST_GID"
  echo "IMAGE_NAME:     $IMAGE_NAME"
  echo "IMAGE_MODE:     $IMAGE_MODE"
  echo "WORKSPACE_PATH: $WORKSPACE_PATH"
  echo "WORKSPACE_PORT: $WORKSPACE_PORT"
  echo ""
  echo "CONTAINER_ENV_FILE: $CONTAINER_ENV_FILE"
  echo ""
  echo "DOCKER_BUILD_ARGS_FILE: $DOCKER_BUILD_ARGS_FILE"
  echo "DOCKER_RUN_ARGS_FILE:   $DOCKER_RUN_ARGS_FILE"
  echo ""
  echo "BUILD_ARGS: "$(print_args "${BUILD_ARGS[@]}")
  echo "RUN_ARGS:   "$(print_args "${RUN_ARGS[@]}")
  echo ""
  echo "CMDS: "$(print_args "${CMDS[@]}")
  echo ""

  if [[ ${#BUILD_ARGS[@]} -gt 0 ]] && [[ "${LOCAL_BUILD}" == "false" ]] && [[ "${VERBOSE}" == "true" ]]; then
    echo "⚠️  Warning: BUILD_ARGS provided, but no build is being performed (using prebuilt image)." >&2
    echo ""
  fi
fi

# --------- Execute ---------

if ! $DRYRUN; then
  # Clean up any previous container with the same name
  docker rm -f "$CONTAINER_NAME" &>/dev/null || true
fi

COMMON_ARGS+=(
  --name "$CONTAINER_NAME"
  -e HOST_UID="$HOST_UID"
  -e HOST_GID="$HOST_GID"
  -v "$WORKSPACE_PATH":"/home/coder/workspace"
  -w "/home/coder/workspace"
  -p "${WORKSPACE_PORT:-10000}:10000"

  # Metadata
  -e "WS_DAEMON=${DAEMON}"
  -e "WS_IMAGE_NAME=${IMAGE_NAME}"
  -e "WS_CONTAINER_NAME=${CONTAINER_NAME}"
  -e "WS_WORKSPACE_PATH=${WORKSPACE_PATH}"
  -e "WS_WORKSPACE_PORT=${WORKSPACE_PORT}"
)

TTY_ARGS="-i"
if [ -t 0 ] && [ -t 1 ]; then TTY_ARGS="-it"; fi

if $DAEMON; then
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

  docker_run -d "${COMMON_ARGS[@]}" "${RUN_ARGS[@]}" "$IMAGE_NAME"

elif [[ ${#CMDS[@]} -eq 0 ]]; then
  echo "📦 Running workspace in foreground."
  echo "👉 Stop with Ctrl+C. The container will be removed (--rm) when stop."
  echo "👉 To open an interactive shell instead: '${SCRIPT_NAME} -- bash'"
  echo ""
  docker_run --rm "$TTY_ARGS" "${COMMON_ARGS[@]}"  "${RUN_ARGS[@]}" "$IMAGE_NAME"

else
  # Foreground with explicit command
  USER_CMDS="${CMDS[*]}"
  docker_run --rm "$TTY_ARGS" "${COMMON_ARGS[@]}" "${RUN_ARGS[@]}" "$IMAGE_NAME" bash -lc "$USER_CMDS"
fi
