#!/usr/bin/env bash
# setup-code-server-jupyter.sh
# Installs code-server + Jupyter (Python venv + Bash kernel) on Ubuntu
# Auth behavior:
#   - If PASSWORD is empty or unset -> auth: none (no password)
#   - If PASSWORD is set           -> auth: password (value = PASSWORD)
set -Eeuo pipefail

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
REMOVE_SYSTEM_KERNEL="${REMOVE_SYSTEM_KERNEL:-true}"  # remove system python3 kernelspec
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
echo "    REMOVE_SYSTEM_KERNEL=$REMOVE_SYSTEM_KERNEL"

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

echo "[1/9] Install prerequisites…"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  curl ca-certificates git bash tini jq \
  python3 python3-venv python3-pip
rm -rf /var/lib/apt/lists/*

echo "[2/9] Install code-server…"
if ! command -v code-server >/dev/null 2>&1; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi
command -v code-server >/dev/null

echo "[3/9] Create Jupyter venv at ${VENV_DIR}…"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel

echo "[4/9] Install Jupyter + kernels in venv…"
"$VENV_DIR/bin/pip" install jupyter bash_kernel ipykernel
"$VENV_DIR/bin/python" -m bash_kernel.install --sys-prefix
"$VENV_DIR/bin/python" -m ipykernel install --sys-prefix \
  --name=python3 --display-name="Python 3 (venv)"

# Pre-create config dirs for CS_USER and ensure ownership (fixes EACCES)
mkdir -p "$CS_HOME/.config" "$CS_HOME/.local/share/code-server"
chown -R "$CS_USER:$CS_USER" "$CS_HOME/.config" "$CS_HOME/.local"

echo "[5/9] Install VS Code extensions (as ${CS_USER})…"
EXT_CMDS='code-server --install-extension ms-toolsai.jupyter && code-server --install-extension ms-python.python'
if command -v sudo >/dev/null 2>&1; then
  sudo -u "$CS_USER" -H bash -lc "$EXT_CMDS"
else
  su - "$CS_USER" -s /bin/bash -c "$EXT_CMDS"
fi

echo "[6/9] Write code-server config for ${CS_USER}…"
mkdir -p "$CS_HOME/.config/code-server"
CONFIG_FILE="$CS_HOME/.config/code-server/config.yaml"
if [[ -z "$PASSWORD" ]]; then
  cat >"$CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:${PORT}
auth: none
cert: false
EOF
else
  cat >"$CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:${PORT}
auth: password
password: ${PASSWORD}
cert: false
EOF
fi
chown -R "$CS_USER:$CS_USER" "$CS_HOME/.config"

# VS Code (code-server) User settings (force venv + local Jupyter + filter kernels)
CS_SETTINGS_DIR="$CS_HOME/.local/share/code-server/User"
mkdir -p "$CS_SETTINGS_DIR"
SETTINGS_JSON="$CS_SETTINGS_DIR/settings.json"

TMP_SETTINGS="$(mktemp)"
cat >"$TMP_SETTINGS" <<'JSON'
{
  "python.defaultInterpreterPath": "__VENV__/bin/python",
  "jupyter.jupyterServerType": "local",
  "jupyter.kernels.filter": [
    "Python 3 (venv)",
    "bash"
  ]
}
JSON
# Replace placeholder with actual venv path
sed -i "s#__VENV__#${VENV_DIR//\//\\/}#g" "$TMP_SETTINGS"

if [[ -s "$SETTINGS_JSON" && -x "$(command -v jq || true)" ]]; then
  jq -s '.[0] * .[1]' "$SETTINGS_JSON" "$TMP_SETTINGS" > "${SETTINGS_JSON}.new" || cp "$TMP_SETTINGS" "${SETTINGS_JSON}.new"
  mv "${SETTINGS_JSON}.new" "$SETTINGS_JSON"
else
  cp "$TMP_SETTINGS" "$SETTINGS_JSON"
fi
rm -f "$TMP_SETTINGS"
chown -R "$CS_USER:$CS_USER" "$CS_HOME/.local"

# Workspace-level settings (if ~/workspace exists)
if [[ -d "$CS_HOME/workspace" ]]; then
  mkdir -p "$CS_HOME/workspace/.vscode"
  WS_SETTINGS="$CS_HOME/workspace/.vscode/settings.json"
  TMP_WS="$(mktemp)"
  cat >"$TMP_WS" <<'JSON'
{
  "python.defaultInterpreterPath": "__VENV__/bin/python",
  "jupyter.jupyterServerType": "local",
  "jupyter.kernels.filter": [
    "Python 3 (venv)",
    "bash"
  ]
}
JSON
  sed -i "s#__VENV__#${VENV_DIR//\//\\/}#g" "$TMP_WS"
  cp "$TMP_WS" "$WS_SETTINGS"
  rm -f "$TMP_WS"
  chown -R "$CS_USER:$CS_USER" "$CS_HOME/workspace/.vscode"
fi

echo "[7/9] (Optional) Remove system Python kernelspec to avoid wrong default…"
if [[ "$REMOVE_SYSTEM_KERNEL" == "true" ]]; then
  rm -rf /usr/share/jupyter/kernels/python3 2>/dev/null || true
  rm -rf /usr/local/share/jupyter/kernels/python3 2>/dev/null || true
fi

echo "[8/9] Create launcher: /usr/local/bin/codeserver"
cat > /usr/local/bin/codeserver <<'LAUNCH'
#!/usr/bin/env bash
set -Eeuo pipefail
PORT="${PORT:-10000}"
VENV_DIR="${VENV_DIR:-/opt/jupyter-venv}"
PASSWORD="${PASSWORD:-}"

# Ensure the venv is visible to Jupyter/VS Code
export PATH="${VENV_DIR}/bin:${PATH}"
export JUPYTER_PATH="${VENV_DIR}/share/jupyter"

# Force bind port and auth at runtime so old configs can't override them
if [[ -z "$PASSWORD" ]]; then
  exec code-server --bind-addr "0.0.0.0:${PORT}" --auth none
else
  exec code-server --bind-addr "0.0.0.0:${PORT}" --auth password
fi
LAUNCH
chmod 755 /usr/local/bin/codeserver

echo "[9/9] Permissions tidy…"
chown -R "$CS_USER:$CS_USER" "$VENV_DIR" || true

cat <<EOF

✅ Setup complete.

Start code-server as ${CS_USER}:
  sudo -u ${CS_USER} -H code-server-jupyter-start
  # or if you're already that user:
  code-server-jupyter-start

Open:
  http://localhost:${PORT}/

Auth mode:
  $( [[ -z "$PASSWORD" ]] && echo "No password (auth: none)" || echo "Password set (auth: password)" )

Kernels available (scoped to venv):
  - Python 3 (venv)
  - bash

If a notebook still shows Python 3.12.x, use the kernel picker and choose "Python 3 (venv)".
EOF

chmod 755 /usr/local/bin/codeserver
