#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Config (override via env or first arg)
# --------------------------
BREW_INSTALL_URL="${BREW_INSTALL_URL:-${1:-https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}}"
PROFILE_FILE="/etc/profile.d/57-ws-brew.sh"

# ---- Create profile script ----
envsubst '' > "$PROFILE_FILE" <<"EOF"
if ! command -v brew >/dev/null 2>&1; then
  # prevent re-entry if a subshell sources this again
  if [ -n "${BREW_BOOTSTRAP_IN_PROGRESS:-}" ]; then
    return
  fi
  export BREW_BOOTSTRAP_IN_PROGRESS=1

  run_quiet_or_dump() {
    set -o pipefail
    local out
    if ! out="$("$@" 2>&1)"; then
      printf '%s\n' "$out" >&2
      echo "❌ Command failed: $*" >&2
      return 1
    fi
  }

  export NONINTERACTIVE="${NONINTERACTIVE:-1}"
  export HOMEBREW_NO_ANALYTICS="${HOMEBREW_NO_ANALYTICS:-1}"
  export HOMEBREW_NO_ENV_HINTS="${HOMEBREW_NO_ENV_HINTS:-1}"
  export HOMEBREW_UPDATE_REPORT_ONLY_INSTALLED="${HOMEBREW_UPDATE_REPORT_ONLY_INSTALLED:-1}"
  : "${BREW_INSTALL_URL:=https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}"

  echo "📦 Installing Homebrew (first-run bootstrap)..."

  tmp="${TMPDIR:-/tmp}/brew-install.$$"
  # ⬇️ No login shell; call the downloader directly with a timeout
  if command -v curl >/dev/null 2>&1; then
    run_quiet_or_dump curl -fsSL --connect-timeout 10 --retry 3 --retry-delay 1 \
      -o "$tmp" "$BREW_INSTALL_URL"
  elif command -v wget >/dev/null 2>&1; then
    run_quiet_or_dump wget -q --timeout=15 --tries=3 -O "$tmp" "$BREW_INSTALL_URL"
  else
    echo "❌ Need curl or wget to install Homebrew." >&2
    unset BREW_BOOTSTRAP_IN_PROGRESS
    return 1
  fi

  run_quiet_or_dump bash "$tmp"
  rm -f "$tmp"

  # locate brew and load env
  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  elif [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  elif command -v brew >/dev/null 2>&1; then
    eval "$("$(command -v brew)" shellenv)"
  else
    echo "❌ Homebrew install finished but brew not found on disk." >&2
    unset BREW_BOOTSTRAP_IN_PROGRESS
    return 1
  fi

  echo "✅ Homebrew installed."
  unset BREW_BOOTSTRAP_IN_PROGRESS
fi

# Ensure brew env on every login (even if already installed)
if command -v brew >/dev/null 2>&1; then
  eval "$("$(command -v brew)" shellenv)"
fi

EOF

chmod 755 "$PROFILE_FILE"
echo "✅ Brew installer ready. It will bootstrap on next login shell or \`source ${PROFILE_FILE}\` to use now."
