#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [<ZIG_VERSION>] [--zig-version <ZIG_VERSION>] [--no-verify]

Examples:
  $0                          # install default (latest stable)
  $0 0.14.1                   # pin a version
  $0 --zig-version 0.15.1     # equivalent
  $0 0.15.1 --no-verify       # skip minisign verification
USAGE
}

# --- root check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# --- defaults ---
ZIG_DEFAULT_VERSION="${ZIG_DEFAULT_VERSION:-0.15.1}"   # latest stable on 2025-09-26
ZIG_VERSION_INPUT="${1:-}"
if [[ "${ZIG_VERSION_INPUT}" =~ ^- ]] ; then ZIG_VERSION_INPUT=""; fi

NO_VERIFY=0
# parse flags (+ optional positional version)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zig-version) shift; ZIG_VERSION_INPUT="${1:-}"; shift ;;
    --no-verify)   NO_VERIFY=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)
      if [[ -z "${ZIG_VERSION_INPUT}" ]]; then ZIG_VERSION_INPUT="$1"; shift
      else echo "❌ Unknown argument: $1"; usage; exit 2; fi
      ;;
  esac
done
ZIG_VERSION="${ZIG_VERSION_INPUT:-$ZIG_DEFAULT_VERSION}"

# --- arch mapping ---
dpkg_arch="$(dpkg --print-architecture)"
case "$dpkg_arch" in
  amd64) ZIG_ARCH="x86_64" ;;
  arm64) ZIG_ARCH="aarch64" ;;
  *) echo "❌ Unsupported architecture: $dpkg_arch (supported: amd64, arm64)" >&2; exit 2 ;;
esac

INSTALL_PARENT=/opt/zig
TARGET_DIR="${INSTALL_PARENT}/zig-${ZIG_VERSION}"
LINK_DIR=/opt/zig-stable
BASE_URL="https://ziglang.org/download/${ZIG_VERSION}"

# --- base tools ---
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates xz-utils tar coreutils minisign
rm -rf /var/lib/apt/lists/*

# --- try both historical filename patterns ---
fname_new="zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz"   # e.g. 0.15.1
fname_old="zig-linux-${ZIG_ARCH}-${ZIG_VERSION}.tar.xz"   # e.g. 0.14.0
TMP="/tmp"
download_one() {
  local name="$1"
  echo "Attempting download: ${BASE_URL}/${name}"
  curl -fsSL "${BASE_URL}/${name}" -o "${TMP}/${name}"
}

if ! download_one "$fname_new"; then
  echo "Fallback to legacy filename pattern..."
  if ! download_one "$fname_old"; then
    echo "❌ Could not download Zig ${ZIG_VERSION} for ${ZIG_ARCH} from ${BASE_URL}" >&2
    exit 3
  else
    FILENAME="$fname_old"
  fi
else
  FILENAME="$fname_new"
fi

# --- verify with minisign (optional) ---
# Zig's minisign public key (from the downloads page):
PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"  # :contentReference[oaicite:3]{index=3}
if [ "$NO_VERIFY" -eq 0 ]; then
  echo "Verifying minisign signature..."
  if curl -fsSL "${BASE_URL}/${FILENAME}.minisig" -o "${TMP}/${FILENAME}.minisig"; then
    minisign -Vm "${TMP}/${FILENAME}" -P "$PUBKEY" -x "${TMP}/${FILENAME}.minisig"
  else
    echo "⚠️  Signature file not found; proceeding without verification."
  fi
else
  echo "⚠️  Verification disabled by --no-verify."
fi

# --- install into versioned dir ---
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
tar -xJf "${TMP}/${FILENAME}" -C "$TARGET_DIR" --strip-components=1
rm -f "${TMP}/${FILENAME}" "${TMP}/${FILENAME}.minisig" || true

# --- stable symlink ---
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# --- expose binary for non-login shells ---
install -d /usr/local/bin
# zig binary sits at the bundle root (not under bin/)
ln -sfn "$LINK_DIR/zig" /usr/local/bin/zig

# --- login-shell env ---
cat >/etc/profile.d/99-zig.sh <<'EOF'
# ---- container defaults (safe to source multiple times) ----
export ZIG_HOME=/opt/zig-stable
export PATH="$ZIG_HOME:$PATH"
# ---- end defaults ----
EOF
chmod 0644 /etc/profile.d/99-zig.sh

echo "✅ Zig ${ZIG_VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   zig: "; /usr/local/bin/zig version || true
