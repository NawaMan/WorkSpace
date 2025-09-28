#!/usr/bin/env bash
set -Eeuo pipefail

# -------------------------------------------------
# brew-setup.sh — Install Homebrew (macOS & Linux)
#
# Strategy (mirrors your JDK script style):
#   • Safe logging + strict mode
#   • OS/arch detection & sensible prefixes
#   • Package-manager bootstrap of prerequisites
#   • Non-interactive official installer
#   • PATH & environment wiring (system-wide when possible)
#   • Idempotent: re-runs are safe
#
# Usage examples:
#   ./brew-setup.sh                         # auto prefix per OS/arch
#   ./brew-setup.sh /custom/prefix          # force install prefix (advanced)
#   ./brew-setup.sh --no-doctor             # skip brew doctor
#   ./brew-setup.sh --only-paths            # just (re)write profile PATHs
#
# Notes:
#   • Do NOT run the installer as root. We only use sudo for OS packages
#     and system profile files when available.
#   • On Linux, default prefix is /home/linuxbrew/.linuxbrew
#   • On macOS: arm64 → /opt/homebrew, x86_64 → /usr/local
# -------------------------------------------------

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }
die() { echo "❌ $*" >&2; exit 1; }

# --- CLI args ---
CUSTOM_PREFIX=""
RUN_DOCTOR=1
ONLY_PATHS=0
for arg in "${@:-}"; do
  case "${arg}" in
    --no-doctor) RUN_DOCTOR=0 ;;
    --only-paths) ONLY_PATHS=1 ;;
    /*) CUSTOM_PREFIX="${arg}" ;;
    -h|--help)
      cat <<EOF
brew-setup.sh — Install Homebrew (macOS & Linux)

USAGE:
  ./brew-setup.sh [INSTALL_PREFIX] [--no-doctor] [--only-paths]

OPTIONS:
  INSTALL_PREFIX   Optional explicit Homebrew prefix (advanced)
  --no-doctor      Skip 'brew doctor' at the end
  --only-paths     Don't install; only (re)write profile PATH entries
EOF
      exit 0
      ;;
  esac
done

# --- OS / arch detection ---
OS="$(uname -s)"
ARCH="$(uname -m)"
case "${OS}" in
  Darwin) PLATFORM=macOS ;;
  Linux)  PLATFORM=Linux ;;
  *) die "Unsupported OS: ${OS}" ;;
esac

# --- Determine prefix ---
if [[ -n "${CUSTOM_PREFIX}" ]]; then
  HOMEBREW_PREFIX="${CUSTOM_PREFIX}"
else
  if [[ "${PLATFORM}" == "macOS" ]]; then
    if [[ "${ARCH}" == "arm64" ]]; then
      HOMEBREW_PREFIX="/opt/homebrew"
    else
      HOMEBREW_PREFIX="/usr/local"
    fi
  else
    HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
  fi
fi

# --- Sudo helper (for system package install / profile.d writes) ---
SUDO=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  fi
fi

# --- Write profile fragments ---
write_profiles() {
  local prefix="$1"
  local brew_bin="$1/bin"

  log "Writing profile entries for Homebrew at ${prefix} ..."

  # System-wide profile (best effort)
  if [[ -n "$SUDO" ]]; then
    ${SUDO} mkdir -p /etc/profile.d || true
    ${SUDO} tee /etc/profile.d/99-brew.sh >/dev/null <<EOF
# ---- Homebrew (system-wide) ----
if [ -d "${prefix}" ]; then
  export HOMEBREW_PREFIX="${prefix}"
  export PATH="${brew_bin}:\$PATH"
  # Prefer brewed manpages and completions when present
  export MANPATH="${prefix}/share/man:\${MANPATH:-}"
  export INFOPATH="${prefix}/share/info:\${INFOPATH:-}"
fi
# ---- end Homebrew ----
EOF
    ${SUDO} chmod 0644 /etc/profile.d/99-brew.sh || true
  fi

  # User shells
  for f in "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.profile"; do
    [[ -e "$f" ]] || touch "$f"
    if ! grep -q "HOMEBREW_PREFIX=\"${prefix}\"" "$f" 2>/dev/null; then
      cat >>"$f" <<EOF
# ---- Homebrew (user) ----
if [ -d "${prefix}" ]; then
  export HOMEBREW_PREFIX="${prefix}"
  export PATH="${brew_bin}:\$PATH"
  export MANPATH="${prefix}/share/man:\${MANPATH:-}"
  export INFOPATH="${prefix}/share/info:\${INFOPATH:-}"
fi
# ---- end Homebrew ----
EOF
    fi
  done
}

# If only writing PATHs, do it and exit
if [[ "$ONLY_PATHS" -eq 1 ]]; then
  write_profiles "${HOMEBREW_PREFIX}"
  log "Done writing PATH/profile entries. Open a new shell to pick them up."
  exit 0
fi

# --- Preflight checks ---
if [[ $EUID -eq 0 ]]; then
  die "Do NOT run Homebrew installation as root. Re-run this script as a normal user. We'll use sudo only for OS packages."
fi

# Idempotency: if brew exists and matches prefix, skip install
if command -v brew >/dev/null 2>&1; then
  EXISTING_PREFIX="$(brew --prefix 2>/dev/null || true)"
  if [[ -d "${EXISTING_PREFIX}" ]]; then
    log "Homebrew already present at ${EXISTING_PREFIX}. Skipping installer."
    write_profiles "${EXISTING_PREFIX}"
    if [[ "$RUN_DOCTOR" -eq 1 ]]; then
      log "Running 'brew update' and 'brew doctor' ..."
      brew update || true
      brew doctor || true
    fi
    log "✅ Finished (existing install)."
    exit 0
  fi
fi

# --- OS prerequisites ---
install_linux_prereqs() {
  log "Installing Linux prerequisites (curl, git, build tools, etc.) ..."
  if command -v apt-get >/dev/null 2>&1; then
    ${SUDO} apt-get update
    ${SUDO} apt-get install -y --no-install-recommends \
      build-essential curl file git ca-certificates procps
  elif command -v dnf >/dev/null 2>&1; then
    ${SUDO} dnf -y install \
      gcc-c++ make curl file git ca-certificates procps-ng
  elif command -v yum >/dev/null 2>&1; then
    ${SUDO} yum -y install \
      gcc-c++ make curl file git ca-certificates procps-ng || \
    ${SUDO} yum -y install \
      gcc-c++ make curl file git ca-certificates procps
  elif command -v zypper >/dev/null 2>&1; then
    ${SUDO} zypper --non-interactive install \
      gcc-c++ make curl file git ca-certificates procps
  elif command -v pacman >/dev/null 2>&1; then
    ${SUDO} pacman -Sy --noconfirm --needed base-devel curl git
  elif command -v apk >/dev/null 2>&1; then
    # Alpine is not officially supported by Homebrew (musl). Best-effort only.
    ${SUDO} apk add --no-cache build-base curl git file procps
    log "⚠️ Alpine/musl is not officially supported by Homebrew; proceed at your own risk."
  else
    log "⚠️ Unknown package manager. Skipping prerequisite installation."
  fi
}

if [[ "${PLATFORM}" == "Linux" ]]; then
  install_linux_prereqs
fi

# --- Run official Homebrew installer non-interactively ---
log "Running official Homebrew installer at prefix: ${HOMEBREW_PREFIX} ..."
export NONINTERACTIVE=1
# The installer determines prefix automatically, but we export to hint/force where supported
export HOMEBREW_PREFIX
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# --- Post-install sanity ---
if [[ ! -x "${HOMEBREW_PREFIX}/bin/brew" ]]; then
  # Try typical fallback locations just in case
  if [[ -x /opt/homebrew/bin/brew ]]; then HOMEBREW_PREFIX="/opt/homebrew"; fi
  if [[ -x /usr/local/bin/brew ]]; then HOMEBREW_PREFIX="/usr/local"; fi
fi
[[ -x "${HOMEBREW_PREFIX}/bin/brew" ]] || die "brew binary not found after install. Check installer logs above."

# Add to PATH now for current shell
export PATH="${HOMEBREW_PREFIX}/bin:${PATH}"

# --- Write profiles & finish ---
write_profiles "${HOMEBREW_PREFIX}"

log "Updating Homebrew ..."
brew update || true

if [[ "$RUN_DOCTOR" -eq 1 ]]; then
  log "Running 'brew doctor' (optional) ..."
  brew doctor || true
fi

# --- Summary ---
cat <<EOF
✅ Homebrew installed.
   Prefix       = ${HOMEBREW_PREFIX}
   Brew binary  = ${HOMEBREW_PREFIX}/bin/brew
   System PATH  = /etc/profile.d/99-brew.sh (if sudo available)
   User PATHs   = ~/.bashrc, ~/.zshrc, ~/.profile, etc. (appended)

Tip: open a new shell or 'source' your shell rc to pick up PATH changes.
Examples:
  brew --version
  brew doctor
  brew install gh
EOF
