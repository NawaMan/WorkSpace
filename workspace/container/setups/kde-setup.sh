#!/usr/bin/env bash
# kde-setup.sh — root-only installer for KDE Plasma + VNC + noVNC + Dolphin & Konsole pinned + NO LOCK SCREEN
# Installs deps, writes /etc/profile.d/99-ws-kde.sh, creates /usr/local/bin/start-kde,
# pins Dolphin and Konsole, and disables KDE screen locking (no password on lock).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# ---- root check ----
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- configurable args ----
KDE_PACKAGES="${KDE_PACKAGES:-plasma-desktop konsole dolphin kio-extras ffmpegthumbs kde-cli-tools}"
VNC_STACK_PACKAGES="${VNC_STACK_PACKAGES:-tigervnc-standalone-server novnc websockify dbus-x11}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-x11-xserver-utils curl locales software-properties-common}"
PROFILE_FILE="${PROFILE_FILE:-/etc/profile.d/55-ws-kde.sh}"

DEFAULT_DISPLAY="${DEFAULT_DISPLAY:-:1}"
DEFAULT_GEOMETRY="${DEFAULT_GEOMETRY:-1280x800}"
DEFAULT_NOVNC_PORT="${DEFAULT_NOVNC_PORT:-10000}"
DEFAULT_VNC_PORT="${DEFAULT_VNC_PORT:-5901}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-}"   # empty ⇒ NO VNC AUTH

# ---- install base packages ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
if ! apt-get install -y $KDE_PACKAGES $VNC_STACK_PACKAGES $EXTRA_PACKAGES; then
  echo "ℹ️ Falling back to alternate KDE package names…"
  apt-get install -y kde-plasma-desktop $VNC_STACK_PACKAGES $EXTRA_PACKAGES || \
  apt-get install -y plasma-desktop $VNC_STACK_PACKAGES $EXTRA_PACKAGES
fi
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
    resize: 'remote'
  });
  location.replace('vnc.html?' + params.toString());
</script>
HTML

# ---- profile snippet ----
cat > "${PROFILE_FILE}" <<EOF
# KDE Plasma over VNC/noVNC defaults
export DISPLAY=${DEFAULT_DISPLAY}
export GEOMETRY=\${GEOMETRY:-${DEFAULT_GEOMETRY}}
export NOVNC_PORT=\${NOVNC_PORT:-${DEFAULT_NOVNC_PORT}}
export VNC_PORT=\${VNC_PORT:-${DEFAULT_VNC_PORT}}
# export VNC_PASSWORD=change-me   # to require password
# export VNC_PASSWORD=            # leave empty (or "none") to disable password
export SHELL=/bin/bash

alias desktop-start='start-kde'
EOF
chmod 0644 "${PROFILE_FILE}"

# ---- start-kde (foreground only) ----
cat > /usr/local/bin/start-kde <<'EOF'
#!/usr/bin/env bash
# start-kde — foreground-only; Ctrl+C to stop
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

# ---- ensure Konsole default profile points to /bin/bash (fixes 'Could not find ''' warning) ----
KONSOLE_DIR="${HOME}/.local/share/konsole"
mkdir -p "$KONSOLE_DIR" "${HOME}/.config"
PROFILE_FILE="${KONSOLE_DIR}/Shell.profile"
if [[ ! -s "$PROFILE_FILE" ]]; then
  cat > "$PROFILE_FILE" <<'PROF'
[General]
Command=/bin/bash
Name=Shell
Parent=FALLBACK/
PROF
fi
KONSOLERC="${HOME}/.config/konsolerc"
if ! grep -q '^DefaultProfile=Shell.profile' "$KONSOLERC" 2>/dev/null; then
  printf "[Desktop Entry]\nDefaultProfile=Shell.profile\n" > "$KONSOLERC"
fi

# --- KWallet suppression (per-session) ---
case "${KEYRING_MODE}" in
  basic|disable)
    mkdir -p "${HOME}/.config/autostart"
    for f in org.kde.kwalletd5.desktop kwalletmanager5_autostart.desktop; do
      cat > "${HOME}/.config/autostart/${f}" <<AUTOSTART
[Desktop Entry]
Type=Application
Name=KWallet (suppressed)
Exec=kwalletd5
Hidden=true
X-GNOME-Autostart-enabled=false
X-KDE-autostart-condition=false
AUTOSTART
    done
    ;;
esac

# pick vnc binary
VNCBIN="$(command -v tigervncserver || command -v vncserver || true)"
[[ -z "$VNCBIN" ]] && { echo "❌ tigervncserver not found" >&2; exit 3; }

# VNC auth: empty = disabled
mkdir -p "${HOME}/.vnc"
VNCAUTH_OPTS=()
if [[ -n "${VNC_PASSWORD}" && "${VNC_PASSWORD,,}" != "none" ]]; then
  [[ ! -s "${HOME}/.vnc/passwd" ]] && echo "$VNC_PASSWORD" | vncpasswd -f > "${HOME}/.vnc/passwd"
  chmod 600 "${HOME}/.vnc/passwd"
else
  VNCAUTH_OPTS+=( -SecurityTypes=None )
  rm -f "${HOME}/.vnc/passwd" 2>/dev/null || true
fi

# xstartup for Plasma (X11)
XSTART="${HOME}/.vnc/xstartup"
if [[ ! -x "$XSTART" ]]; then
  cat > "$XSTART" <<'XEOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
xsetroot -solid grey
exec dbus-launch --exit-with-session startplasma-x11
XEOF
  chmod +x "$XSTART"
fi

# start vnc
if "$VNCBIN" -list 2>/dev/null | grep -qE "^[[:space:]]*${DISPLAY}[[:space:]]"; then
  echo "ℹ️  VNC already running on ${DISPLAY}"
else
  "$VNCBIN" "$DISPLAY" -geometry "$GEOMETRY" -localhost yes "${VNCAUTH_OPTS[@]}"
fi

# ensure no KDE lock is active (best-effort)
if command -v kwriteconfig5 >/dev/null 2>&1; then
  kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock false || true
  kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnResume false || true
fi
pkill -f kscreenlocker || true

# start noVNC in foreground
echo "🌐 noVNC: http://localhost:${NOVNC_PORT}/vnc.html?autoconnect=1&host=localhost&port=${NOVNC_PORT}&path=websockify&resize=scale"
trap 'echo; echo "🛑 stopping…"; "$VNCBIN" -kill "$DISPLAY" || true; exit 0' INT TERM
exec websockify --web=/usr/share/novnc "0.0.0.0:${NOVNC_PORT}" "localhost:${VNC_PORT}"
EOF
chmod 0755 /usr/local/bin/start-kde

# ---- KWallet behavior (disable | basic | keep) ----
: "${KEYRING_MODE:=basic}"
case "${KEYRING_MODE}" in
  disable)
    echo "🔒 Disabling KDE Wallet…"
    apt-get remove -y kwalletmanager kwalletmanager5 kwallet-pam || true
    mkdir -p /etc/xdg/autostart
    for f in /etc/xdg/autostart/*kwallet*.desktop /etc/xdg/autostart/org.kde.kwalletd5.desktop; do
      [[ -f "$f" ]] && sed -i 's/^Hidden=.*/Hidden=true/; t; $aHidden=true' "$f" || true
    done
    ;;
esac

# ---- System-wide NO-LOCK defaults (for all new users) ----
install -d /etc/xdg
cat > /etc/xdg/kscreenlockerrc <<'CONF'
[Daemon]
Autolock=false
LockOnResume=false
Timeout=0
CONF

install -m 0755 /dev/null /usr/local/bin/kde-no-lock
cat > /usr/local/bin/kde-no-lock <<'NLOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock false || true
kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnResume false || true
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Timeout 0 || true
pkill -f kscreenlocker || true
AUTOSTART="${HOME}/.config/autostart/kde-no-lock.desktop"
[[ -f "$AUTOSTART" ]] && sed -i 's/^Hidden=.*/Hidden=true/; t; $aHidden=true' "$AUTOSTART" || true
NLOCK

install -d /etc/xdg/autostart
cat > /etc/xdg/autostart/kde-no-lock.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Disable KDE Lock Screen
Exec=/usr/local/bin/kde-no-lock
OnlyShowIn=KDE;
X-KDE-autostart-phase=1
Hidden=false
NoDisplay=true
DESK

# ---- Auto-pin Dolphin + Konsole ----
install -m 0755 /dev/null /usr/local/bin/kde-pin-dolphin
cat > /usr/local/bin/kde-pin-dolphin <<'PINSH'
#!/usr/bin/env bash
set -Eeuo pipefail
CFG="${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"
mkdir -p "$(dirname "$CFG")"
[[ -f "$CFG" ]] || echo "[General]" > "$CFG"

append_unique() {
  local file="$1" section="$2" key="$3" value="$4"
  awk -v sec="$section" -v key="$key" -v val="$value" '
    BEGIN{FS=OFS="="}
    $0=="["sec"]"{insec=1; found=0}
    /^\[.*\]$/{if(insec && !found){print key"="val}; insec=0}
    insec && $1==key{
      split($2,a,/,/);present=0;for(i in a){if(a[i]==val){present=1}}
      if(!present){$2=($2==""?val:$2","val)};found=1
    }
    {print}
    END{if(insec && !found){print key"="val}}
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

mapfile -t TASK_SECTIONS < <(awk '
  /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]\[Configuration\]\[General\]$/ { print $0 }
' "$CFG")

APPS=("applications:org.kde.dolphin.desktop" "applications:org.kde.konsole.desktop")

for sec in "${TASK_SECTIONS[@]}"; do
  for app in "${APPS[@]}"; do
    append_unique "$CFG" "$sec" "launchers" "$app"
  done
done

KICKOFF="${HOME}/.config/kickoffrc"
mkdir -p "$(dirname "$KICKOFF")"
[[ -f "$KICKOFF" ]] || { echo "[Favorites]" > "$KICKOFF"; echo "FavoriteApps=" >> "$KICKOFF"; }

append_unique "$KICKOFF" "Favorites" "FavoriteApps" "org.kde.dolphin.desktop"
append_unique "$KICKOFF" "Favorites" "FavoriteApps" "org.kde.konsole.desktop"

append_unique "$CFG" "Favorites" "FavoriteApps" "org.kde.dolphin.desktop"
append_unique "$CFG" "Favorites" "FavoriteApps" "org.kde.konsole.desktop"

command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental || \
command -v kbuildsycoca5 >/dev/null && kbuildsycoca5 --noincremental || true

AUTOSTART="${HOME}/.config/autostart/kde-pin-dolphin.desktop"
if [[ -f "$AUTOSTART" ]]; then
  sed -i 's/^Hidden=.*/Hidden=true/; t; $aHidden=true' "$AUTOSTART" || true
fi
PINSH

install -d /etc/xdg/autostart
cat > /etc/xdg/autostart/kde-pin-dolphin.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Pin Dolphin & Konsole to Panel
Exec=/usr/local/bin/kde-pin-dolphin
OnlyShowIn=KDE;
X-KDE-autostart-phase=1
Hidden=false
NoDisplay=true
DESK

# ---- summary ----
cat <<EOF

✅ Installed: $KDE_PACKAGES
✅ VNC stack: $VNC_STACK_PACKAGES
✅ Extras:    $EXTRA_PACKAGES
✅ Profile:   ${PROFILE_FILE}
✅ Binary:    /usr/local/bin/start-kde
✅ Dolphin & Konsole pinned to panel and favorites
✅ KDE lock screen disabled (system-wide defaults + per-user enforcement)

Defaults:
  DISPLAY=${DEFAULT_DISPLAY}
  GEOMETRY=${DEFAULT_GEOMETRY}
  NOVNC_PORT=${DEFAULT_NOVNC_PORT}
  VNC_PORT=${DEFAULT_VNC_PORT}
  VNC_PASSWORD=${DEFAULT_VNC_PASSWORD}

Usage:
  # as NON-root user
  . ${PROFILE_FILE}
  start-kde             # runs in foreground; Ctrl+C to stop

Security:
  - VNC auth is DISABLED by default (SecurityTypes=None).
  - KDE lock screen is disabled; anyone with access to noVNC has desktop access.
  - Strongly recommend reverse proxy + TLS + auth, or keep access limited to localhost/VPN.
EOF
