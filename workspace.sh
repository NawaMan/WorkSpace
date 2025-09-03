#!/bin/bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# ---------- Defaults ----------
IMGREPO="${IMGREPO:-nawaman/workspace}"
VARIANT="${VARIANT:-container}"
VERSION="${VERSION:-latest}"

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

# NEW: Docker run-args file (NOT sourced); lines are parsed into RUN_ARGS
DOCKER_ARGS_FILE="${DOCKER_ARGS_FILE:-./workspace-docker.args}"

WORKSPACE="/home/coder/workspace"
RUN_ARGS=()
CMDS=()

# Capture CLI overrides without applying yet (to preserve precedence)
CLI_VARIANT=""
CLI_VERSION=""
CLI_CONTAINER=""
CLI_CONFIG_FILE=""
CLI_CONTAINER_ENV_FILE=""
# NEW: CLI override for docker args file
CLI_DOCKER_ARGS_FILE=""

# NEW: holder for args loaded from docker args file
RUN_ARGS_FROM_FILE=()

show_help() {
  cat <<EOF
Starting a workspace container.
More information: https://github.com/NawaMan/WorkSpace

Usage:
  ${SCRIPT_NAME} [OPTIONS] [RUN_ARGS]                 # interactive shell
  ${SCRIPT_NAME} [OPTIONS] [RUN_ARGS] -- <command...> # run a command then exit
  ${SCRIPT_NAME} [OPTIONS] [RUN_ARGS] --daemon        # run container detached

Options:
  -d, --daemon              Run container detached (background)
      --pull                Pull/refresh the image from registry (also pulls if image missing)
      --variant <name>      Variant prefix        (default: container)
      --version <tag>       Version suffix        (default: latest)
      --name <name>         Container name        (default: <project-folder>)
      --config F            Launcher config file to source (default: ./workspace.env or \$WORKSPACE_CONFIG_FILE)
      --env-file F          Container env file passed to 'docker run --env-file' (default: ./.env or \$CONTAINER_ENV_FILE)
      --docker-args F       File of extra 'docker run' args (default: ./workspace-docker.args or \$DOCKER_ARGS_FILE)
      --dryrun              Print the docker run command and exit (no side effects)
  -h, --help                Show this help message

Notes:
  • Bind: . -> /home/coder/workspace; Working dir: /home/coder/workspace

Configuration:
  • Launcher config (sourced): workspace.env (override with --config or \$WORKSPACE_CONFIG_FILE)
      Keys: IMGNAME, IMGREPO, IMG_TAG, VARIANT, VERSION, CONTAINER,
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
[[ -n "$CLI_VARIANT"   ]] && VARIANT="$CLI_VARIANT"
[[ -n "$CLI_VERSION"   ]] && VERSION="$CLI_VERSION"
[[ -n "$CLI_CONTAINER" ]] && CONTAINER="$CLI_CONTAINER"
[[ -n "$CLI_CONTAINER_ENV_FILE" ]] && CONTAINER_ENV_FILE="$CLI_CONTAINER_ENV_FILE"
# NEW: apply CLI override for docker args file
[[ -n "$CLI_DOCKER_ARGS_FILE" ]] && DOCKER_ARGS_FILE="$CLI_DOCKER_ARGS_FILE"

# --------- Validate & derive ---------
case "$VARIANT" in
  container|notebook|codeserver) ;;
  *) echo "Error: unknown --variant '$VARIANT' (expected: container|notebook|codeserver)"; exit 1 ;;
esac

IMG_TAG="${IMG_TAG:-${VARIANT}-${VERSION}}"
IMGNAME="${IMGNAME:-${IMGREPO}:${IMG_TAG}}"

# Default container name: <project-folder>, sanitized for Docker
if [[ -z "${CONTAINER:-}" ]]; then
  proj="$(basename "$PWD")"
  proj_sanitized="$(printf '%s' "$proj" | tr '[:upper:] ' '[:lower:]-' | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//')"
  [[ -z "$proj_sanitized" ]] && proj_sanitized="workspace"
  CONTAINER="${proj_sanitized}"
fi

# Build docker args common to all modes
TTY_ARGS="-i"; if [ -t 1 ]; then TTY_ARGS="-it"; fi

COMMON_ARGS=(
  --name "$CONTAINER"
  -e HOST_UID="$HOST_UID"
  -e HOST_GID="$HOST_GID"
  -v "$PWD":"$WORKSPACE"
  -w "$WORKSPACE"
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

# NEW: Load docker args from file and prepend (so CLI RUN_ARGS win on conflicts)
load_docker_args_file "$DOCKER_ARGS_FILE"
if [[ ${#RUN_ARGS_FROM_FILE[@]} -gt 0 ]]; then
  RUN_ARGS=( "${RUN_ARGS_FROM_FILE[@]}" "${RUN_ARGS[@]}" )
fi

# Helper: print a docker command nicely quoted
print_cmd() {
  printf 'docker run'
  for a in "$@"; do
    # safe token? print as-is
    if [[ "$a" =~ ^[A-Za-z0-9_./:-]+$ ]]; then
      printf ' %s' "$a"
    else
      # single-quote and escape internal single quotes: ' -> '\'' 
      q=${a//\'/\'\\\'\'}
      printf " '%s'" "$q"
    fi
  done
  printf '\n'
}

# --------- If --dryrun, print and exit (no side effects) ---------
if $DAEMON; then
  SHELL_CMD=()
  if [[ "$VARIANT" == "container" ]]; then
    SHELL_CMD=("bash" -lc "while true; do sleep 3600; done")
  fi
  if $DRYRUN; then
    print_cmd -d "${COMMON_ARGS[@]}" "${RUN_ARGS[@]}" "$IMGNAME" "${SHELL_CMD[@]}"
    exit 0
  fi
else
  if $DRYRUN; then
    if [[ ${#CMDS[@]} -eq 0 ]]; then
      print_cmd --rm "$TTY_ARGS" "${COMMON_ARGS[@]}" "${RUN_ARGS[@]}" "$IMGNAME"
    else
      USER_CMD="${CMDS[*]}"
      print_cmd --rm "$TTY_ARGS" "${COMMON_ARGS[@]}" "${RUN_ARGS[@]}" "$IMGNAME" "bash" -lc "$USER_CMD"
    fi
    exit 0
  fi
fi

# --------- Docker preflight (after parsing so --dryrun can skip) ---------
command -v docker >/dev/null 2>&1 || { echo "Error: docker not found in PATH. Please install Docker." >&2; exit 1; }

# --------- Pull if requested or missing ---------
# Fail early on obviously bad refs (empty or whitespace)
if [[ -z "$IMGNAME" || "$IMGNAME" =~ [[:space:]] ]]; then
  echo "Error: invalid image reference IMGNAME='$IMGNAME' (empty or contains whitespace)." >&2
  exit 1
fi
# Silence inspect's stderr cleanly; pull if missing or --pull requested
if $DO_PULL || ! { docker image inspect "$IMGNAME" >/dev/null 2>&1; }; then
  echo "Pulling image: $IMGNAME"
  docker pull "$IMGNAME" || { echo "Error: failed to pull '$IMGNAME'." >&2; exit 1; }
fi

# Final check
if ! docker image inspect "$IMGNAME" >/dev/null 2>&1; then
  echo "Error: image '$IMGNAME' not available locally. Try '--pull'." >&2
  exit 1
fi

# Clean up any previous container with the same name
docker rm -f "$CONTAINER" &>/dev/null || true

# --------- Execute ---------
if $DAEMON; then
  SHELL_CMD=()
  if [[ "$VARIANT" == "container" ]]; then
    SHELL_CMD=("bash" -lc "while true; do sleep 3600; done")
  fi

  exec docker run -d \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMGNAME" \
    "${SHELL_CMD[@]}"

elif [[ ${#CMDS[@]} -eq 0 ]]; then
  exec docker run --rm "$TTY_ARGS" \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMGNAME"

else
  USER_CMD="${CMDS[*]}"
  exec docker run --rm "$TTY_ARGS" \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMGNAME" \
    bash -lc "$USER_CMD"
fi
