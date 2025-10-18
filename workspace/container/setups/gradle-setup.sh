#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Config (override via env or first arg)
# --------------------------
GRADLE_VERSION="${GRADLE_VERSION:-${1:-9.1.0}}"
PROFILE_FILE="/etc/profile.d/62-ws-gradle.sh"


# ---- Create profile script ----
envsubst '' > "$PROFILE_FILE" <<"EOF"
if ! command -v gradle >/dev/null 2>&1; then
  source /etc/profile.d/60-ws-jdk.sh
  source /etc/profile.d/61-ws-sdkman.sh

  # Helper: run quietly; if non-zero, dump captured logs
  run_quiet_or_dump() {
    local out
    if ! out="$("$@" 2>&1)"; then
      printf '%s\n' "$out" >&2
      echo "❌ Command failed: $*" >&2
      return 1
    fi
  }

  # (optional) ensure noninteractive SDKMAN config
  mkdir -p "${HOME}/.sdkman/etc"
  printf '%s\n' \
    "sdkman_auto_answer=true" \
    "sdkman_auto_selfupdate=false" \
    "sdkman_insecure_ssl=false" \
    > "${HOME}/.sdkman/etc/config"

  # Quiet on success, verbose on failure:
  run_quiet_or_dump sdk install gradle "${GRADLE_VERSION}"
  run_quiet_or_dump sdk default gradle "${GRADLE_VERSION}"
fi
EOF

chmod 755 "$PROFILE_FILE"
echo "✅ Gradle installer ready. It will bootstrap on next login shell or \`source ${PROFILE_FILE}\` to use now."
