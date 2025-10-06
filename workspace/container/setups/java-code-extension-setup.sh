#!/usr/bin/env bash
# Minimal-but-robust IJava (Java) Jupyter kernel installer.
# - Finds a Jupyter-capable venv under /opt/venvs
# - Detects JAVA_HOME or java/jshell on PATH
# - Installs IJava system-wide and (if possible) into the venv's sys-prefix
set -Eeuo pipefail

IJAVA_VERSION="${IJAVA_VERSION:-1.3.0}"
PREFIX="${PREFIX:-/usr/local}"          # where system-wide kernelspec goes
WORKDIR="${WORKDIR:-/opt/ijava}"
TMPDIR="$(mktemp -d)"

# ---- find a /opt/venvs/* venv that already has jupyter_client ----
find_venv_with_jupyter_client() {
  local p
  for p in /opt/venvs/py*/bin/python; do
    [[ -x "$p" ]] || continue
    "$p" - <<'PY' >/dev/null 2>&1 || continue
import importlib.util as u; raise SystemExit(0 if u.find_spec("jupyter_client") else 1)
PY
    printf "%s\n" "${p%/bin/python}"; return 0
  done
  return 1
}

VENV_DIR="${VENV_DIR:-$(find_venv_with_jupyter_client || true)}"
[[ -n "$VENV_DIR" && -x "$VENV_DIR/bin/python" ]] || { echo "❌ No Jupyter-capable venv found under /opt/venvs"; exit 1; }
VENV_PY="$VENV_DIR/bin/python"

# ---- detect JAVA_HOME (prefer env, else java on PATH) ----
detect_java_home() {
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/jshell" ]]; then
    printf "%s" "$JAVA_HOME"; return 0
  fi
  if command -v java >/dev/null 2>&1; then
    local bindir; bindir="$(dirname "$(readlink -f "$(command -v java)")")"
    local home="${bindir%/bin}"
    [[ -x "$home/bin/jshell" ]] && { printf "%s" "$home"; return 0; }
  fi
  return 1
}
JAVA_HOME="$(detect_java_home || true)" || true
[[ -n "$JAVA_HOME" ]] || { echo "❌ JAVA_HOME not found and jshell unavailable. Install a JDK and retry."; exit 1; }

# ---- display name: Java (JDK <major>) ----
JDK_VERSION="$( "$JAVA_HOME/bin/java" -version 2>&1 | awk -F\" '/version/{print $2;exit}' )"
JDK_MAJOR="${JDK_VERSION%%.*}"; [[ -n "$JDK_MAJOR" ]] || JDK_MAJOR="$JDK_VERSION"
KERNEL_NAME="${KERNEL_NAME:-java}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Java (JDK ${JDK_MAJOR})}"

# ---- deps needed just for unzip/curl/python3 (if not already) ----
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends curl unzip ca-certificates python3
rm -rf /var/lib/apt/lists/*

# ---- fetch IJava ----
mkdir -p "$WORKDIR"
ZIP_URL="https://github.com/SpencerPark/IJava/releases/download/v${IJAVA_VERSION}/ijava-${IJAVA_VERSION}.zip"
echo "⬇️  Downloading IJava ${IJAVA_VERSION} …"
curl -fsSL "$ZIP_URL" -o "${TMPDIR}/ijava.zip"
unzip -q -o "${TMPDIR}/ijava.zip" -d "${TMPDIR}"
INSTALL_PY="$(find "${TMPDIR}" -maxdepth 2 -type f -name 'install.py' -print -quit)"
[[ -n "$INSTALL_PY" ]] || { echo "❌ IJava archive missing install.py"; exit 1; }

# stage for reuse
rsync -a --delete "$(dirname "$INSTALL_PY")"/ "${WORKDIR}/"
chmod -R a+rX "${WORKDIR}"

# ---- install: system-wide + venv sys-prefix (best of both) ----
export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"

echo "🧩 Registering IJava system-wide → $PREFIX"
python3 "${WORKDIR}/install.py" --prefix "$PREFIX"

if [[ -x "$VENV_PY" ]]; then
  echo "🧩 Also registering IJava into venv (sys-prefix) → $VENV_DIR"
  "$VENV_PY" "${WORKDIR}/install.py" --sys-prefix || true
fi

KDIR="${PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
[[ -d "$KDIR" ]] || { echo "❌ Expected kernelspec dir not found at $KDIR"; exit 1; }

# ---- tweak kernel.json: display_name + bake JAVA_HOME/java path ----
python3 - "$KDIR" "$KERNEL_DISPLAY_NAME" "$JAVA_HOME" <<'PY'
import json, os, sys
kdir, disp, jh = sys.argv[1], sys.argv[2], sys.argv[3]
p = os.path.join(kdir, "kernel.json")
with open(p) as f: data = json.load(f)
data["display_name"] = disp
env = data.get("env", {})
env.setdefault("JAVA_HOME", jh)
argv = data.get("argv", [])
if argv and argv[0] == "java":
    argv[0] = os.path.join(jh, "bin", "java")
data["env"] = env
with open(p, "w") as f: json.dump(data, f, indent=2)
PY

# ---- verify ----
echo
echo "🔎 Kernels (system):"
python3 -m jupyter kernelspec list || true
echo
echo "✅ IJava ready."
echo "   Kernel dir:     $KDIR"
echo "   Display name:   $KERNEL_DISPLAY_NAME"
echo "   JAVA_HOME:      $JAVA_HOME"
echo "   Venv (found):   $VENV_DIR"
