#!/usr/bin/env bash
# xfce-setup.sh — root-only installer for XFCE + VNC + noVNC (+ Firefox via Mozillateam PPA)
# Installs deps, writes /etc/profile.d/99-custom.sh, and creates /usr/local/bin/start-xfce + stop-xfce
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# ---- root check ----
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- configurable args (safe defaults) ----
DESKTOP_PACKAGES="${DESKTOP_PACKAGES:-xfce4 xfce4-terminal}"
VNC_STACK_PACKAGES="${VNC_STACK_PACKAGES:-tigervnc-standalone-server novnc websockify dbus-x11}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-x11-xserver-utils curl locales software-properties-common}"
PROFILE_FILE="${PROFILE_FILE:-/etc/profile.d/99-custom.sh}"

DEFAULT_DISPLAY="${DEFAULT_DISPLAY:-:1}"
DEFAULT_GEOMETRY="${DEFAULT_GEOMETRY:-1280x800}"
DEFAULT_NOVNC_PORT="${DEFAULT_NOVNC_PORT:-10000}"
DEFAULT_VNC_PORT="${DEFAULT_VNC_PORT:-5901}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-}"

# ---- install packages ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y $DESKTOP_PACKAGES $VNC_STACK_PACKAGES $EXTRA_PACKAGES
apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- Firefox via Mozillateam PPA (avoids snap) ----
# Remove the snap stub if present, add PPA, pin it, install the DEB.
apt-get remove -y firefox || true
apt-get update
add-apt-repository -y ppa:mozillateam/ppa
tee /etc/apt/preferences.d/mozillateam-firefox >/dev/null <<'EOF'
Package: firefox*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF
apt-get update
apt-get install -y firefox
# ----

# ---- VS Code via Microsoft apt repo (clean + idempotent) ----
echo "🔧 Installing Visual Studio Code (no snap)…"

# 1) Prereqs
apt-get update
apt-get install -y curl ca-certificates gnupg

# 2) Install Microsoft’s signing key in a canonical location
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
chmod 0644 /etc/apt/keyrings/packages.microsoft.gpg

# 3) Remove ALL existing Code repo entries (both .list and .sources) to avoid Signed-By conflicts
for f in /etc/apt/sources.list \
         /etc/apt/sources.list.d/*.list \
         /etc/apt/sources.list.d/*.sources; do
  [[ -f "$f" ]] && sed -i '/packages\.microsoft\.com\/repos\/code/d' "$f" || true
done
rm -f /etc/apt/sources.list.d/vscode.list /etc/apt/sources.list.d/vscode.sources || true

# 4) Add a single, canonical repo entry referencing the same keyring
arch="$(dpkg --print-architecture)"   # amd64 or arm64
install -d -m 0755 /etc/apt/sources.list.d
cat > /etc/apt/sources.list.d/vscode.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main
EOF
chmod 0644 /etc/apt/sources.list.d/vscode.list

# 5) Install VS Code (deb package)
apt-get clean
rm -rf /var/lib/apt/lists/*
apt-get update
apt-get install -y code
echo "✅ VS Code installed"

# 6) Make no-sandbox the default (wrapper takes precedence over /usr/bin via PATH)
cat >/usr/local/bin/code <<'EOF'
#!/usr/bin/env bash
# Wrapper to run VS Code without sandbox (friendlier in containers/VNC)
exec /usr/bin/code \
  --no-sandbox \
  --disable-gpu \
  --no-first-run \
  --no-default-browser-check \
  --user-data-dir="${HOME}/.vscode-data" \
  "$@"
EOF
chmod 0755 /usr/local/bin/code

# 7) Ensure the desktop launcher uses the wrapper (if the .desktop exists)
if [[ -f /usr/share/applications/code.desktop ]]; then
  sed -i 's#^Exec=.*#Exec=/usr/local/bin/code %F#' /usr/share/applications/code.desktop || true
fi

echo "✅ VS Code configured to use --no-sandbox by default"
# ----

# sanity check for noVNC assets
if [[ ! -d /usr/share/novnc ]]; then
  echo "❌ /usr/share/novnc not found (noVNC assets missing)" >&2
  exit 2
fi

# ---- Make / the autoconnect entrypoint for noVNC (works for any port/host) ----
cat >/usr/share/novnc/index.html <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>noVNC</title>
<script>
  // Redirect to the viewer and autoconnect using the current host/port
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

# ---- profile snippet (auto-sourced on shell startup) ----
cat > "${PROFILE_FILE}" <<EOF
# XFCE over VNC/noVNC defaults
export DISPLAY=${DEFAULT_DISPLAY}
export GEOMETRY=\${GEOMETRY:-${DEFAULT_GEOMETRY}}
export NOVNC_PORT=\${NOVNC_PORT:-${DEFAULT_NOVNC_PORT}}
export VNC_PORT=\${VNC_PORT:-${DEFAULT_VNC_PORT}}
# Change this for NEW users before first start:
# export VNC_PASSWORD=change-me   # set a password to require auth
# export VNC_PASSWORD=            # leave empty (or set to "none") to DISABLE auth

# convenience aliases
alias desktop-start='start-xfce --background'
alias desktop-foreground='start-xfce --foreground'
alias desktop-stop='stop-xfce'
EOF
chmod 0644 "${PROFILE_FILE}"

# ---- user-facing launcher: start-xfce (NON-ROOT) ----
cat > /usr/local/bin/start-xfce <<'EOF'
#!/usr/bin/env bash
# start-xfce — start XFCE via TigerVNC + noVNC (run as NON-ROOT user)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

MODE="${1:---foreground}"  # --foreground (default) or --background

: "${DISPLAY:=:1}"
: "${GEOMETRY:=1280x800}"
: "${NOVNC_PORT:=10000}"
: "${VNC_PASSWORD:=}"
# If VNC_PORT not provided, infer 5900 + display number
if [[ -z "${VNC_PORT:-}" ]]; then
  if [[ "$DISPLAY" =~ :([0-9]+) ]]; then
    VNC_PORT="$((5900 + ${BASH_REMATCH[1]}))"
  else
    VNC_PORT=5901
  fi
fi

: "${HOME:?HOME must be set and writable}"

# Runtime dir helps some apps
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

# pick VNC binary
VNCBIN="$(command -v tigervncserver || command -v vncserver || true)"
if [[ -z "$VNCBIN" ]]; then
  echo "❌ tigervncserver not found. Ask admin to run xfce-setup.sh" >&2
  exit 3
fi

# ensure VNC auth + xstartup
mkdir -p "${HOME}/.vnc"

VNCAUTH_OPTS=()
if [[ -n "${VNC_PASSWORD}" && "${VNC_PASSWORD,,}" != "none" ]]; then
  # password provided -> create password file (if missing) and use default security types
  if [[ ! -s "${HOME}/.vnc/passwd" ]]; then
    echo "$VNC_PASSWORD" | vncpasswd -f > "${HOME}/.vnc/passwd"
    chmod 600 "${HOME}/.vnc/passwd"
  fi
else
  # no password -> explicitly disable authentication on TigerVNC
  VNCAUTH_OPTS+=( -SecurityTypes=None )
  # (optional) ensure no stale passwd influences behavior
  rm -f "${HOME}/.vnc/passwd" 2>/dev/null || true
fi

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

# start/verify VNC (bind to loopback only; no need to expose 5901)
if "$VNCBIN" -list 2>/dev/null | grep -qE "^[[:space:]]*${DISPLAY}[[:space:]]"; then
  echo "ℹ️  VNC already running on ${DISPLAY}"
else
  "$VNCBIN" "$DISPLAY" -geometry "$GEOMETRY" -localhost yes "${VNCAUTH_OPTS[@]}"
fi

# start noVNC (websockify) either foreground or background
WEBSOCK_PIDFILE="${HOME}/.vnc/websockify.pid"
start_novnc_bg() {
  if [[ -f "$WEBSOCK_PIDFILE" ]] && kill -0 "$(cat "$WEBSOCK_PIDFILE")" 2>/dev/null; then
    echo "ℹ️  noVNC already running (PID $(cat "$WEBSOCK_PIDFILE")) at http://localhost:${NOVNC_PORT}"
  else
    websockify --web=/usr/share/novnc "0.0.0.0:${NOVNC_PORT}" "localhost:${VNC_PORT}" &
    echo $! > "$WEBSOCK_PIDFILE"
    disown || true
    echo "✅ noVNC: http://localhost:${NOVNC_PORT}/vnc.html?autoconnect=1&host=localhost&port=${NOVNC_PORT}&path=websockify&resize=scale"
  fi
}

start_novnc_fg() {
  echo "🌐 noVNC: http://localhost:${NOVNC_PORT}/vnc.html?autoconnect=1&host=localhost&port=${NOVNC_PORT}&path=websockify&resize=scale"
  trap 'echo; echo "🛑 stopping…"; [[ -f "$WEBSOCK_PIDFILE" ]] && kill "$(cat "$WEBSOCK_PIDFILE")" 2>/dev/null || true; "$VNCBIN" -kill "$DISPLAY" || true; exit 0' INT TERM
  exec websockify --web=/usr/share/novnc "0.0.0.0:${NOVNC_PORT}" "localhost:${VNC_PORT}"
}

case "$MODE" in
  --background) start_novnc_bg ;;
  --foreground) start_novnc_fg ;;
  *)
    echo "Usage: start-xfce [--background|--foreground]" >&2
    exit 64
    ;;
esac

echo "🔌 Raw VNC (inside container only): localhost:${VNC_PORT}   Display: ${DISPLAY}   Geometry: ${GEOMETRY}"
EOF
chmod 0755 /usr/local/bin/start-xfce

# ---- user-facing stopper: stop-xfce (NON-ROOT) ----
cat > /usr/local/bin/stop-xfce <<'EOF'
#!/usr/bin/env bash
# stop-xfce — stop noVNC + VNC for the current user/session
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

: "${DISPLAY:=:1}"
: "${HOME:?HOME must be set and writable}"

VNCBIN="$(command -v tigervncserver || command -v vncserver || true)"
if [[ -z "$VNCBIN" ]]; then
  echo "❌ tigervncserver not found" >&2
  exit 3
fi

WEBSOCK_PIDFILE="${HOME}/.vnc/websockify.pid"
if [[ -f "$WEBSOCK_PIDFILE" ]]; then
  if kill -0 "$(cat "$WEBSOCK_PIDFILE")" 2>/dev/null; then
    kill "$(cat "$WEBSOCK_PIDFILE")" || true
  fi
  rm -f "$WEBSOCK_PIDFILE"
  echo "🛑 noVNC stopped"
else
  echo "ℹ️  noVNC not running (no PID file)"
fi

"$VNCBIN" -kill "$DISPLAY" || true
echo "🛑 VNC stopped for ${DISPLAY}"
EOF
chmod 0755 /usr/local/bin/stop-xfce

# --- Disable keyrings ---
apt-get remove -y gnome-keyring seahorse

# ---- summary ----
echo
echo "✅ Installed: $DESKTOP_PACKAGES"
echo "✅ VNC stack: $VNC_STACK_PACKAGES"
echo "✅ Extras:    $EXTRA_PACKAGES"
echo "✅ Firefox:   installed via Mozillateam PPA (DEB, no snap)"
echo "✅ VSCODE:    VS Code -- run with 'code'"
echo "✅ Profile:   ${PROFILE_FILE}"
echo "✅ Binaries:  /usr/local/bin/start-xfce, /usr/local/bin/stop-xfce"
echo
echo "Defaults:"
echo "  DISPLAY=${DEFAULT_DISPLAY}"
echo "  GEOMETRY=${DEFAULT_GEOMETRY}"
echo "  NOVNC_PORT=${DEFAULT_NOVNC_PORT}"
echo "  VNC_PORT=${DEFAULT_VNC_PORT}"
echo "  VNC_PASSWORD=${DEFAULT_VNC_PASSWORD}"
echo
echo "Next steps (inside the container):"
echo "  # as NON-root user"
echo "  . ${PROFILE_FILE}            # usually auto-sourced"
echo "  start-xfce --background      # open: http://localhost:${DEFAULT_NOVNC_PORT}"
echo "  # or keep attached:"
echo "  start-xfce --foreground"
echo "  # to stop later:"
echo "  stop-xfce"
