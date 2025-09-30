#!/usr/bin/env bash
# setup-code-server-jupyter.sh
# Installs code-server + Jupyter (Python venv + Bash kernel) on Ubuntu
# Auth behavior:
#   - If PASSWORD is empty or unset -> auth: none (no password)
#   - If PASSWORD is set           -> auth: password (value = PASSWORD)
set -Eeuo pipefail

# This is to be run by sudo
# Ensure script is run as root (EUID == 0)
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- configurable args (safe defaults) ----
PY_VERSION=${1:-3.11}              # accepts 3.13, 3.13.7, 3.12, ...
PYENV_ROOT="/opt/pyenv"            # system-wide pyenv
VENV_ROOT="/opt/venvs"             # shared venvs root
PIP_CACHE_DIR="/opt/pip-cache"     # shared pip cache
STABLE_PY_LINK="/opt/python"       # stable, version-agnostic symlink
PROFILE_FILE="/etc/profile.d/99-custom.sh"

FEATURE_DIR=${FEATURE_DIR:-/opt/workspace/features}
${FEATURE_DIR}/python-setup.sh "${PY_VERSION}"

### ---- Tunables (override with env) ----
PORT="${PORT:-10000}"                                 # code-server port
PASSWORD="${PASSWORD:-}"                              # empty => no password
VENV_DIR="${VENV_DIR:-/opt/venvs/py${PY_VERSION}}"    # Jupyter virtualenv location

echo "[1/9] Install code-server…"
if ! command -v code-server >/dev/null 2>&1; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi
command -v code-server >/dev/null

# # Ensure the runtime user exists (minimal safeguard)
# if ! id -u coder >/dev/null 2>&1; then
#   useradd -m -s /bin/bash coder
# fi

echo "[2/9] Pre-seed Jupyter into ${VENV_DIR} (build-time)…"
# Ensure venv exists and seed Jupyter so jupyter_client is available before runtime
if [[ ! -d "$VENV_DIR" ]]; then
  "${STABLE_PY_LINK}/bin/python" -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel
"$VENV_DIR/bin/pip" install jupyter bash_kernel ipykernel
"$VENV_DIR/bin/python" -m bash_kernel.install --sys-prefix
"$VENV_DIR/bin/python" -m ipykernel install --sys-prefix --name=python3 --display-name="Python ${PY_VERSION} (venv)"
# # Ensure the coder user can access the venv (useful in containers)
# sudo chown -R "coder:coder" "$VENV_DIR" || true

# Export VENV_DIR and prepend to PATH for interactive shells
{
  echo "export VENV_DIR=\"${VENV_DIR}\""
  echo 'if [ -d "$VENV_DIR/bin" ] && [[ ":$PATH:" != *":$VENV_DIR/bin:"* ]]; then export PATH="$VENV_DIR/bin:$PATH"; fi'
} >> "$PROFILE_FILE"

source "$VENV_DIR/bin/activate"

CODESERVER_EXTENSION_DIR=/usr/local/share/code-server/extensions

# 1) Create a shared directory
mkdir -p "$CODESERVER_EXTENSION_DIR"
chmod -R a+rX "$CODESERVER_EXTENSION_DIR"
# (root will write here; everyone else needs read+exec)

# 2) (Optional) Move what you already installed as root
if [ -d /root/.local/share/code-server/extensions ]; then
  rsync -a /root/.local/share/code-server/extensions/ "$CODESERVER_EXTENSION_DIR"/
fi

# 3) Install future extensions into the shared dir
code-server --extensions-dir "$CODESERVER_EXTENSION_DIR" \
  --install-extension ms-toolsai.jupyter \
  --install-extension ms-python.python

echo "[4/9] Create launcher: /usr/local/bin/codeserver"
VENV_DIR_BAKED="$VENV_DIR" PY_VERSION_BAKED="$PY_VERSION" \
envsubst '$VENV_DIR_BAKED $PY_VERSION_BAKED' > /usr/local/bin/codeserver <<'LAUNCH'
#!/usr/bin/env bash
set -Eeuo pipefail

# ==== Baked-in values from build time ====
export VENV_DIR="${VENV_DIR_BAKED}"
export PY_VERSION="${PY_VERSION_BAKED}"

# ==== Runtime tunables ====
PASSWORD="${PASSWORD:-}"                 # empty => no password
PORT="${PORT:-10000}"
FEATURE_DIR=${FEATURE_DIR:-.}
PATH="${VENV_DIR}/bin:${PATH}"

# NEW: make venv kernels visible to any Jupyter process
export JUPYTER_PATH="${VENV_DIR}/share/jupyter:/usr/local/share/jupyter:/usr/share/jupyter${JUPYTER_PATH:+:$JUPYTER_PATH}"

# NEW: use the shared extensions dir at runtime so preinstalled extensions are available on first run
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
bind-addr: 0.0.0.0:${PORT}
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
  "python.terminal.activateEnvironment": true
}
JSON

sudo chown -R "coder:coder" "$CSHOME/.config"
sudo chown -R "coder:coder" "$CSHOME/.local"
sudo chown -R "coder:coder" "$VENV_DIR" || true

echo "Starting code-server. This may take sometime ..."
exec sudo -u "$CSUSER" -H env PATH="$VENV_DIR/bin:$PATH" PASSWORD="$PASSWORD" JUPYTER_PATH="$JUPYTER_PATH" \
  code-server --extensions-dir "$CODESERVER_EXTENSION_DIR" \
              --bind-addr "0.0.0.0:${PORT}" --auth "$AUTH" "$CSHOME/workspace"
LAUNCH
chmod 755 /usr/local/bin/codeserver

cat <<EOF

✅ Setup complete.

Start:
  /usr/local/bin/codeserver

Open:
  https://localhost:${PORT}/

Auth mode:
  $( [[ -z "$PASSWORD" ]] && echo "No password (auth: none)" || echo "Password set (auth: password)" )

Kernels available (scoped to venv):
  - Python 3 (venv)
  - bash
EOF
