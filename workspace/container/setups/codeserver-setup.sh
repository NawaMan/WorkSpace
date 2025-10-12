#!/usr/bin/env bash
# codeserver-setup.sh
# Installs code-server + Jupyter (Python venv). Bash kernel is installed via external script.
# Auth behavior:
#   - If PASSWORD is empty or unset -> auth: none (no password)
#   - If PASSWORD is set           -> auth: password (value = PASSWORD)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# This is to be run by sudo
# Ensure script is run as root (EUID == 0)
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# Use python-setup.sh exactly like setup-code-server-jupyter.sh
PY_VERSION=${1:-3.12}                    # accepts X.Y or X.Y.Z
FEATURE_DIR=${FEATURE_DIR:-/opt/workspace/setups}
"${FEATURE_DIR}/python-setup.sh" "${PY_VERSION}"

# Load python env exported by the base setup
source /etc/profile.d/53-ws-python.sh 2>/dev/null || true

# Profile snippet this script will write to (used later)
PROFILE_FILE="/etc/profile.d/55-ws-codeserver.sh"

### ---- Tunables (override with env) ----
PASSWORD="${PASSWORD:-}"                              # empty => no password


echo "[1/9] Install code-server…"
if ! command -v code-server >/dev/null 2>&1; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi
command -v code-server >/dev/null


echo "[2/9] Pre-seed Jupyter into ${VENV_DIR} (build-time)…"

# Ensure venv exists and seed Jupyter so jupyter_client is available before runtime
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  mkdir -p "${VENV_DIR%/*}"
  "${PY_STABLE}/bin/python" -m venv "$VENV_DIR"
fi

VENV_PY="$VENV_DIR/bin/python"
VENV_PIP="$VENV_DIR/bin/pip"

# Upgrade basics
env PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  "$VENV_PY" -m pip install -U pip setuptools wheel

# Install Jupyter + ipykernel into the venv
env PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  "$VENV_PY" -m pip install -U jupyter ipykernel

# Kernelspec (use actual patch version for display)
ACTUAL_VER="$("$VENV_PY" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))')"
"$VENV_PY" -m ipykernel install --sys-prefix --name=python3 --display-name="Python ${ACTUAL_VER} (venv)"


echo "[3/9] Install Bash kernel via external script…"
if [ -x "${FEATURE_DIR}/bash-nb-kernel-setup.sh" ]; then
  VENV_DIR="${VENV_DIR}" "${FEATURE_DIR}/bash-nb-kernel-setup.sh"
else
  echo "⚠️  ${FEATURE_DIR}/bash-nb-kernel-setup.sh not found or not executable; skipping Bash kernel install." >&2
fi

# Export VENV_DIR and prepend to PATH for interactive shells
{
  echo "export VENV_DIR=\"${VENV_DIR}\""
  echo 'if [ -d "$VENV_DIR/bin" ] && [[ ":$PATH:" != *":$VENV_DIR/bin:"* ]]; then export PATH="$VENV_DIR/bin:$PATH"; fi'
} >> "$PROFILE_FILE"

cat >> "$PROFILE_FILE" <<'SH'
# codeserver setup inspector
# Usage: codeserver-setup-info
codeserver_setup_info() {
  set -o pipefail
  _hdr() { printf "\n\033[1m%s\033[0m\n" "$*"; }
  _ok()  { printf "✅ %s\n" "$*"; }
  _warn(){ printf "⚠️  %s\n" "$*"; }
  _err() { printf "❌ %s\n" "$*"; }

  # Defaults that match your setup
  local csuser="${CSUSER:-coder}"
  local cshome="${CSHOME:-/home/$csuser}"
  local config_file="${CONFIG_FILE:-$cshome/.config/code-server/config.yaml}"
  local ext_dir="${CODESERVER_EXTENSION_DIR:-/usr/local/share/code-server/extensions}"
  local launcher="${LAUNCHER:-/usr/local/bin/codeserver}"

  _hdr "code-server"
  if command -v code-server >/dev/null 2>&1; then
    _ok "Binary: $(command -v code-server)"
    _ok "Version: $(code-server --version 2>/dev/null | head -n1)"
  else
    _err "code-server not found on PATH"
  fi
  [ -x "$launcher" ] && _ok "Launcher: $launcher"

  _hdr "Python / venv"
  local venv="${VENV_DIR:-${VENV_SERIES_DIR:-/opt/venvs/py${PY_SERIES:-}}}"
  if [ -n "$venv" ] && [ -x "$venv/bin/python" ]; then
    _ok "VENV_DIR: $venv"
    _ok "Python: $("$venv/bin/python" -V 2>&1)"
  elif [ -x /opt/python/bin/python ]; then
    _warn "VENV_DIR not set; using /opt/python"
    _ok "Python: $(/opt/python/bin/python -V 2>&1)"
  else
    _err "No Python interpreter found"
  fi

  _hdr "Jupyter"
  local jbin=""
  if [ -n "$venv" ] && [ -x "$venv/bin/jupyter" ]; then
    jbin="$venv/bin/jupyter"
  elif command -v jupyter >/dev/null 2>&1; then
    jbin="$(command -v jupyter)"
  fi
  if [ -n "$jbin" ]; then
    _ok "jupyter: $("$jbin" --version 2>/dev/null | head -n1)"
    "$jbin" kernelspec list 2>/dev/null | sed 's/^/  /'
  else
    _warn "jupyter not found"
  fi

  _hdr "Extensions"
  if [ -d "$ext_dir" ]; then
    local n
    n="$(find "$ext_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    _ok "Shared dir: $ext_dir (count: $n)"
    find "$ext_dir" -mindepth 1 -maxdepth 1 -type d -printf "  - %f\n" 2>/dev/null | sort | head -n 20
  else
    _warn "Extensions dir not found: $ext_dir"
  fi

  _hdr "Auth config"
  if [ -f "$config_file" ]; then
    local auth pass_set
    auth="$(grep -E '^[[:space:]]*auth:' "$config_file" | awk '{print $2}' | tr -d '\r' || true)"
    grep -Eq '^[[:space:]]*password:' "$config_file" && pass_set=yes || pass_set=no
    _ok "Config: $config_file"
    _ok "Auth: ${auth:-unknown}  Password set: $pass_set"
  else
    _warn "Config not found: $config_file"
  fi

  _hdr "Quick start"
  echo "  codeserver 10000   # start on port 10000 (uses current \$PASSWORD if set)"
}
alias codeserver-setup-info='codeserver_setup_info'
SH

chmod 0644 "$PROFILE_FILE"
# Make it available in THIS shell immediately:
. "$PROFILE_FILE" || true


# Make it usable right away in THIS shell
source "$VENV_DIR/bin/activate"

CODESERVER_EXTENSION_DIR=/usr/local/share/code-server/extensions

# 1) Create a shared directory
mkdir -p "$CODESERVER_EXTENSION_DIR"
chown root:root "$CODESERVER_EXTENSION_DIR"
chmod 1777 -Rf "$CODESERVER_EXTENSION_DIR"     # root-writable, others read/exec (matches your comment)

# 2) Move what you already installed as root and link it back
if [ -d /root/.local/share/code-server/extensions ]; then
  ROOT_CODESERVER_EXTENSION_DIR=/root/.local/share/code-server/extensions

  # Copy out existing extensions (rsync if available, else cp -a)
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$ROOT_CODESERVER_EXTENSION_DIR"/ "$CODESERVER_EXTENSION_DIR"/
  else
    cp -a "$ROOT_CODESERVER_EXTENSION_DIR"/. "$CODESERVER_EXTENSION_DIR"/
  fi

  rm -Rf "$ROOT_CODESERVER_EXTENSION_DIR"
  mkdir -p /root/.local/share/code-server

  # Make the link exact (no trailing slashes; -T to treat LINKNAME as a file)
  ln -sfnT "$CODESERVER_EXTENSION_DIR" "$ROOT_CODESERVER_EXTENSION_DIR"
fi

if [ -f /usr/local/share/code-server/extensions/extensions.json ]; then
  chmod 777 /usr/local/share/code-server/extensions/extensions.json
else
  echo "[]" > /usr/local/share/code-server/extensions/extensions.json
  chmod 777 /usr/local/share/code-server/extensions/extensions.json
fi

# 3) Install future extensions into the shared dir
code-server --extensions-dir "$CODESERVER_EXTENSION_DIR" \
  --install-extension ms-toolsai.jupyter \
  --install-extension ms-python.python

# Extensions now in $CODESERVER_EXTENSION_DIR
code-server --extensions-dir "$CODESERVER_EXTENSION_DIR" --list-extensions || true


echo "[4/9] Create launcher: /usr/local/bin/codeserver"
VENV_DIR_BAKED="$VENV_DIR" PY_VERSION_BAKED="$PY_VERSION" \
envsubst '$VENV_DIR_BAKED $PY_VERSION_BAKED' > /usr/local/bin/codeserver <<'LAUNCH'
#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

PORT=${1:-10000}

# ==== Baked-in values from build time ====
export VENV_DIR="${VENV_DIR_BAKED}"
export PY_VERSION="${PY_VERSION_BAKED}"

# ==== Runtime tunables ====
PASSWORD="${PASSWORD:-}"                 # empty => no password
FEATURE_DIR=${FEATURE_DIR:-.}
PATH="${VENV_DIR}/bin:${PATH}"

# Make venv kernels visible to any Jupyter process
export JUPYTER_PATH="${VENV_DIR}/share/jupyter:/usr/local/share/jupyter:/usr/share/jupyter${JUPYTER_PATH:+:$JUPYTER_PATH}"

# Use the shared extensions dir at runtime so preinstalled extensions are available on first run
CODESERVER_EXTENSION_DIR="${CODESERVER_EXTENSION_DIR:-/usr/local/share/code-server/extensions}"

CSUSER=coder
CSHOME=/home/$CSUSER

# Pre-create config dirs for CSUSER and ensure ownership
mkdir -p "$CSHOME/.config" "$CSHOME/.local/share/code-server" "$CSHOME/.local/share/code-server/User"

# Write code-server config for coder (auth decided at runtime)
mkdir -p "$CSHOME/.config/code-server"
CONFIG_FILE="$CSHOME/.config/code-server/config.yaml"

AUTH=$( [ -z "$PASSWORD" ] && echo none || echo password )
PASS_LINE=$( [ "$AUTH" = "password" ] && echo "password: $PASSWORD" || echo "" )

cat >"$CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:$PORT
cert: false
auth: ${AUTH}
${PASS_LINE}
EOF

# Settings
SETTING_DIR=$CSHOME/.local/share/code-server/User
SETTINGS_JSON="$SETTING_DIR/settings.json"
mkdir -p "$SETTING_DIR"

cat > "$SETTINGS_JSON" <<JSON
{
  "python.defaultInterpreterPath": "${VENV_DIR_BAKED}/bin/python",
  "jupyter.jupyterServerType": "local",

  "terminal.integrated.profiles.linux": {
    "bash-login": { "path": "/bin/bash", "args": ["-l"] }
  },
  "terminal.integrated.defaultProfile.linux": "bash-login",
  "python.terminal.activateEnvironment": true,
  "workbench.colorTheme": "Default Dark+",
  "editor.fontSize": 14
}
JSON

sudo chown -R "coder:coder" "$CSHOME/.config"
sudo chown -R "coder:coder" "$CSHOME/.local"
sudo chown -R "coder:coder" "$VENV_DIR" || true

# -------- default shell for everything code-server launches (incl. Jupyter ext) --------
DEFAULT_SHELL="/bin/bash"
if ! command -v bash >/dev/null 2>&1; then
  DEFAULT_SHELL="/bin/sh"
fi

echo "Starting code-server. This may take sometime ..."
exec sudo --preserve-env=DOCKER_HOST,DOCKER_TLS_VERIFY,DOCKER_CERT_PATH \
  -u "$CSUSER"                 \
  -H env                       \
  SHELL="$DEFAULT_SHELL"       \
  PATH="$VENV_DIR/bin:$PATH"   \
  PASSWORD="$PASSWORD"         \
  JUPYTER_PATH="$JUPYTER_PATH" \
  code-server \
      --extensions-dir "$CODESERVER_EXTENSION_DIR" \
      --bind-addr      "0.0.0.0:$PORT"             \
      --auth           "$AUTH"                     \
      "$CSHOME/workspace"

LAUNCH
chmod 755 /usr/local/bin/codeserver

cat <<EOF

✅ Setup complete.

Start:
  /usr/local/bin/codeserver

Auth mode:
  $( [[ -z "$PASSWORD" ]] && echo "No password (auth: none)" || echo "Password set (auth: password)" )

Kernels available (scoped to venv):
  - Python 3 (venv)
  - Bash
EOF
