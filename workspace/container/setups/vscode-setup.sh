#!/usr/bin/env bash
# vscode-setup.sh — Install Visual Studio Code (DEB, no snap)
# Adds: Jupyter Notebook + Bash kernel setup (for VS Code Jupyter extension)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# ---- root check ----
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "🔧 Installing Visual Studio Code (no snap)…"

# prereqs
apt-get update
apt-get install -y curl ca-certificates gnupg python3 python3-venv python3-pip

# add Microsoft’s key
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
chmod 0644 /etc/apt/keyrings/packages.microsoft.gpg

# clean old repo entries
for f in /etc/apt/sources.list \
         /etc/apt/sources.list.d/*.list \
         /etc/apt/sources.list.d/*.sources; do
  [[ -f "$f" ]] && sed -i '/packages\.microsoft\.com\/repos\/code/d' "$f" || true
done
rm -f /etc/apt/sources.list.d/vscode.list /etc/apt/sources.list.d/vscode.sources || true

# add repo
arch="$(dpkg --print-architecture)"
cat > /etc/apt/sources.list.d/vscode.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main
EOF
chmod 0644 /etc/apt/sources.list.d/vscode.list

# install VS Code
apt-get clean
rm -rf /var/lib/apt/lists/*
apt-get update
apt-get install -y code
echo "✅ VS Code installed"

# ---- Jupyter + Bash kernel setup ----
echo "🔧 Installing Jupyter + Bash kernel…"

VENV_DIR="/opt/venvs/py3"
mkdir -p "$(dirname "$VENV_DIR")"

if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel
"$VENV_DIR/bin/pip" install jupyter ipykernel bash_kernel

# Register both kernels system-wide
"$VENV_DIR/bin/python" -m ipykernel install --sys-prefix --name=python3 --display-name="Python 3 (venv)"
"$VENV_DIR/bin/python" -m bash_kernel.install --sys-prefix

# Make Jupyter path globally visible for VS Code
PROFILE_FILE="/etc/profile.d/99-vscode-jupyter.sh"
cat > "$PROFILE_FILE" <<EOF
# Added by vscode-setup.sh
export VENV_DIR="$VENV_DIR"
export PATH="\$VENV_DIR/bin:\$PATH"
export JUPYTER_PATH="\$VENV_DIR/share/jupyter:/usr/local/share/jupyter:/usr/share/jupyter:\${JUPYTER_PATH:-}"
EOF

echo "✅ Jupyter + Bash kernel ready for VS Code"

# wrapper (always no-sandbox in container)
cat >/usr/local/bin/code <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/code \
  --no-sandbox \
  --disable-gpu \
  --no-first-run \
  --no-default-browser-check \
  --password-store=basic \
  --user-data-dir="${HOME}/.vscode-data" \
  "$@"
EOF
chmod 0755 /usr/local/bin/code

# fix desktop launcher if exists
if [[ -f /usr/share/applications/code.desktop ]]; then
  sed -i 's#^Exec=.*#Exec=/usr/local/bin/code %F#' /usr/share/applications/code.desktop || true
fi

echo "✅ VS Code configured to use --no-sandbox by default"
echo "✅ Environment prepared for Jupyter notebooks + Bash kernel"

cat <<EOF

🎉 Setup complete!

You can now open VS Code and install:
  • ms-toolsai.jupyter
  • ms-python.python

Your Jupyter kernels available:
  - Python 3 (venv)
  - Bash

To verify inside VS Code:
  1. Open a .ipynb notebook
  2. Select 'Python 3 (venv)' or 'Bash' kernel
EOF
