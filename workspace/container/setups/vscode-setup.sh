#!/usr/bin/env bash
# vscode-setup.sh — Install Visual Studio Code (DEB, no snap)
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
apt-get install -y curl ca-certificates gnupg

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

# install
apt-get clean
rm -rf /var/lib/apt/lists/*
apt-get update
apt-get install -y code
echo "✅ VS Code installed"

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
