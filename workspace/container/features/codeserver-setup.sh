#!/usr/bin/env bash
# setup-code-server-jupyter.sh
# Installs code-server + Jupyter (Python venv + Bash kernel) on Ubuntu
# Auth behavior:
#   - If PASSWORD is empty or unset -> auth: none (no password)
#   - If PASSWORD is set           -> auth: password (value = PASSWORD)
set -Eeuo pipefail

FEATURE_DIR=${FEATURE_DIR:-.}
${FEATURE_DIR}/python-setup.sh

### ---- Tunables (override with env) ----
PORT="${PORT:-10000}"                          # code-server port
PASSWORD="${PASSWORD:-}"                       # empty => no password
VENV_DIR="${VENV_DIR:-/opt/jupyter-venv}"      # Jupyter virtualenv location
# Auto-pick coder if present, else fall back to sudo user, else root
if [[ -z "${CS_USER:-}" ]]; then
  if id -u coder >/dev/null 2>&1; then
    CS_USER="coder"
  else
    CS_USER="${SUDO_USER:-root}"
  fi
fi
### --------------------------------------

echo "[*] Settings"
echo "    PORT=$PORT"
if [[ -z "$PASSWORD" ]]; then
  echo "    PASSWORD=<none> (auth: none)"
else
  echo "    PASSWORD=<hidden> (auth: password)"
fi
echo "    VENV_DIR=$VENV_DIR"
echo "    CS_USER=$CS_USER"

# Ensure CS_USER exists (if building in a base that doesn't provide it)
if ! id -u "$CS_USER" >/dev/null 2>&1; then
  echo "[0/9] Creating user $CS_USER…"
  useradd -m -s /bin/bash "$CS_USER"
fi

# Resolve CS_USER home
if [[ "$CS_USER" == "root" ]]; then
  CS_HOME="/root"
else
  CS_HOME="$(getent passwd "$CS_USER" | cut -d: -f6 || true)"
fi
if [[ -z "${CS_HOME:-}" ]]; then
  echo "[!] Could not resolve home for user '$CS_USER'"; exit 1
fi
mkdir -p "$CS_HOME"
chown -R "$CS_USER:$CS_USER" "$CS_HOME"

echo "[1/9] Install code-server…"
if ! command -v code-server >/dev/null 2>&1; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi
command -v code-server >/dev/null

echo "[2/9] Create Jupyter venv at ${VENV_DIR}…"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel

echo "[3/9] Install Jupyter + kernels in venv…"
"$VENV_DIR/bin/pip" install jupyter bash_kernel ipykernel
"$VENV_DIR/bin/python" -m bash_kernel.install --sys-prefix
"$VENV_DIR/bin/python" -m ipykernel install --sys-prefix \
  --name=python3 --display-name="Python 3 (venv)"

# Pre-create config dirs for CS_USER and ensure ownership (fixes EACCES)
mkdir -p "$CS_HOME/.config" "$CS_HOME/.local/share/code-server"
chown -R "$CS_USER:$CS_USER" "$CS_HOME/.config" "$CS_HOME/.local"

echo "[4/9] Install VS Code extensions (as ${CS_USER})…"
EXT_CMDS='code-server --install-extension ms-toolsai.jupyter && code-server --install-extension ms-python.python'
sudo -u "$CS_USER" -H bash -lc "$EXT_CMDS"




echo "[5/9] Create launcher: /usr/local/bin/codeserver"
cat > /usr/local/bin/codeserver <<'LAUNCH'
#!/usr/bin/env bash
set -Eeuo pipefail

export VENV_DIR="${VENV_DIR:-/opt/jupyter-venv}"

FEATURE_DIR=${FEATURE_DIR:-.}
PASSWORD="${PASSWORD:-}"

PORT="${PORT:-10000}"
PATH="${VENV_DIR}/bin:${PATH}"


#== Write code-server config for coder ==============================
mkdir -p "/home/coder/.config/code-server"
CONFIG_FILE="/home/coder/.config/code-server/config.yaml"
AUTH=none
PASS=$( [[ "$AUTH" == "password" ]] && echo "password: ${PASSWORD}" || echo "")

cat >"$CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:${PORT}
auth: ${AUTH}
${PASS}
cert: false
EOF

#== Settings ========================================================

SETTING_DIR=/home/coder/.local/share/code-server/User
SETTINGS_JSON="$SETTING_DIR/settings.json"
mkdir -p "$SETTING_DIR"


cat <<EOF | "${FEATURE_DIR}"/tools/apply-template.sh | \
  "${FEATURE_DIR}"/tools/json-merge.sh --into "$SETTINGS_JSON"
{
  "python.defaultInterpreterPath": "${VENV_DIR}/bin/python",
  "jupyter.jupyterServerType": "local"
}
EOF


sudo chown -R "coder:coder" "/home/coder/.config"
sudo chown -R "coder:coder" "/home/coder/.local"
sudo chown -R "coder:coder" "$VENV_DIR" || true


# Force bind port and auth at runtime so old configs can't override them
AUTH=$([ -z "$PASSWORD" ] && echo none || echo password)
echo "Starting code-server. This may take sometime ..."
exec code-server --bind-addr "0.0.0.0:${PORT}" --auth "$AUTH" "/home/coder/workspace"

LAUNCH
chmod 755 /usr/local/bin/codeserver

cat <<EOF

✅ Setup complete.

Start:
  /usr/local/bin/codeserver

Open:
  http://localhost:${PORT}/

Auth mode:
  $( [[ -z "$PASSWORD" ]] && echo "No password (auth: none)" || echo "Password set (auth: password)" )

Kernels available (scoped to venv):
  - Python 3 (venv)
  - bash
EOF

chmod 755 /usr/local/bin/codeserver
