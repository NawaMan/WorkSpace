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


echo "[1/9] Install code-server…"
if ! command -v code-server >/dev/null 2>&1; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi
command -v code-server >/dev/null

echo "[2/9] Create Jupyter venv at ${VENV_DIR}…"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel

echo "[3/9] Install Jupyter + kernels in venv…"
"$VENV_DIR/bin/pip"    install jupyter bash_kernel ipykernel
"$VENV_DIR/bin/python" -m bash_kernel.install --sys-prefix
"$VENV_DIR/bin/python" -m ipykernel install   --sys-prefix --name=python3 --display-name="Python 3 (venv)"


echo "[4/9] Create launcher: /usr/local/bin/codeserver"
cat > /usr/local/bin/codeserver <<'LAUNCH'
#!/usr/bin/env bash
set -Eeuo pipefail

export VENV_DIR="${VENV_DIR:-/opt/jupyter-venv}"

FEATURE_DIR=${FEATURE_DIR:-.}
PASSWORD="${PASSWORD:-}"

PORT="${PORT:-10000}"
PATH="${VENV_DIR}/bin:${PATH}"

CSUSER=coder
CSHOME=/home/$CSUSER



# Pre-create config dirs for CSUSER and ensure ownership (fixes EACCES)
mkdir -p "$CSHOME/.config" "$CSHOME/.local/share/code-server"


#== Install VS Code extensions (as ${CS_USER}) ================================
sudo -u "$CSUSER" -H bash -lc "
    code-server --install-extension ms-toolsai.jupyter && \
    code-server --install-extension ms-python.python
"


#== Write code-server config for coder ==============================
mkdir -p "$CSHOME/.config/code-server"
CONFIG_FILE="$CSHOME/.config/code-server/config.yaml"
AUTH=none
PASS=$( [[ "$AUTH" == "password" ]] && echo "password: ${PASSWORD}" || echo "")

cat >"$CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:${PORT}
auth: ${AUTH}
${PASS}
cert: false
EOF


#== Settings ========================================================
SETTING_DIR=$CSHOME/.local/share/code-server/User
SETTINGS_JSON="$SETTING_DIR/settings.json"
mkdir -p "$SETTING_DIR"


cat <<EOF | "${FEATURE_DIR}"/tools/apply-template.sh | \
  "${FEATURE_DIR}"/tools/json-merge.sh --into "$SETTINGS_JSON"
{
  "python.defaultInterpreterPath": "${VENV_DIR}/bin/python",
  "jupyter.jupyterServerType": "local"
}
EOF


sudo chown -R "coder:coder" "$CSHOME/.config"
sudo chown -R "coder:coder" "$CSHOME/.local"
sudo chown -R "coder:coder" "$VENV_DIR" || true


# Force bind port and auth at runtime so old configs can't override them
AUTH=$([ -z "$PASSWORD" ] && echo none || echo password)
echo "Starting code-server. This may take sometime ..."
exec code-server --bind-addr "0.0.0.0:${PORT}" --auth "$AUTH" "$CSHOME/workspace"

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
