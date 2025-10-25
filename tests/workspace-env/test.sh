#!/usr/bin/env bash
# Smoke test for env-file passthrough and workspace mount
# Verifies:
#   1) .env -> SECRET is visible inside container
#   2) data.txt is present and readable inside container
#   3) source data.txt -> PUBLIC variable becomes available

set -euo pipefail

# ---- Config -------------------------------------------------------------------
# Path to your workspace launcher script. Override via env if needed.
WS_SCRIPT="${WS_SCRIPT:-../../workspace.sh}"
# Canonicalize to absolute path before we cd/pushd anywhere
if command -v readlink >/dev/null 2>&1; then
  WS_SCRIPT="$(readlink -f "$WS_SCRIPT")"
else
  WS_SCRIPT="$(cd "$(dirname "$WS_SCRIPT")" && pwd -P)/$(basename "$WS_SCRIPT")"
fi

# Unique container name to avoid collisions
RUN_ID="$(date +%s)-$$"
CONTAINER_NAME="ws-test-${RUN_ID}"

# ---- Preconditions ------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP: docker not found in PATH"
  exit 0
fi

if [[ ! -x "$WS_SCRIPT" ]]; then
  echo "ERROR: WS_SCRIPT not executable or not found: $WS_SCRIPT" >&2
  exit 1
fi

# ---- Test workspace -----------------------------------------------------------
TMPDIR="$(mktemp -d)"
cleanup() {
  # Workspace container is started with --rm, so nothing to stop.
  rm -rf "$TMPDIR" || true
}
trap cleanup EXIT

pushd "$TMPDIR" >/dev/null

# Create files as per your example
cat > .env <<'EOF'
SECRET=Boo
EOF

cat > data.txt <<'EOF'
PUBLIC=Yo
EOF

# Helper to run the workspace with our test image and capture stdout
run_ws() {
  # We’ll pass an explicit image to avoid any build/pull logic, pick a random port to avoid conflicts
  # Note: The script wraps the command in `bash -lc "<cmd>"` internally
  "$WS_SCRIPT" -- "$@"
}

# ---- Assertions ---------------------------------------------------------------
pass() { printf 'ok - %s\n' "$*"; }
fail() { printf 'not ok - %s\n' "$*\n" >&2; exit 1; }

# 1) SECRET from .env is visible
out="$(run_ws 'echo $SECRET' | tr -d '\r')"
[[ "$out" == "Boo" ]] || fail "SECRET expected 'Boo', got: '$out'"
pass "SECRET from .env visible in container"

# 2) data.txt is present
out="$(run_ws 'cat data.txt' | tr -d '\r')"
[[ "$out" == "PUBLIC=Yo" ]] || fail "data.txt content mismatch, got: '$out'"
pass "data.txt present in workspace mount"

# 3) source data.txt -> PUBLIC available
out="$(run_ws 'source data.txt; echo $PUBLIC' | tr -d '\r')"
[[ "$out" == "Yo" ]] || fail "PUBLIC expected 'Yo' after sourcing, got: '$out'"
pass "Sourcing data.txt exposes PUBLIC"

popd >/dev/null

echo "All checks passed."
