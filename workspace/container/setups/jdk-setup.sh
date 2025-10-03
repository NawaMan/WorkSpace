#!/bin/bash
set -Eeuo pipefail

# ---------------------------------------------
# jdk-setup.sh — Install JBang + chosen JDK
#
# Vendor selection:
#   1) CLI arg #2 (e.g., "graalvm") → sets JBANG_JDK_VENDOR
#   2) Existing JBANG_JDK_VENDOR env
#   3) Fallback default: temurin
#
# Usage:
#   sudo ./jdk-setup.sh                 # version=21, vendor=$JBANG_JDK_VENDOR or temurin
#   sudo ./jdk-setup.sh 25              # version=25, vendor from env/default
#   sudo ./jdk-setup.sh 25 graalvm      # version=25, vendor=graalvm (sets env for this run)
# ---------------------------------------------

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }
die() { echo "❌ $*" >&2; exit 1; }

# --- Root check ---
[[ "${EUID}" -eq 0 ]] || die "This script must be run as root (use sudo)."

# --- Inputs & vendor policy ---
JDK_VERSION="${1:-25}"
CLI_VENDOR="${2:-}"  # optional: temurin | graalvm | (any vendor JBang supports)
if [[ -n "$CLI_VENDOR" ]]; then
  export JBANG_JDK_VENDOR="$CLI_VENDOR"
fi
: "${JBANG_JDK_VENDOR:=temurin}"   # default if env not set
ACTIVE_VENDOR="$JBANG_JDK_VENDOR"

# --- Base tools ---
export DEBIAN_FRONTEND=noninteractive
log "Installing base packages..."
apt-get update
apt-get install -y --no-install-recommends curl unzip zip ca-certificates
rm -rf /var/lib/apt/lists/*

# --- JBang dirs ---
export JBANG_DIR=/opt/jbang-home
export JBANG_CACHE_DIR=/opt/jbang-cache
mkdir -p "$JBANG_DIR" "$JBANG_CACHE_DIR"
chmod -R 0777 "$JBANG_DIR" "$JBANG_CACHE_DIR"

# --- Install JBang (binary) ---
log "Installing JBang..."
curl -Ls https://sh.jbang.dev | bash -s - app setup
install -Dm755 "${JBANG_DIR}/bin/jbang" /usr/local/bin/jbang

# --- Install JDK (vendor controlled by JBANG_JDK_VENDOR) ---
log "Installing JDK ${JDK_VERSION} (vendor: ${ACTIVE_VENDOR}) via JBang..."
jbang jdk install "${JDK_VERSION}"

# Try to make it default (ok if multiple vendors exist)
jbang jdk default "${JDK_VERSION}" >/dev/null 2>&1 || true

# --- Resolve JAVA_HOME for this version (per active vendor selection) ---
JDK_HOME="$(jbang jdk home "${JDK_VERSION}")"
[[ -n "$JDK_HOME" && -d "$JDK_HOME" ]] || die "Could not resolve JDK home for ${JDK_VERSION} (${ACTIVE_VENDOR})."

# --- Stable symlinks ---
GENERIC_LINK="/opt/jdk${JDK_VERSION}"
VENDOR_LINK="/opt/jdk-${JDK_VERSION}-${ACTIVE_VENDOR}"
log "Creating symlinks: ${GENERIC_LINK} and ${VENDOR_LINK}"
ln -snf "$JDK_HOME" "$GENERIC_LINK"
ln -snf "$JDK_HOME" "$VENDOR_LINK"

# --- Export for current shell (this root shell) ---
export JAVA_HOME="$GENERIC_LINK"
export "JAVA_${JDK_VERSION}_HOME=$GENERIC_LINK"
export PATH="$JAVA_HOME/bin:$PATH"

# --- Optional extras for GraalVM ---
if [[ "${ACTIVE_VENDOR}" == "graalvm" ]]; then
  log "GraalVM selected; attempting to install native-image (optional)..."
  if command -v gu >/dev/null 2>&1; then
    gu install native-image || true
  elif [[ -x "${JAVA_HOME}/bin/gu" ]]; then
    "${JAVA_HOME}/bin/gu" install native-image || true
  else
    log "Graal 'gu' not found; skipping native-image."
  fi
fi

# --- Register with update-alternatives (immediate availability for all shells) ---
log "Registering JDK ${JDK_VERSION} with update-alternatives..."
update-alternatives --install /usr/bin/java   java   "${GENERIC_LINK}/bin/java"   20000
update-alternatives --install /usr/bin/javac  javac  "${GENERIC_LINK}/bin/javac"  20000
update-alternatives --install /usr/bin/jar    jar    "${GENERIC_LINK}/bin/jar"    20000
update-alternatives --install /usr/bin/jcmd   jcmd   "${GENERIC_LINK}/bin/jcmd"   20000
update-alternatives --install /usr/bin/jps    jps    "${GENERIC_LINK}/bin/jps"    20000
update-alternatives --install /usr/bin/jstack jstack "${GENERIC_LINK}/bin/jstack" 20000
# Set them explicitly to our freshly installed JDK
update-alternatives --set java   "${GENERIC_LINK}/bin/java"
update-alternatives --set javac  "${GENERIC_LINK}/bin/javac"  || true
update-alternatives --set jar    "${GENERIC_LINK}/bin/jar"    || true
update-alternatives --set jcmd   "${GENERIC_LINK}/bin/jcmd"   || true
update-alternatives --set jps    "${GENERIC_LINK}/bin/jps"    || true
update-alternatives --set jstack "${GENERIC_LINK}/bin/jstack" || true

# --- System-wide profile for future shells (nice env vars) ---
log "Writing /etc/profile.d/99-custom.sh ..."
cat >/etc/profile.d/99-custom.sh <<EOF
# ---- container defaults (safe to source multiple times) ----
export JAVA_HOME=${GENERIC_LINK}
export PATH="\$JAVA_HOME/bin:\$PATH"

# version-specific JAVA_<ver>_HOME
export JAVA_${JDK_VERSION}_HOME=${GENERIC_LINK}

# vendor-specific symlink for convenience
export JAVA_HOME_${JDK_VERSION}_VENDOR=${VENDOR_LINK}
# ---- end defaults ----
EOF
chmod 0644 /etc/profile.d/99-custom.sh

# --- Summary ---
echo "✅ JDK ${JDK_VERSION} (${ACTIVE_VENDOR}) installed."
echo "   JAVA_HOME = ${GENERIC_LINK}"
echo "   JAVA_${JDK_VERSION}_HOME = ${GENERIC_LINK}"
echo "   Vendor link = ${VENDOR_LINK}"
echo "   JBang launcher = /usr/local/bin/jbang"
echo "   Profile script = /etc/profile.d/99-custom.sh"
echo "   Alternatives:   $(command -v java) -> $(readlink -f "$(command -v java)")"
echo
echo "Tip: List available JDKs/vendors:"
echo "  jbang jdk list --available --show-details"
