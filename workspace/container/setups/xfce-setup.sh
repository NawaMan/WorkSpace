#!/usr/bin/env bash
# xfce-setup.sh — root-only installer for XFCE + VNC + noVNC
# Installs deps, writes /etc/profile.d/99-custom.sh, and creates /usr/local/bin/start-xfce
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# ---- root check ----
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- configurable args ----
DESKTOP_PACKAGES="${DESKTOP_PACKAGES:-xfce4 xfce4-terminal}"
VNC_STACK_PACKAGES="${VNC_STACK_PACKAGES:-tigervnc-standalone-server novnc websockify dbus-x11}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-x11-xserver-utils curl locales software-properties-common}"
PROFILE_FILE="${PROFILE_FILE:-/etc/profile.d/99-custom.sh}"

DEFAULT_DISPLAY="${DEFAULT_DISPLAY:-:1}"
DEFAULT_GEOMETRY="${DEFAULT_GEOMETRY:-1280x800}"
DEFAULT_NOVNC_PORT="${DEFAULT_NOVNC_PORT:-10000}"
DEFAULT_VNC_PORT="${DEFAULT_VNC_PORT:-5901}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-}"

# ---- install base packages ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y $DESKTOP_PACKAGES $VNC_STACK_PACKAGES $EXTRA_PACKAGES
apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- sanity check for noVNC ----
if [[ ! -d /usr/share/novnc ]]; then
  echo "❌ /usr/share/novnc not found" >&2
  exit 2
fi

# ---- Make autoconnect entrypoint for noVNC ----
cat >/usr/share/novnc/index.html <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>noVNC</title>
<script>
  const host = location.hostname || 'localhost';
  const port = location.port || '6080';
  const params = new URLSearchParams({
    autoconnect: '1',
    host,
    port,
    path: 'websockify',
    resize: 'scale'
  });
  location.replace('vnc.html?' + params.toString());
</script>
HTML

# ---- profile snippet ----
cat > "${PROFILE_FILE}" <<EOF
# XFCE over VNC/noVNC defaults
export DISPLAY=${DEFAULT_DISPLAY}
export GEOMETRY=\${GEOMETRY:-${DEFAULT_GEOMETRY}}
export NOVNC_PORT=\${NOVNC_PORT:-${DEFAULT_NOVNC_PORT}}
export VNC_PORT=\${VNC_PORT:-${DEFAULT_VNC_PORT}}
# export VNC_PASSWORD=change-me   # to require password
# export VNC_PASSWORD=            # leave empty (or "none") to disable password

alias desktop-start='start-xfce'
EOF
chmod 0644 "${PROFILE_FILE}"

# ---- start-xfce (foreground only) ----
cat > /usr/local/bin/start-xfce <<'EOF'
#!/usr/bin/env bash
# start-xfce — foreground-only; Ctrl+C to stop
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

: "${DISPLAY:=:1}"
: "${GEOMETRY:=1280x800}"
: "${NOVNC_PORT:=10000}"
: "${VNC_PASSWORD:=}"
: "${KEYRING_MODE:=basic}"   # basic | disable | keep

# infer VNC port
if [[ -z "${VNC_PORT:-}" ]]; then
  if [[ "$DISPLAY" =~ :([0-9]+) ]]; then
    VNC_PORT="$((5900 + ${BASH_REMATCH[1]}))"
  else
    VNC_PORT=5901
  fi
fi

: "${HOME:?HOME must be set and writable}"

# runtime dir
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

# --- keyring behavior (per-session) -----------------------------------------
# 'basic' and 'disable' both neuter the keyring so apps won't prompt.
case "${KEYRING_MODE}" in
  basic|disable)
    # Stop apps (VS Code/Chrome/etc.) from talking to gnome-keyring/libsecret
    export GNOME_KEYRING_CONTROL=/nonexistent
    unset GNOME_KEYRING_PID SSH_AUTH_SOCK

    # Also hide the per-user autostarts (so daemon won't launch under XFCE)
    mkdir -p "${HOME}/.config/autostart"
    for comp in pkcs11 secrets ssh; do
      cat > "${HOME}/.config/autostart/gnome-keyring-${comp}.desktop" <<AUTOSTART
[Desktop Entry]
Type=Application
Name=GNOME Keyring: ${comp}
Exec=/usr/bin/gnome-keyring-daemon --start --components=${comp}
Hidden=true
X-GNOME-Autostart-enabled=false
AUTOSTART
    done
    ;;
  keep)
    # Do nothing; you may see the "Default keyring" password prompt on first use.
    :
    ;;
  *)
    echo "⚠️ Unknown KEYRING_MODE='${KEYRING_MODE}', defaulting to 'basic'"
    export GNOME_KEYRING_CONTROL=/nonexistent
    unset GNOME_KEYRING_PID SSH_AUTH_SOCK
    ;;
esac
# ---------------------------------------------------------------------------

# pick vnc binary
VNCBIN="$(command -v tigervncserver || command -v vncserver || true)"
if [[ -z "$VNCBIN" ]]; then
  echo "❌ tigervncserver not found" >&2
  exit 3
fi

# auth
mkdir -p "${HOME}/.vnc"
VNCAUTH_OPTS=()
if [[ -n "${VNC_PASSWORD}" && "${VNC_PASSWORD,,}" != "none" ]]; then
  if [[ ! -s "${HOME}/.vnc/passwd" ]]; then
    echo "$VNC_PASSWORD" | vncpasswd -f > "${HOME}/.vnc/passwd"
    chmod 600 "${HOME}/.vnc/passwd"
  fi
else
  VNCAUTH_OPTS+=( -SecurityTypes=None )
  rm -f "${HOME}/.vnc/passwd" 2>/dev/null || true
fi

# xstartup
XSTART="${HOME}/.vnc/xstartup"
if [[ ! -x "$XSTART" ]]; then
  cat > "$XSTART" <<'XEOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
xsetroot -solid grey
exec dbus-launch --exit-with-session startxfce4
XEOF
  chmod +x "$XSTART"
fi

# start vnc
if "$VNCBIN" -list 2>/dev/null | grep -qE "^[[:space:]]*${DISPLAY}[[:space:]]"; then
  echo "ℹ️  VNC already running on ${DISPLAY}"
else
  "$VNCBIN" "$DISPLAY" -geometry "$GEOMETRY" -localhost yes "${VNCAUTH_OPTS[@]}"
fi

# start noVNC in foreground
echo "🌐 noVNC: http://localhost:${NOVNC_PORT}/vnc.html?autoconnect=1&host=localhost&port=${NOVNC_PORT}&path=websockify&resize=scale"
trap 'echo; echo "🛑 stopping…"; "$VNCBIN" -kill "$DISPLAY" || true; exit 0' INT TERM
exec websockify --web=/usr/share/novnc "0.0.0.0:${NOVNC_PORT}" "localhost:${VNC_PORT}"
EOF
chmod 0755 /usr/local/bin/start-xfce


# ---- keyring behavior (disable | basic | keep) ----
: "${KEYRING_MODE:=basic}"

case "${KEYRING_MODE}" in
  disable)
    echo "🔒 Disabling GNOME keyring (packages + autostart)…"
    apt-get remove -y gnome-keyring seahorse || true
    # Hide any leftover autostart files so it never launches
    mkdir -p /etc/xdg/autostart
    for f in /etc/xdg/autostart/gnome-keyring*.desktop; do
      [[ -f "$f" ]] && sed -i 's/^Hidden=.*/Hidden=true/; t; $aHidden=true' "$f" || true
    done
    ;;

  basic)
    echo "🔒 Forcing basic password storage (no keyring prompts)…"
    # Make sure the daemon doesn't get picked up
    echo 'export GNOME_KEYRING_CONTROL=/nonexistent' >> "${PROFILE_FILE}"
    echo 'unset GNOME_KEYRING_PID SSH_AUTH_SOCK' >> "${PROFILE_FILE}"
    ;;

  keep)
    echo "🔒 Keeping GNOME keyring (you may see the “Default keyring” prompt on first use)…"
    ;;

  *)
    echo "⚠️ Unknown KEYRING_MODE='${KEYRING_MODE}', defaulting to 'basic'"
    echo 'export GNOME_KEYRING_CONTROL=/nonexistent' >> "${PROFILE_FILE}"
    echo 'unset GNOME_KEYRING_PID SSH_AUTH_SOCK' >> "${PROFILE_FILE}"
    ;;
esac

# ---- summary ----
cat <<EOF

✅ Installed: $DESKTOP_PACKAGES
✅ VNC stack: $VNC_STACK_PACKAGES
✅ Extras:    $EXTRA_PACKAGES
✅ Profile:   ${PROFILE_FILE}
✅ Binary:    /usr/local/bin/start-xfce

Defaults:
  DISPLAY=${DEFAULT_DISPLAY}
  GEOMETRY=${DEFAULT_GEOMETRY}
  NOVNC_PORT=${DEFAULT_NOVNC_PORT}
  VNC_PORT=${DEFAULT_VNC_PORT}
  VNC_PASSWORD=${DEFAULT_VNC_PASSWORD}

Usage:
  # as NON-root user
  . ${PROFILE_FILE}     # usually auto-sourced
  start-xfce            # runs in foreground; Ctrl+C to stop
EOF
