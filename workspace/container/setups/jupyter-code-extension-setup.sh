#!/usr/bin/env bash
# python-code-extension-setup.sh
# Root-only installer: writes /etc/profile.d/99-python-extension.sh to run per-user at login.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

PROFILE_PATH="/etc/profile.d/99-python-extension.sh"
UMASK_OLD=$(umask)
umask 022

cat >"$PROFILE_PATH" <<'PROFILE_EOF'
# /etc/profile.d/99-python-extension.sh
# shellcheck shell=bash
# Minimal Jupyter extension setup for VS Code / code-server on first interactive login.
# - Scans /opt/venvs for a venv with jupyter_client
# - Installs ms-toolsai.jupyter (+ Python + Pylance unless SKIP_PY_EXTS=1)
# - Writes lightweight settings.json pointing to that venv
# - Runs once per user; bump VERSION to re-run.

# Only interactive, non-root shells
case $- in *i*) : ;; *) return 0 2>/dev/null || exit 0 ;; esac
[ "${EUID:-$(id -u)}" -eq 0 ] && return 0 2>/dev/null || exit 0

set -Eeuo pipefail

# ---- config knobs (can be overridden in env before login) ----
: "${SKIP_PY_EXTS:=0}"      # set to 1 to install ONLY the Jupyter extension
VERSION="v1-minimal-hook"   # bump to force re-run for all users

STAMP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/vscode-ext-setup"
STAMP_FILE="$STAMP_DIR/$VERSION.done"
mkdir -p "$STAMP_DIR"

# If we already completed this VERSION, stop.
[[ -f "$STAMP_FILE" ]] && return 0 2>/dev/null || exit 0

# ---- helpers ----
_pick_code_bins() {
  # echo any available CLIs, one per line
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

ensure_exts_for_cli() {
  local cli="$1"
  local -a EXTS=( ms-toolsai.jupyter )
  [[ "$SKIP_PY_EXTS" -ne 1 ]] && EXTS+=( ms-python.python ms-python.vscode-pylance )

  # list once to avoid repeated spawns
  local listed; listed="$("$cli" --list-extensions 2>/dev/null || true)"
  local id
  for id in "${EXTS[@]}"; do
    if ! grep -Fxq "$id" <<<"$listed"; then
      "$cli" --install-extension "$id" >/dev/null 2>&1 || true
    fi
  done
}

write_settings() {
  # $1 = path, $2 = python path (non-empty required here)
  local path="$1" py="$2"
  mkdir -p "$(dirname "$path")"
  if command -v jq >/dev/null 2>&1 && [[ -f "$path" ]]; then
    local tmp; tmp="$(mktemp)"
    jq --arg py "$py" '
      . + {
        "python.defaultInterpreterPath": $py,
        "jupyter.jupyterServerType": "local",
        "python.terminal.activateEnvironment": true
      }' "$path" >"$tmp" && mv "$tmp" "$path"
  else
    cat >"$path" <<JSON
{
  "python.defaultInterpreterPath": "$py",
  "jupyter.jupyterServerType": "local",
  "python.terminal.activateEnvironment": true
}
JSON
  fi
}

# ---- main flow ----

# 1) Need a Code CLI; if not present yet, try again on next login (no stamp).
mapfile -t CODE_BINS < <(_pick_code_bins || true)
if [[ ${#CODE_BINS[@]} -eq 0 ]]; then
  # No code/code-server on PATH yet; retry later.
  return 0 2>/dev/null || exit 0
fi

# 2) Need a Jupyter-capable venv; if not found, retry later (no stamp).
VENV_DIR="${VENV_DIR:-$(find_venv_with_jupyter_client || true)}"
if [[ -z "${VENV_DIR:-}" || ! -x "$VENV_DIR/bin/python" ]]; then
  # Venv not ready; retry later.
  return 0 2>/dev/null || exit 0
fi
VENV_PY="$VENV_DIR/bin/python"

# 3) Install extensions for each available CLI
for cli in "${CODE_BINS[@]}"; do
  ensure_exts_for_cli "$cli" || true
done

# 4) Write minimal settings.json for common locations
write_settings "$HOME/.config/Code/User/settings.json"             "$VENV_PY"
write_settings "$HOME/.vscode-data/User/settings.json"             "$VENV_PY"
write_settings "$HOME/.local/share/code-server/User/settings.json" "$VENV_PY"

# 5) Mark success (we had Code + venv and applied settings)
: > "$STAMP_FILE"

# 6) Optional friendly echo (interactive only)
if [ -t 1 ]; then
  echo "✅ VS Code Jupyter setup complete. Interpreter: $VENV_PY"
  [[ "$SKIP_PY_EXTS" -eq 1 ]] && echo "↪ Skipped Python/Pylance (SKIP_PY_EXTS=1)."
fi
PROFILE_EOF

chmod 0644 "$PROFILE_PATH"
umask "$UMASK_OLD"

echo "Installed login hook: $PROFILE_PATH"
echo "Users will auto-configure on first login once Code and a Jupyter-capable venv exist."
echo "To reapply later, edit $PROFILE_PATH and bump VERSION."
