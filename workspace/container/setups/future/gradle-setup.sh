#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <gradle-version>|latest] [--dist bin|all] [--user-home <path>]

Examples:
  $0                                # install default (8.10.2), bin distribution
  $0 --version latest               # install the latest Gradle
  $0 --version 8.7 --dist all       # install a specific version with sources/docs
  $0 --user-home /opt/gradle-cache  # set shared GRADLE_USER_HOME

Notes:
- Installs under /opt/gradle/gradle-<version> and links /opt/gradle-stable
- Adds /usr/local/bin/gradle wrapper so it works in non-login shells
- Respects existing JAVA_HOME; this script does not install Java
USAGE
}

# ---- root check ----
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- defaults ----
GRADLE_DEFAULT_VERSION="8.10.2"   # change when you want a newer pinned default
DIST_KIND="bin"                   # bin|all
GRADLE_USER_HOME_DEFAULT="/opt/gradle-user-home"

# ---- args ----
REQ_VERSION=""
USER_HOME="$GRADLE_USER_HOME_DEFAULT"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VERSION="${1:-}"; shift ;;
    --dist)    shift; DIST_KIND="${1:-bin}"; shift ;;
    --user-home) shift; USER_HOME="${1:-$GRADLE_USER_HOME_DEFAULT}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Resolve version (supports 'latest' via services.gradle.org)
if [[ -z "$REQ_VERSION" ]]; then
  VERSION="$GRADLE_DEFAULT_VERSION"
elif [[ "$REQ_VERSION" == "latest" ]]; then
  # Lightweight JSON parse without jq
  VERSION="$(curl -fsSL https://services.gradle.org/versions/current | grep -oP '"version"\s*:\s*"\K[^"]+')"
  [[ -n "$VERSION" ]] || { echo "❌ Failed to resolve latest Gradle version"; exit 1; }
else
  VERSION="$REQ_VERSION"
fi

case "$DIST_KIND" in
  bin|all) ;; 
  *) echo "❌ --dist must be 'bin' or 'all'"; exit 2 ;;
esac

# ---- paths ----
INSTALL_PARENT=/opt/gradle
TARGET_DIR="${INSTALL_PARENT}/gradle-${VERSION}"
LINK_DIR=/opt/gradle-stable
WRAPPER=/usr/local/bin/gradle

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl unzip ca-certificates coreutils
rm -rf /var/lib/apt/lists/*

# ---- prepare dirs ----
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR" "$INSTALL_PARENT" "$USER_HOME"
chmod -R 0777 "$USER_HOME" || true   # dev/CI friendly shared cache

# ---- download + verify ----
BASE_URL="https://services.gradle.org/distributions"
ZIP_NAME="gradle-${VERSION}-${DIST_KIND}.zip"
ZIP_URL="${BASE_URL}/${ZIP_NAME}"
SHA_URL="${ZIP_URL}.sha256"

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
echo "⬇️  Downloading ${ZIP_NAME} ..."
curl -fsSL "$ZIP_URL" -o "${tmpdir}/${ZIP_NAME}"
curl -fsSL "$SHA_URL" -o "${tmpdir}/${ZIP_NAME}.sha256"

echo "🔐 Verifying checksum ..."
( cd "$tmpdir" && sha256sum -c "${ZIP_NAME}.sha256" )

echo "📦 Installing Gradle ${VERSION} (${DIST_KIND}) ..."
unzip -q "${tmpdir}/${ZIP_NAME}" -d "$tmpdir"
# extracted folder is gradle-${VERSION}
mv "${tmpdir}/gradle-${VERSION}"/* "$TARGET_DIR"

# ---- stable link ----
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- login shell env (PATH + GRADLE_USER_HOME only) ----
cat >/etc/profile.d/99-gradle.sh <<EOF
# Gradle under /opt
export GRADLE_HOME=$LINK_DIR
export GRADLE_USER_HOME=${USER_HOME}
export PATH="\$GRADLE_HOME/bin:\$PATH"
EOF
chmod 0644 /etc/profile.d/99-gradle.sh

# ---- non-login wrapper ----
cat >"$WRAPPER" <<'EOF'
#!/bin/sh
: "${GRADLE_HOME:=/opt/gradle-stable}"
: "${GRADLE_USER_HOME:=/opt/gradle-user-home}"
export GRADLE_HOME GRADLE_USER_HOME PATH="$GRADLE_HOME/bin:$PATH"
exec "$GRADLE_HOME/bin/gradle" "$@"
EOF
chmod +x "$WRAPPER"

# ---- friendly summary ----
echo "✅ Gradle ${VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo "   GRADLE_USER_HOME = ${USER_HOME}"
echo -n "   gradle -v → "; "$WRAPPER" -v | head -n1 || true

cat <<'EON'
ℹ️ Ready to use:
- Try: gradle -v
- Works in login & non-login shells (wrapper primes PATH & GRADLE_USER_HOME).
- Use --dist all if you want sources/docs for IDEs.
- JAVA_HOME should point to your JDK; this script does not set/override it.

Tips:
- Speed up CI: mount a persistent GRADLE_USER_HOME volume at /opt/gradle-user-home
- Daemon opts: create /opt/gradle-user-home/gradle.properties or ~/.gradle/gradle.properties
EON
