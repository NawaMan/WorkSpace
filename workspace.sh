#!/bin/bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# ---------- Defaults ----------
IMGREPO="${IMGREPO:-nawaman/workspace}"
VARIANT="${VARIANT-}"
VARIANT_DEFAULT="container"   # CHG: default only when truly needed
VERSION="${VERSION:-latest}"
WORKSPACE="${WORKSPACE:-$PWD}"

# Respect overrides like docker-compose does, else detect host values
HOST_UID="${HOST_UID:-$(id -u)}"
HOST_GID="${HOST_GID:-$(id -g)}"

DAEMON=false
DO_PULL=false
DRYRUN=false

# Separate config files
# Launcher config (sourced): default ./workspace.env (override with --config or $WORKSPACE_CONFIG_FILE)
WORKSPACE_CONFIG_FILE="${WORKSPACE_CONFIG_FILE:-./workspace.env}"   # launcher config (sourced)
CONTAINER_ENV_FILE="${CONTAINER_ENV_FILE:-.env}"                    # passed to docker --env-file (NOT sourced)

# Docker run-args file (NOT sourced); lines are parsed into RUN_ARGS
DOCKER_ARGS_FILE="${DOCKER_ARGS_FILE:-./workspace-docker.args}"
RUN_ARGS=()
CMDS=()

# Capture CLI overrides without applying yet (to preserve precedence)
CLI_VARIANT=""
CLI_VERSION=""
CLI_CONTAINER=""
CLI_CONFIG_FILE=""
CLI_CONTAINER_ENV_FILE=""
CLI_DOCKER_ARGS_FILE=""
CLI_WORKSPACE=""
CLI_DOCKERFILE=""

# holder for args loaded from docker args file
RUN_ARGS_FROM_FILE=()

show_help() {
  cat <<EOF
Starting a workspace container.
More information: https://github.com/NawaMan/WorkSpace

Usage:
  ${SCRIPT_NAME} [OPTIONS] [RUN_ARGS]                 # run workspace (foreground)
  ${SCRIPT_NAME} [OPTIONS] [RUN_ARGS] -- <command...> # run a command then exit
  ${SCRIPT_NAME} [OPTIONS] [RUN_ARGS] --daemon        # run container detached

Options:
  -d, --daemon              Run container detached (background)
      --pull                Pull/refresh the image from registry (also pulls if image missing)
      --variant <name>      Variant prefix        (default: container; see Image selection)
      --version <tag>       Version suffix        (default: latest)
      --name <name>         Container name        (default: <project-folder>)
      --config F            Launcher config file to source (default: ./workspace.env or \$WORKSPACE_CONFIG_FILE)
      --env-file F          Container env file passed to 'docker run --env-file' (default: ./.env or \$CONTAINER_ENV_FILE)
      --docker-args F       File of extra 'docker run' args (default: ./workspace-docker.args or \$DOCKER_ARGS_FILE)ILE)
      --workspace F         The base folder.
      --dockerfile F        Dockerfile to build when no variant provided (default: ./Dockerfile or \$DOCKERFILE)
      --dryrun              Print the docker build/run command(s) and exit (no side effects)
  -h, --help                Show this help message

Notes:
  • Bind: . -> /home/coder/workspace; Working dir: /home/coder/workspace

Configuration:
  • Launcher config (sourced): workspace.env (override with --config or \$WORKSPACE_CONFIG_FILE)
      Keys: IMGNAME, IMGREPO, IMG_TAG, VARIANT, VERSION, CONTAINER, DOCKERFILE,
            HOST_UID, HOST_GID, WORKSPACE_PORT
  • Container env (NOT sourced): .env (or --env-file)
      Typical keys: PASSWORD, JUPYTER_TOKEN, TZ, PROXY, AWS_*, GH_TOKEN, etc.
  • Docker run-args file (NOT sourced): workspace-docker.args (or --docker-args)
      One directive per line (supports quotes); examples:
        -p 127.0.0.1:9000:9000
        -v "\$HOME/.cache/pip:/home/coder/.cache/pip"
        --shm-size 2g
        --add-host "minio.local:127.0.0.1"

  • Image selection:
      - Set IMGNAME to full image (e.g., nawaman/workspace:container-latest), or
      - Set IMGREPO and IMG_TAG (IMG_TAG defaults to VARIANT-VERSION)
      - If NO variant is provided via CLI/config/env and a local Dockerfile exists
        (or --dockerfile points to one), the script BUILDS that Dockerfile and runs it.
        Otherwise it falls back to the default variant: '${VARIANT_DEFAULT}'.

  • Precedence (most → least):
      command-line args > workspace config file > environment variables > built-in defaults
EOF
}

# --------- Load default workspace config BEFORE parsing so CLI can override it later ---------
if [[ -n "$WORKSPACE_CONFIG_FILE" && -f "$WORKSPACE_CONFIG_FILE" ]]; then
  # tolerate CRLF endings in the file
  # shellcheck disable=SC1090
  source <(sed $'s/\r$//' "$WORKSPACE_CONFIG_FILE")
fi

# --------- Helper: load docker args file into array (supports quotes, ignores comments) ---------
load_docker_args_file() {
  local f="$1"
  [[ -z "$f" || ! -f "$f" ]] && return 0
  # Read CRLF-tolerant, skip blanks and comments; each non-empty line is evaluated as words
  # shellcheck disable=SC2016
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # Use eval to expand a single line into array items (respects quotes)
    # shellcheck disable=SC2086
    eval 'RUN_ARGS_FROM_FILE+=('"$line"')'
  done < <(sed $'s/\r$//' "$f")
}

# --------- Parse arguments ---------
parsing_cmds=false
while [[ $# -gt 0 ]]; do
  if [[ "$parsing_cmds" == true ]]; then
    CMDS+=("$1"); shift
  else
    case $1 in
      -d|--daemon)   DAEMON=true  ; shift ;;
      --pull)        DO_PULL=true ; shift ;;
      --dryrun)      DRYRUN=true  ; shift ;;
      --variant)     [[ -n "${2:-}" ]] && { CLI_VARIANT="$2"            ; shift 2; } || { echo "Error: --variant requires a value";    exit 1; } ;;
      --version)     [[ -n "${2:-}" ]] && { CLI_VERSION="$2"            ; shift 2; } || { echo "Error: --version requires a value";    exit 1; } ;;
      --name)        [[ -n "${2:-}" ]] && { CLI_CONTAINER="$2"          ; shift 2; } || { echo "Error: --name requires a value";       exit 1; } ;;
      --config)      [[ -n "${2:-}" ]] && { CLI_CONFIG_FILE="$2"        ; shift 2; } || { echo "Error: --config requires a path";      exit 1; } ;;
      --env-file)    [[ -n "${2:-}" ]] && { CLI_CONTAINER_ENV_FILE="$2" ; shift 2; } || { echo "Error: --env-file requires a path";    exit 1; } ;;
      --docker-args) [[ -n "${2:-}" ]] && { CLI_DOCKER_ARGS_FILE="$2"   ; shift 2; } || { echo "Error: --docker-args requires a path"; exit 1; } ;;
      --workspace)   [[ -n "${2:-}" ]] && { CLI_WORKSPACE="$2"          ; shift 2; } || { echo "Error: --workspace requires a path";   exit 1; } ;;
      --dockerfile)  [[ -n "${2:-}" ]] && { CLI_DOCKERFILE="$2"         ; shift 2; } || { echo "Error: --dockerfile requires a path";  exit 1; } ;;
      -h|--help)     show_help ; exit 0 ;;
      --)            parsing_cmds=true ; shift ;;
      *)             RUN_ARGS+=("$1") ; shift ;;
    esac
  fi
done

# If a different config file was specified, source it now (then re-apply CLI overrides)
if [[ -n "$CLI_CONFIG_FILE" ]]; then
  WORKSPACE_CONFIG_FILE="$CLI_CONFIG_FILE"
  if [[ -f "$WORKSPACE_CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source <(sed $'s/\r$//' "$WORKSPACE_CONFIG_FILE")
  else
    echo "Warning: --config '$WORKSPACE_CONFIG_FILE' not found; continuing without it." >&2
  fi
fi

# Apply CLI overrides last (preserve precedence)
[[ -n "$CLI_VARIANT"   ]]          && VARIANT="$CLI_VARIANT"
[[ -n "$CLI_VERSION"   ]]          && VERSION="$CLI_VERSION"
[[ -n "$CLI_CONTAINER" ]]          && CONTAINER="$CLI_CONTAINER"
[[ -n "$CLI_CONTAINER_ENV_FILE" ]] && CONTAINER_ENV_FILE="$CLI_CONTAINER_ENV_FILE"
[[ -n "$CLI_DOCKER_ARGS_FILE" ]]   && DOCKER_ARGS_FILE="$CLI_DOCKER_ARGS_FILE"
[[ -n "$CLI_WORKSPACE" ]]          && WORKSPACE="$(readlink -f "$CLI_WORKSPACE")"
[[ -n "$CLI_DOCKERFILE" ]]         && DOCKERFILE="$CLI_DOCKERFILE"

DOCKERFILE="${DOCKERFILE:-$WORKSPACE/Dockerfile}"

# CHG: Track whether a variant was explicitly provided (CLI/config/env), not defaulted.
VARIANT_EXPLICIT=false
if [[ -n "$CLI_VARIANT" || -n "${VARIANT}" ]]; then
  # If VARIANT is set by either CLI or sourced/env (even if empty string), treat as explicit.
  # Only an actually non-empty value will be validated below.
  VARIANT_EXPLICIT=true
fi

# --------- Validate & derive ---------
# CHG: Only validate if a variant value is present; otherwise we may build locally.
if [[ -n "${VARIANT:-}" ]]; then
  case "$VARIANT" in
    container|notebook|codeserver) ;;
    *) echo "Error: unknown --variant '$VARIANT' (expected: container|notebook|codeserver)"; exit 1 ;;
  esac
fi

# Derive tag/name if variant path is chosen later; for now, leave IMGNAME possibly unset.
IMG_TAG="${IMG_TAG-}"
IMGNAME="${IMGNAME-}"

# Default container name: <project-folder>, sanitized for Docker
if [[ -z "${CONTAINER:-}" ]]; then
  proj="$(basename "$WORKSPACE")"
  proj_sanitized="$(printf '%s' "$proj" | tr '[:upper:] ' '[:lower:]-' | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//')"
  [[ -z "$proj_sanitized" ]] && proj_sanitized="workspace"
  CONTAINER="${proj_sanitized}"
else
  # still need proj_sanitized for local image tag below
  proj="$(basename "$WORKSPACE")"
  proj_sanitized="$(printf '%s' "$proj" | tr '[:upper:] ' '[:lower:]-' | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//')"
  [[ -z "$proj_sanitized" ]] && proj_sanitized="workspace"
fi

# Build docker args common to all modes
# Choose -it only if both stdin and stdout are TTYs
TTY_ARGS="-i"
if [ -t 0 ] && [ -t 1 ]; then TTY_ARGS="-it"; fi

COMMON_ARGS=(
  --name "$CONTAINER"
  -e HOST_UID="$HOST_UID"
  -e HOST_GID="$HOST_GID"
  -v "$WORKSPACE":"/home/coder/workspace"
  -w "/home/coder/workspace"
  -p "${WORKSPACE_PORT:-10000}:10000"
)

# Container env file: pass if explicitly set OR default exists
EXPLICIT_ENV_FILE=false
[[ -n "$CLI_CONTAINER_ENV_FILE" ]] && EXPLICIT_ENV_FILE=true
if [[ -n "$CONTAINER_ENV_FILE" ]]; then
  if [[ -f "$CONTAINER_ENV_FILE" ]]; then
    COMMON_ARGS+=(--env-file "$CONTAINER_ENV_FILE")
  else
    $EXPLICIT_ENV_FILE && COMMON_ARGS+=(--env-file "$CONTAINER_ENV_FILE")
  fi
fi

# Load docker args from file and prepend (so CLI RUN_ARGS win on conflicts)
load_docker_args_file "$DOCKER_ARGS_FILE"
if [[ ${#RUN_ARGS_FROM_FILE[@]} -gt 0 ]]; then
  RUN_ARGS=( "${RUN_ARGS_FROM_FILE[@]}" "${RUN_ARGS[@]}" )
fi

# Helper: print the docker run command nicely quoted
print_cmd() {
  printf 'docker'
  for a in "$@"; do
    if [[ "$a" =~ ^[A-Za-z0-9_./:-]+$ ]]; then
      printf ' %s' "$a"
    else
      q=${a//\'/\'\\\'\'}
      printf " '%s'" "$q"
    fi
  done
  printf '\n'
}

# --------- Decide build-vs-variant ---------
USE_LOCAL_BUILD=false
LOCAL_IMGNAME=""
if ! $VARIANT_EXPLICIT; then
  # No variant provided by CLI/config/env → try Dockerfile path
  if [[ -n "${DOCKERFILE:-}" && -f "$DOCKERFILE" ]]; then
    USE_LOCAL_BUILD=true
    LOCAL_IMGNAME="workspace-local:${proj_sanitized}"
  fi
fi

echo "CLI_VARIANT:      $CLI_VARIANT"
echo "VARIANT:          $VARIANT"
echo "USE_LOCAL_BUILD:  $USE_LOCAL_BUILD"
echo "LOCAL_IMGNAME:    $LOCAL_IMGNAME"
echo "VARIANT_EXPLICIT: $VARIANT_EXPLICIT"
echo "WORKSPACE:        $WORKSPACE"
echo "DOCKERFILE:       $DOCKERFILE"
echo "USE_LOCAL_BUILD:  $USE_LOCAL_BUILD"
echo "proj_sanitized:   $proj_sanitized"


# If not building locally and no variant set, fall back to default variant and derive image name
if ! $USE_LOCAL_BUILD; then
  if [[ -z "${VARIANT:-}" ]]; then
    VARIANT="$VARIANT_DEFAULT"
  fi
  # Validate (in case VARIANT was defaulted just now)
  case "$VARIANT" in
    container|notebook|codeserver) ;;
    *) echo "Error: unknown --variant '$VARIANT' (expected: container|notebook|codeserver)"; exit 1 ;;
  esac
  # Derive tag/name only if IMGNAME not explicitly provided
  IMG_TAG="${IMG_TAG:-${VARIANT}-${VERSION}}"
  IMGNAME="${IMGNAME:-${IMGREPO}:${IMG_TAG}}"
fi

if ! $DRYRUN; then
  # Docker preflight (after parsing so --dryrun can skip)
  command -v docker >/dev/null 2>&1 || { echo "Error: docker not found in PATH. Please install Docker." >&2; exit 1; }
fi

# Build or pull logic, honoring --dryrun and skipping pulls for local builds
if $USE_LOCAL_BUILD; then
  # Build local image from Dockerfile
  if $DRYRUN; then
    print_cmd build -f "$DOCKERFILE" -t "$LOCAL_IMGNAME" .
  else
    docker build -f "$DOCKERFILE" -t "$LOCAL_IMGNAME" .
  fi
  IMGNAME="$LOCAL_IMGNAME"
else
  # Variant path: pull/inspect as before
  if [[ -z "${IMGNAME:-}" || "$IMGNAME" =~ [[:space:]] ]]; then
    echo "Error: invalid image reference IMGNAME='${IMGNAME:-}' (empty or contains whitespace)." >&2
    exit 1
  fi
  if ! $DRYRUN; then
    if $DO_PULL || ! { docker image inspect "$IMGNAME" >/dev/null 2>&1; }; then
      echo "Pulling image: $IMGNAME"
      docker pull "$IMGNAME" || { echo "Error: failed to pull '$IMGNAME'." >&2; exit 1; }
    fi
    if ! docker image inspect "$IMGNAME" >/dev/null 2>&1; then
      echo "Error: image '$IMGNAME' not available locally. Try '--pull'." >&2
      exit 1
    fi
  fi
fi

if ! $DRYRUN; then
  # Clean up any previous container with the same name
  docker rm -f "$CONTAINER" &>/dev/null || true
fi

# --------- Execute ---------

# Unified runner: print when --dryrun, otherwise exec the real docker run
run() {
  if $DRYRUN; then
    print_cmd run "$@"
  else
    exec docker run "$@"
  fi
}

WORKSPACE_PORT=${WORKSPACE_PORT:-10000}

if $DAEMON; then
  # Detached: no TTY args
  echo "📦 Running workspace in daemon mode."
  echo "👉 Stop with '${0} -- exit'. The container will be removed (--rm) when stop."
  echo "👉 Visit 'http://localhost:${WORKSPACE_PORT}'"
  echo "👉 To open an interactive shell instead: ${0} -- bash"
  echo -n "👉 Container ID: "
  run -d \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    -e DAEMON=${DAEMON} \
    -e WORKSPACE_PORT=${WORKSPACE_PORT} \
    "$IMGNAME"

elif [[ ${#CMDS[@]} -eq 0 ]]; then
  echo "📦 Running workspace in foreground."
  echo "👉 Stop with Ctrl+C. The container will be removed (--rm) when stop."
  echo "👉 To open an interactive shell instead: '${0} -- bash'"
  run --rm "$TTY_ARGS" \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    -e DAEMON=${DAEMON} \
    -e WORKSPACE_PORT=${WORKSPACE_PORT} \
    "$IMGNAME"

else
  # Foreground with explicit command
  USER_CMD="${CMDS[*]}"
  run --rm "$TTY_ARGS" \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    -e DAEMON=${DAEMON} \
    -e WORKSPACE_PORT=${WORKSPACE_PORT} \
    "$IMGNAME" \
    bash -lc "$USER_CMD"
fi
