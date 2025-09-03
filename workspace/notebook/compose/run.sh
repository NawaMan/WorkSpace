#!/bin/bash
set -euo pipefail

# ---------- Constants ----------
SERVICE_NAME="workspace"
SHELL_NAME="bash"

RUN_ARGS=()
CMD=()

show_help() {
  cat <<'EOF'
Usage:
  run.sh [OPTIONS]                 # interactive shell (bash)
  run.sh [OPTIONS] -- <command...> # run a command then exit

Options:
  -h, --help    Show this help message
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

# --------- Run container ---------
if [[ ${#CMD[@]} -eq 0 ]]; then
  # No command -> open a shell
  exec docker compose run --rm \
    "${RUN_ARGS[@]}" \
    -p 10000:10000   \
    "$SERVICE_NAME"
else
  # Command provided -> run it inside the shell
  USER_CMD="${CMD[*]}"
  exec docker compose run --rm \
    "${RUN_ARGS[@]}" \
    -p 10000:10000   \
    "$SERVICE_NAME"  \
    "$SHELL_NAME" -lc "$USER_CMD"
fi
