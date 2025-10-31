
#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- Defaults ---
XXXXXX_VERSION="${1:-0.0.0}"      # Replace the variable

LEVEL=57                          # See README.md - Profile Ordering

STARTUP_FILE="/usr/share/startup.d/${LEVEL}-ws-xxxxxx--startup.sh"
PROFILE_FILE="/etc/profile.d/${LEVEL}-ws-xxxxxx--profile.sh"
STARTER_FILE="/usr/local/bin/xxxxxx"



# ==== Things to do once at the call time by root. ====





# ---- Create startup file: to be executed as normal user on first login ----
# The starter file will be run by the docker entrypoint -- container start.
export XXXXXX_VERSION
envsubst '$XXXXXX_VERSION' > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail


# ==== Things to do once at the docker start by user. ====
# - You can use $XXXXXX_VERSION in this block.
# - if the user stop and restart or pause and resume, 
#       this will be run again so make sure it is idempotent.
#
# If needed, you can use sentinel pattern.
# Example "run once" sentinel:
# SENTINEL="$HOME/.xxxxxx-startup-done"
# [[ -f "$SENTINEL" ]] && exit 0
# touch "$SENTINEL"


EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file: to be sourced at the beginning of a user shell session ----
envsubst '$XXXXXX_VERSION' > "${PROFILE_FILE}" <<'EOF'
# Profile: XXXXXX: $XXXXXX_VERSION

# ==== Things to do at shell login by user. ====
# - You can use $XXXXXX_VERSION in this block.
# - Try to make this lightweight.
# - Example action:
#     - export variable
#     - setup path -- case ":$PATH:" in *":/usr/local/bin:"*) ;; *) export PATH="/usr/local/bin:$PATH";; esac


EOF
chmod 644 "${PROFILE_FILE}"

# ---- Create starter file: a wrapper to the program installed so that we can do things before and after ----
envsubst '$XXXXXX_VERSION' > "${STARTER_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail


# ==== Things to do around the executable by user. ====
# - You can use $XXXXXX_VERSION in this block.
# - Hand off to the real binary (replace with actual path):
#     - exec /usr/local/bin/real-xxxxxx "$@"


EOF
chmod 755 "${STARTER_FILE}"


echo "✅ .... XXXXXX is installed ...."
echo "• Version: ${XXXXXX_VERSION}"
echo "• Startup file (container login) : ${STARTUP_FILE}"
echo "• Profile file (every user shell): ${PROFILE_FILE}"
echo "• Starter file (the executable)  : ${STARTER_FILE}"
echo ""
echo "You may source the profile above to start using in this session."
