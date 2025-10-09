#!/usr/bin/env bash
# bash-nb-kernel-setup.sh
#
# Install the Bash Jupyter kernel so BOTH:
#   1) a standalone Jupyter, and
#   2) code-server's Jupyter extension
# can see it.
#
# This script intentionally has **no CLI flags**. It derives everything from the
# environment provisioned by python-setup.sh and notebook-setup.sh:
#   - /etc/profile.d/53-python.sh     (sets PY_STABLE, PIP knobs, PATH)
#   - /etc/profile.d/54-python-version.sh (sets PY_STABLE_VERSION, PY_SERIES, VENV_SERIES_DIR)
#
# Env overrides if needed:
#   JUPYTER_KERNEL_PREFIX  (default: /usr/local)
#   KERNEL_NAME            (default: bash)
#   KERNEL_DISPLAY_NAME    (default: Bash)
#   VENV_DIR               (explicit venv dir; otherwise auto-detected)
#
# Prereqs:
#   - python-setup.sh and notebook-setup.sh already ran successfully.
#   - The chosen Python can install packages with pip.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# ---------------- Load environment from profile.d ----------------
# These set: PY_STABLE, PY_STABLE_VERSION, PY_SERIES, VENV_SERIES_DIR, PATH tweaks, etc.
source /etc/profile.d/53-python.sh         2>/dev/null || true
source /etc/profile.d/54-python-version.sh 2>/dev/null || true

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-bash}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Bash}"
PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}"

# ---------------- Helpers ----------------
has_module() {
  local pybin="$1" mod="$2"
  "$pybin" - <<PY >/dev/null 2>&1
import importlib.util as u, sys
sys.exit(0 if u.find_spec("${mod}") else 1)
PY
}

find_venv_with_jupyter_client() {
  # Print venv dir whose python has jupyter_client; empty if none.
  local p
  for p in /opt/venvs/py*/bin/python; do
    [ -x "$p" ] || continue
    if has_module "$p" jupyter_client; then
      printf "%s\n" "${p%/bin/python}"
      return 0
    fi
  done
  return 1
}

# ---------------- Resolve VENV_DIR and Python binary ----------------
# Priority:
#   1) $VENV_DIR (if set)
#   2) $VENV_SERIES_DIR from 54-python-version.sh (e.g. /opt/venvs/py3.12)
#   3) /opt/python (stable symlink made by python-setup.sh)
#   4) any /opt/venvs/py*/ that already has jupyter_client
VENV_DIR="${VENV_DIR:-}"
if [ -z "${VENV_DIR}" ] && [ -n "${VENV_SERIES_DIR:-}" ] && [ -x "${VENV_SERIES_DIR}/bin/python" ]; then
  VENV_DIR="${VENV_SERIES_DIR}"
fi
if [ -z "${VENV_DIR}" ] && [ -x /opt/python/bin/python ]; then
  VENV_DIR="/opt/python"
fi
if [ -z "${VENV_DIR}" ]; then
  VENV_DIR="$(find_venv_with_jupyter_client || true)"
fi

# Pick Python: prefer the venv’s python; else fall back to python3/python on PATH.
if [ -n "${VENV_DIR:-}" ] && [ -x "${VENV_DIR}/bin/python" ]; then
  PYBIN="${VENV_DIR}/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PYBIN="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  PYBIN="$(command -v python)"
else
  cat >&2 <<EOF
❌ Could not find any Python interpreter.
Expected from profile setup:
  - /opt/python/bin/python (stable venv)
  - or /opt/venvs/pyX.Y/bin/python (series venv)
EOF
  exit 1
fi

# ---------------- Ensure deps in the chosen Python ----------------
env PIP_CACHE_DIR="$PIP_CACHE_DIR" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  "$PYBIN" -m pip install -U pip setuptools wheel >/dev/null

env PIP_CACHE_DIR="$PIP_CACHE_DIR" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  "$PYBIN" -m pip install -U jupyter_client bash_kernel >/dev/null

# ---------------- Register kernelspecs ----------------
echo "🧩 Registering Bash kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)…"
"$PYBIN" -m bash_kernel.install --prefix "${JUPYTER_KERNEL_PREFIX}"

# If we have a venv, also install the kernelspec in that venv (sys-prefix)
if [ -n "${VENV_DIR:-}" ] && [ -x "${VENV_DIR}/bin/python" ]; then
  echo "🧩 Also registering Bash kernel into venv: ${VENV_DIR} (sys-prefix)…"
  "${VENV_DIR}/bin/python" -m bash_kernel.install --sys-prefix || true
fi

# Expected system-wide kernelspec dir
KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
[ -d "${KDIR}" ] || echo "ℹ️ Could not confirm ${KDIR}; listing kernels below for verification."

# ---------------- Verification ----------------
echo
echo "🔎 Kernels (system):"
"$PYBIN" -m jupyter kernelspec list || true
if [ -n "${VENV_DIR:-}" ] && [ -x "${VENV_DIR}/bin/python" ]; then
  echo
  echo "🔎 Kernels (venv):"
  "${VENV_DIR}/bin/python" -m jupyter kernelspec list || true
fi

# ---------------- Friendly summary ----------------
echo
echo "✅ Bash kernel installed."
[ -n "${KDIR:-}" ] && echo "   System kernelspec dir: ${KDIR}"
echo "   Display name:          ${KERNEL_DISPLAY_NAME}"
echo "   Python used:           ${PYBIN}"
[ -n "${VENV_DIR:-}" ] && echo "   VENV_DIR:              ${VENV_DIR}"

echo
echo "Use it now in this shell:"
echo "  jupyter kernelspec list | sed -n '1,10p'"
