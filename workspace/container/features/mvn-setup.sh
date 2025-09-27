#!/bin/bash
set -Eeuo pipefail

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

MAVEN_VERSION=${1:-3.9.11}
MAVEN_BASE_URL="https://downloads.apache.org/maven/maven-3"
INSTALL_DIR=/opt/maven
LINK_DIR=/opt/maven-stable

# --- Base tools ---
apt-get update
apt-get install -y --no-install-recommends curl tar ca-certificates
rm -rf /var/lib/apt/lists/*

# --- Download and install Maven ---
echo "Downloading Apache Maven $MAVEN_VERSION..."
curl -fsSL "${MAVEN_BASE_URL}/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
  -o /tmp/maven.tar.gz

mkdir -p "$INSTALL_DIR"
tar -xzf /tmp/maven.tar.gz -C "$INSTALL_DIR"
rm -f /tmp/maven.tar.gz

# --- Stable symlink directory for Maven ---
ln -sfn "$INSTALL_DIR/apache-maven-${MAVEN_VERSION}" "$LINK_DIR"

# --- Make mvn available even in non-login shells ---
install -d /usr/local/bin
ln -sfn "$LINK_DIR/bin/mvn" /usr/local/bin/mvn
ln -sfn "$LINK_DIR/bin/mvnDebug" /usr/local/bin/mvnDebug || true

# --- Optional environment for login shells ---
cat >/etc/profile.d/99-maven.sh <<'EOF'
# ---- container defaults (safe to source multiple times) ----
export MAVEN_HOME=/opt/maven-stable
export PATH="$MAVEN_HOME/bin:$PATH"
# ---- end defaults ----
EOF
chmod 0644 /etc/profile.d/99-maven.sh

echo "✅ Maven ${MAVEN_VERSION} installed. Try: mvn --version"
