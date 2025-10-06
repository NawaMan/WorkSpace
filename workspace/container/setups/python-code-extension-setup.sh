#!/usr/bin/env bash
# python-code-extension-setup.sh
# Root-only installer for a login-time VS Code bootstrap in /etc/profile.d/.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

PROFILE_PATH="/etc/profile.d/99-python-extension.sh"
UMASK_OLD=$(umask)
umask 022

# Write the profile.d script (runs as each non-root user at login)
cat >"$PROFILE_PATH" <<'PROFILE_EOF'
# /etc/profile.d/99-python-extension.sh
# shellcheck shell=bash
# Install VS Code Python/Jupyter/Pylance for the current non-root user on first login,
# point to a /opt/venvs/* interpreter (if one with jupyter_client exists),
# merge minimal settings, and (optionally) add dev tools to that venv.
# Idempotent; runs once per user using a stamp file controlled by VERSION.

# Only for interactive shells and non-root users
case $- in
  *i*) : ;;
  *)   return 0 2>/dev/null || exit 0 ;;
esac
[ "${EUID:-$(id -u)}" -eq 0 ] && return 0 2>/dev/null || exit 0

set -Eeuo pipefail

VERSION="v2"

STAMP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/vscode-ext-setup"
STAMP_FILE="$STAMP_DIR/$VERSION.done"
mkdir -p "$STAMP_DIR"
# NOTE: We *don't* early-return here — we want to attempt if not stamped.

# ---- helpers ----
_pick_code_bins() {
  # echo any available CLIs, one per line, in preference order
  for b in code code-insiders codium code-server; do
    command -v "$b" >/dev/null 2>&1 && echo "$b"
  done
}

find_venv_with_jupyter_client() {
  local p
  for p in /opt/venvs/py*/bin/python; do
    [[ -x "$p" ]] || continue
    "$p" - <<'PY' >/dev/null 2>&1 || continue
import importlib.util as u; raise SystemExit(0 if u.find_spec("jupyter_client") else 1)
PY
    printf "%s\n" "${p%/bin/python}"
    return 0
  done
  return 1
}

ensure_exts() {
  local cli="$1"
  local -a EXTS=( ms-toolsai.jupyter ms-python.python ms-python.vscode-pylance )
  # list once to avoid repeated spawns
  local listed; listed="$("$cli" --list-extensions 2>/dev/null || true)"
  local did_any=0
  for id in "${EXTS[@]}"; do
    if ! grep -Fxq "$id" <<<"$listed"; then
      "$cli" --install-extension "$id" >/dev/null 2>&1 || true
      did_any=1
    fi
  done
  return 0
}

write_settings() {
  # $1 = path to settings.json, $2 = python path (may be empty)
  local path="$1" py="$2"
  mkdir -p "$(dirname "$path")"
  if command -v jq >/dev/null 2>&1 && [[ -f "$path" ]]; then
    # merge, omitting null values
    local tmp; tmp="$(mktemp)"
    jq --arg py "$py" '. + {
      "python.defaultInterpreterPath": ($py | select(. != "")),
      "jupyter.jupyterServerType": "local",
      "python.terminal.activateEnvironment": true
    } | with_entries(select(.value != null))' "$path" >"$tmp" && mv "$tmp" "$path"
  else
    # write (omit interpreter if empty)
    if [[ -n "$py" ]]; then
      cat >"$path" <<JSON
{
  "python.defaultInterpreterPath": "$py",
  "jupyter.jupyterServerType": "local",
  "python.terminal.activateEnvironment": true
}
JSON
    else
      cat >"$path" <<'JSON'
{
  "jupyter.jupyterServerType": "local",
  "python.terminal.activateEnvironment": true
}
JSON
    fi
  fi
}

need_install_tools() {
  local py="$1"
  "$py" - <<'PY' >/dev/null 2>&1
import importlib.util as u, sys
pkgs={"black","ruff","isort","pytest","ipywidgets"}
sys.exit(1 if any(u.find_spec(p) is None for p in pkgs) else 0)
PY
}

# ---- main flow ----
# If already stamped for this VERSION, exit quietly
if [[ -f "$STAMP_FILE" ]]; then
  return 0 2>/dev/null || exit 0
fi

# 1) Find VS Code CLI(s). If none yet on PATH, try again on next login (no stamp).
mapfile -t CODE_BINS < <(_pick_code_bins || true)
if [[ ${#CODE_BINS[@]} -eq 0 ]]; then
  # No code CLI yet; try on subsequent logins when Code is installed.
  return 0 2>/dev/null || exit 0
fi

# 2) Install/ensure required extensions for each available CLI
for cli in "${CODE_BINS[@]}"; do
  ensure_exts "$cli" || true
done

# 3) Detect a /opt/venvs/* venv that already has jupyter_client
VENV_DIR="${VENV_DIR:-$(find_venv_with_jupyter_client || true)}"
VENV_PY=""; VENV_PIP=""
if [[ -n "${VENV_DIR:-}" && -x "$VENV_DIR/bin/python" ]]; then
  VENV_PY="$VENV_DIR/bin/python"
  VENV_PIP="$VENV_DIR/bin/pip"
fi

# 4) Write settings.json for common locations (desktop Code, OSS, and code-server)
write_settings "$HOME/.config/Code/User/settings.json"                "$VENV_PY"
write_settings "$HOME/.vscode-data/User/settings.json"                "$VENV_PY"
write_settings "$HOME/.local/share/code-server/User/settings.json"    "$VENV_PY"

# 5) Optional tools: install only if venv exists, is writable, and anything is missing
if [[ -n "$VENV_DIR" && -w "$VENV_DIR" && -n "$VENV_PY" ]] && need_install_tools "$VENV_PY"; then
  "$VENV_PIP" install --upgrade pip >/dev/null 2>&1 || true
  "$VENV_PIP" install -q black ruff isort pytest ipywidgets || true
fi

# 6) Mark done for this VERSION (we reached this point, so Code CLI existed)
: > "$STAMP_FILE"

# 7) Optional: friendly echo if interactive TTY
if [ -t 1 ]; then
  if [[ -n "$VENV_PY" ]]; then
    printf "VS Code extensions configured. Python interpreter: %s\n" "$VENV_PY"
  else
    printf "VS Code extensions configured. No /opt/venvs/* with jupyter_client found yet.\n"
  fi
fi

PROFILE_EOF

chmod 0644 "$PROFILE_PATH"
umask "$UMASK_OLD"

echo "Installed: $PROFILE_PATH"
echo "Users will get extensions on their next login (once per user)."
echo "To force a rerun later, bump VERSION in $PROFILE_PATH (e.g., v3)."
