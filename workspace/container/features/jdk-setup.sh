#!/bin/bash
set -Eeuo pipefail

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

JDK_VERSION=${1:-21}

# --- Base tools ---
apt-get update
apt-get install -y --no-install-recommends curl unzip zip ca-certificates
rm -rf /var/lib/apt/lists/*

# --- Choose shared, predictable locations for JBang state (must be EXPORTED) ---
export JBANG_DIR=/opt/jbang-home
export JBANG_CACHE_DIR=/opt/jbang-cache

# --- Install JBang system-wide (binary only) into our chosen JBANG_DIR ---
# The installer will place the launcher at $JBANG_DIR/bin/jbang thanks to the exported env vars.
curl -Ls https://sh.jbang.dev | bash -s - app setup
install -Dm755 "${JBANG_DIR}/bin/jbang" /usr/local/bin/jbang

# --- Make the state dirs writable for any runtime user (dev-friendly) ---
mkdir -p      "$JBANG_DIR" "$JBANG_CACHE_DIR"
chmod -R 0777 "$JBANG_DIR" "$JBANG_CACHE_DIR"

echo "Installing JDK $JDK_VERSION via JBang..."
jbang jdk install "$JDK_VERSION"
jbang jdk default "$JDK_VERSION" >/dev/null 2>&1 || true

echo Stable JAVA_HOME for tools
JDK_HOME="$(jbang jdk home "$JDK_VERSION")"
ln -snf "$JDK_HOME" /opt/jdk${JDK_VERSION}

export JAVA_HOME=/opt/jdk${JDK_VERSION}
export PATH="$JAVA_HOME/bin:$PATH"

# --- Shared shell config: create the file (no Dockerfile RUN here) ---
cat >/etc/profile.d/99-custom.sh <<EOF
# ---- container defaults (safe to source multiple times) ----
export JAVA_HOME=/opt/jdk${JDK_VERSION}
export PATH="$JAVA_HOME/bin:$PATH"
# ---- end defaults ----
EOF
chmod 0644 /etc/profile.d/99-custom.sh

echo "✅ JBang launcher installed to /usr/local/bin/jbang, /opt/jdk and shared dirs prepared."
