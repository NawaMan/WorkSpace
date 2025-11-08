#!/bin/bash
set -Eeuo pipefail

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- config / defaults ----
GO_DEFAULT_VERSION="1.25.1"   # latest stable on 2025-09-26 (see go.dev/dl)
INSTALL_DIR=/opt/go
LINK_DIR=/opt/go-stable
GO_DL_BASE_PRIMARY="https://go.dev/dl"
GO_DL_BASE_FALLBACK="https://dl.google.com/go"
GO_JSON="$GO_DL_BASE_PRIMARY/?mode=json"

# ---- simple flag parser (positional still works) ----
GO_VERSION_INPUT="${1:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --go-version)
      GO_VERSION_INPUT="${2:-}"; shift 2;;
    -h|--help)
      echo "Usage: $0 [--go-version <x.y.z>]"; exit 0;;
    *)
      # Positional version (first non-flag)
      if [[ -z "${GO_VERSION_INPUT:-}" ]]; then GO_VERSION_INPUT="$1"; fi
      shift;;
  esac
done

# Normalize version (accept '1.25.1' or 'go1.25.1')
if [[ -n "${GO_VERSION_INPUT:-}" ]]; then
  GO_VERSION="${GO_VERSION_INPUT#go}"
else
  GO_VERSION="$GO_DEFAULT_VERSION"
fi

# Determine arch
dpkg_arch="$(dpkg --print-architecture)"
case "$dpkg_arch" in
  amd64) GO_ARCH="amd64" ;;
  arm64) GO_ARCH="arm64" ;;
  *)
    echo "❌ Unsupported architecture: $dpkg_arch (only amd64/arm64 supported)" >&2
    exit 2
    ;;
esac

# Base tools
apt-get update
apt-get install -y --no-install-recommends curl tar ca-certificates coreutils
rm -rf /var/lib/apt/lists/*

# Filenames & URLs
FILENAME="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
TMP_TARBALL="/tmp/${FILENAME}"

echo "Downloading Go ${GO_VERSION} (${GO_ARCH})..."
# Try primary, then fallback
if ! curl -fL "${GO_DL_BASE_PRIMARY}/${FILENAME}" -o "${TMP_TARBALL}"; then
  echo "Primary failed, trying fallback mirror..."
  curl -fL "${GO_DL_BASE_FALLBACK}/${FILENAME}" -o "${TMP_TARBALL}"
fi

# Try to fetch expected SHA256 from the official JSON (no jq dependency)
echo "Verifying checksum..."
EXPECTED_SHA256="$(curl -fsSL "$GO_JSON" \
  | tr ',' '\n' \
  | awk -v FNAME="\"filename\":\"${FILENAME}\"" '
      index($0, FNAME) { hit=1 }
      hit && /"sha256":/ {
        gsub(/.*"sha256":"|".*/, "", $0); print $0; exit
      }')"

if [[ -n "${EXPECTED_SHA256}" ]]; then
  ACTUAL_SHA256="$(sha256sum "${TMP_TARBALL}" | awk '{print $1}')"
  if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
    echo "❌ SHA256 mismatch for ${FILENAME}"
    echo "Expected: ${EXPECTED_SHA256}"
    echo "Actual:   ${ACTUAL_SHA256}"
    exit 3
  fi
else
  echo "⚠️  Could not obtain expected SHA256 from ${GO_JSON}; proceeding without verification."
fi

# Install to versioned folder and link stable
TARGET_DIR="${INSTALL_DIR}/go-${GO_VERSION}"
mkdir -p "${TARGET_DIR}"
tar -xzf "${TMP_TARBALL}" -C "${TARGET_DIR}" --strip-components=1
rm -f "${TMP_TARBALL}"

ln -sfn "${TARGET_DIR}" "${LINK_DIR}"

# Make go/gofmt available even in non-login shells
install -d /usr/local/bin
ln -sfn "${LINK_DIR}/bin/go"    /usr/local/bin/go
ln -sfn "${LINK_DIR}/bin/gofmt" /usr/local/bin/gofmt

# Optional environment for login shells
cat >/etc/profile.d/99-go--profile.sh <<'EOF'
# ---- container defaults (safe to source multiple times) ----
export GOROOT=/opt/go-stable
export PATH="$GOROOT/bin:$PATH"
export GOPATH="$(go env GOPATH)"
# ---- end defaults ----
EOF
chmod 0644 /etc/profile.d/99-go--profile.sh

echo "✅ Go ${GO_VERSION} installed at ${TARGET_DIR}"
echo "   Symlink: ${LINK_DIR}"
echo "   Binaries: /usr/local/bin/go, /usr/local/bin/gofmt"
echo "   Try: go version"
echo "   Set GOPATH: export GOPATH=\"\$(go env GOPATH)\""
echo ""
