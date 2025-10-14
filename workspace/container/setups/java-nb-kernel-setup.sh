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
#
# Prereqs (assumed present in this environment):
#   - JDK installed (JAVA_HOME set; java/jshell on PATH).
#   - Target venv already has Jupyter (jupyter_client & jupyter_core present).
#   - rsync, curl, unzip available.
#   - Running under a venv; WS_VENV_DIR and WS_JDK_VERSION set.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# ---------------- Source helpful profiles (if present) ----------------
[ -r /etc/profile.d/53-ws-python.sh ] && source /etc/profile.d/53-ws-python.sh
[ -r /etc/profile.d/60-ws-jdk.sh    ] && source /etc/profile.d/60-ws-jdk.sh

# ---------------- Defaults / Tunables ----------------
IJAVA_VERSION="${IJAVA_VERSION:-1.3.0}"                                # default IJava tag
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-java}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Java ${WS_JDK_VERSION}}"
WORKDIR="${WORKDIR:-/opt/ijava}"
TMPDIR="$(mktemp -d)"

# Ensure python exists
if ! command -v python >/dev/null 2>&1; then
  echo "❌ python does not exist. Install python first." >&2
  exit 2
fi

# Ensure JDK exists
if ! command -v javac >/dev/null 2>&1; then
  echo "❌ javac does not exist (thus JDK). Install JDK first." >&2
  exit 2
fi

# Ensure chosen python has jupyter_client and jupyter_core
if ! python - <<'PY' >/dev/null 2>&1
import importlib.util as u
ok = all(u.find_spec(m) for m in ("jupyter_client","jupyter_core"))
raise SystemExit(0 if ok else 1)
PY
then
  echo "❌ python lacks required Jupyter packages ('jupyter_client' and/or 'jupyter_core')." >&2
  exit 2
fi

# ---------------- Basics ----------------
export DEBIAN_FRONTEND=noninteractive

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
python install.py --prefix "${JUPYTER_KERNEL_PREFIX}"

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
if [ ! -d "${KDIR}" ]; then
  echo "❌ Expected kernelspec directory not found at ${KDIR}" >&2
  exit 1
fi
chmod -R a+rX "${KDIR}" || true

# Update display_name and bake JAVA_HOME (ensure the right java is used)
if [ -f "${KDIR}/kernel.json" ]; then
  python - "$KDIR" "$KERNEL_DISPLAY_NAME" "$JAVA_HOME" <<'PY'
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
echo "🧩 Also registering IJava into venv"
python install.py --sys-prefix || true

popd >/dev/null

# ---------------- Verification ----------------
echo
echo "🔎 Kernels (current python):"
python -m jupyter kernelspec list || true

echo
echo "✅ IJava installed at: ${KDIR}"
echo "   Display name: ${KERNEL_DISPLAY_NAME}"
echo "   JAVA_HOME:    ${JAVA_HOME}"
echo "   Python used:  ${WS_VENV_DIR}/bin/python"
echo "   VENV_DIR:     ${WS_VENV_DIR}"
