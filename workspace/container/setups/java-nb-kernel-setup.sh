#!/usr/bin/env bash
# Install the IJava (Java) Jupyter kernel so BOTH:
#   1) a standalone Jupyter, and
#   2) code-server's Jupyter extension
# can see it.
#
# No CLI args. It auto-detects the venv and JDK, or errors out with guidance.
#
# Env you MAY set:
#   IJAVA_VERSION      -> IJava release tag (default: 1.3.0)
#   VENV_DIR           -> Explicit venv path (optional)
#
# Prereqs:
#   - JDK installed (JAVA_HOME set or java/jshell on PATH).
#   - Target venv already has Jupyter (jupyter_client present).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# ---------------- Defaults / Tunables ----------------
IJAVA_VERSION="${IJAVA_VERSION:-1.3.0}"              # default IJava tag
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-java}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-}"        # optional override
VENV_DIR="${VENV_DIR:-}"                              # may be pre-set via env
WORKDIR="${WORKDIR:-/opt/ijava}"
TMPDIR="$(mktemp -d)"

# ---------------- Source helpful profiles (if present) ----------------
# Python env from your base setup
[ -r /etc/profile.d/53-python.sh ]         && source /etc/profile.d/53-python.sh
[ -r /etc/profile.d/54-python-version.sh ] && source /etc/profile.d/54-python-version.sh
# JDK env from your JDK setup (you chose 60)
[ -r /etc/profile.d/60-jdk.sh ] && source /etc/profile.d/60-jdk.sh

# ---------------- Helpers ----------------
infer_python_series_from_cmd() {
  # Print X.Y inferred from python3/python; empty on failure.
  local series=""
  if command -v python3 >/dev/null 2>&1; then
    series="$(python3 - <<'PY' 2>/dev/null || true
import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")
PY
)"
  fi
  if [ -z "$series" ] && command -v python >/dev/null 2>&1; then
    series="$(python - <<'PY' 2>/dev/null || true
import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")
PY
)"
  fi
  printf "%s" "$series"
}

find_venv_with_jupyter_client() {
  # Print venv dir whose python has jupyter_client; empty if none.
  local p
  for p in /opt/venvs/py*/bin/python; do
    [ -x "$p" ] || continue
    if "$p" - <<'PY' >/dev/null 2>&1
import importlib.util as u
raise SystemExit(0 if u.find_spec("jupyter_client") else 1)
PY
    then
      printf "%s\n" "${p%/bin/python}"
      return 0
    fi
  done
  return 1
}

detect_java_version_string() {
  # Prefer $JAVA_HOME/bin/java then `java`; print version like 21.0.4, empty on failure.
  local out ver=""
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    out="$("${JAVA_HOME}/bin/java" -version 2>&1 || true)"
  elif command -v java >/dev/null 2>&1; then
    out="$(java -version 2>&1 || true)"
  fi
  ver="$(printf "%s" "$out" | awk -F\" '/version/ {print $2; exit}')"
  if [ -z "$ver" ]; then
    ver="$(printf "%s" "$out" | sed -n '1s/.*\([0-9][0-9.]*\).*/\1/p')"
  fi
  printf "%s" "$ver"
}

# ---------------- Resolve VENV_DIR ----------------
# Priority:
#   1) $VENV_DIR (env)
#   2) $VENV_SERIES_DIR from 54-python-version.sh (your series symlink)
#   3) /opt/venvs/py${PY_SERIES} when defined
#   4) infer from python on PATH and try /opt/venvs/pyX.Y
#   5) scan for any venv with jupyter_client
if [ -z "${VENV_DIR}" ]; then
  if [ -n "${VENV_SERIES_DIR:-}" ] && [ -x "${VENV_SERIES_DIR}/bin/python" ]; then
    VENV_DIR="${VENV_SERIES_DIR}"
  elif [ -n "${PY_SERIES:-}" ] && [ -d "/opt/venvs/py${PY_SERIES}/bin" ]; then
    VENV_DIR="/opt/venvs/py${PY_SERIES}"
  else
    series="$(infer_python_series_from_cmd || true)"
    if [ -n "$series" ] && [ -d "/opt/venvs/py${series}/bin" ]; then
      VENV_DIR="/opt/venvs/py${series}"
    fi
  fi
fi

if [ -z "${VENV_DIR}" ]; then
  VENV_DIR="$(find_venv_with_jupyter_client || true)"
fi

if [ -z "${VENV_DIR}" ] || [ ! -x "${VENV_DIR}/bin/python" ]; then
  cat >&2 <<'EOF'
❌ Could not determine a Python venv with Jupyter.
Make sure your Python/Jupyter setup ran first (e.g., notebook-setup.sh).
You can also set VENV_DIR explicitly, e.g.:
  export VENV_DIR=/opt/venvs/py3.12
  sudo -E ./java-nb-kernel-setup.sh
EOF
  exit 2
fi

# Ensure chosen python has jupyter_client
if ! "${VENV_DIR}/bin/python" - <<'PY' >/dev/null 2>&1
import importlib.util as u
raise SystemExit(0 if u.find_spec("jupyter_client") else 1)
PY
then
  echo "❌ ${VENV_DIR}/bin/python does not have 'jupyter_client'. Install Jupyter first." >&2
  exit 2
fi

# ---------------- Resolve JAVA_HOME (+ jshell) ----------------
if [ -z "${JAVA_HOME:-}" ]; then
  # try profile again in case user's env didn't include it
  [ -r /etc/profile.d/60-jdk.sh ] && source /etc/profile.d/60-jdk.sh
fi
if [ -z "${JAVA_HOME:-}" ]; then
  # last resort: derive from update-alternatives
  if command -v java >/dev/null 2>&1; then
    jpath="$(readlink -f "$(command -v java)")" || true
    # Expect .../jre/bin/java or .../bin/java; go up two/three levels
    base="$(dirname "$(dirname "$jpath")")"
    [ -x "$base/bin/jshell" ] && export JAVA_HOME="$base"
  fi
fi
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME}/bin/jshell" ]; then
  cat >&2 <<'EOF'
❌ JAVA_HOME is not set or jshell is missing.
Run your JDK installer first, e.g.:
  sudo ./jdk-setup.sh 25
Then re-run this script.
EOF
  exit 1
fi

# ---------------- JDK version string for display ----------------
JDK_VERSION_FULL="$(detect_java_version_string || true)"
if [ -z "$JDK_VERSION_FULL" ]; then
  cat >&2 <<'EOF'
❌ Could not determine JDK version for kernel display name.
Ensure 'java -version' works or set JAVA_HOME.
EOF
  exit 2
fi
JDK_MAJOR="${JDK_VERSION_FULL%%.*}"
[ -z "$JDK_MAJOR" ] && JDK_MAJOR="$JDK_VERSION_FULL"
[ -z "$KERNEL_DISPLAY_NAME" ] && KERNEL_DISPLAY_NAME="Java (JDK ${JDK_MAJOR})"

# ---------------- Basics ----------------
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl unzip ca-certificates python3
rm -rf /var/lib/apt/lists/*

# ---------------- Fetch IJava release ----------------
mkdir -p "${WORKDIR}"
ZIP_URL="https://github.com/SpencerPark/IJava/releases/download/v${IJAVA_VERSION}/ijava-${IJAVA_VERSION}.zip"
echo "⬇️  Downloading IJava ${IJAVA_VERSION} …"
curl -fsSL "$ZIP_URL" -o "${TMPDIR}/ijava.zip"
unzip -q -o "${TMPDIR}/ijava.zip" -d "${TMPDIR}"

INSTALL_PY="$(find "${TMPDIR}" -maxdepth 2 -type f -name 'install.py' -print -quit)"
if [ -z "$INSTALL_PY" ]; then
  echo "❌ IJava archive did not contain install.py. Aborting." >&2
  exit 1
fi

# Stage into a stable location for reuse
rsync -a --delete "$(dirname "$INSTALL_PY")"/ "${WORKDIR}/"
chmod -R a+rX "${WORKDIR}"

# ---------------- Register system-wide ----------------
echo "🧩 Registering IJava kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide) …"
pushd "${WORKDIR}" >/dev/null
export JAVA_HOME PATH="${JAVA_HOME}/bin:${PATH}"
"${VENV_DIR}/bin/python" install.py --prefix "${JUPYTER_KERNEL_PREFIX}"

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
if [ ! -d "${KDIR}" ]; then
  echo "❌ Expected kernelspec directory not found at ${KDIR}" >&2
  exit 1
fi
chmod -R a+rX "${KDIR}" || true

# Update display_name and bake JAVA_HOME (ensure the right java is used)
if [ -f "${KDIR}/kernel.json" ]; then
  python3 - "$KDIR" "$KERNEL_DISPLAY_NAME" "$JAVA_HOME" <<'PY'
import json, os, sys
kdir, disp, jh = sys.argv[1], sys.argv[2], sys.argv[3]
p = os.path.join(kdir, "kernel.json")
with open(p) as f:
    data = json.load(f)
data["display_name"] = disp
env = data.get("env", {})
env.setdefault("JAVA_HOME", jh)
argv = data.get("argv", [])
if argv and argv[0] == "java":
    argv[0] = os.path.join(jh, "bin", "java")
data["env"] = env
with open(p, "w") as f:
    json.dump(data, f, indent=2)
PY
fi

# ---------------- Also register into the venv (sys-prefix) ----------------
echo "🧩 Also registering IJava into venv: ${VENV_DIR} (sys-prefix) …"
export JAVA_HOME PATH="${JAVA_HOME}/bin:${PATH}"
"${VENV_DIR}/bin/python" install.py --sys-prefix || true

popd >/dev/null

# ---------------- Verification ----------------
echo
echo "🔎 Kernels (system):"
"${VENV_DIR}/bin/python" -m jupyter kernelspec list || true
echo
echo "🔎 Kernels (venv):"
"${VENV_DIR}/bin/python" -m jupyter kernelspec list || true

echo
echo "✅ IJava installed at: ${KDIR}"
echo "   Display name: ${KERNEL_DISPLAY_NAME}"
echo "   JAVA_HOME:    ${JAVA_HOME}"
echo "   Python used:  ${VENV_DIR}/bin/python"
echo "   VENV_DIR:     ${VENV_DIR}"
