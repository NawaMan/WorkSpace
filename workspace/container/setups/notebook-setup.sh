#!/usr/bin/env bash
# notebook-setup.sh
# Uses consolidated Python setup (/opt/workspace/setups/python-setup.sh),
# then installs Jupyter and registers kernels + a "notebook" launcher.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---- root check (match other scripts) ----
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- configurable args (safe defaults) ----
PY_VERSION=${1:-3.12}                    # accepts X.Y or X.Y.Z
PYENV_ROOT="${PYENV_ROOT:-/opt/pyenv}"   # kept only for parity/logging
VENV_ROOT="${VENV_ROOT:-/opt/venvs}"     # kept only for parity/logging
PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}"
STABLE_PY_LINK="${STABLE_PY_LINK:-/opt/python}"
PROFILE_FILE="${PROFILE_FILE:-/etc/profile.d/99-custom.sh}"
VENV_DIR="${VENV_DIR:-/opt/venvs/py${PY_VERSION}}"

# Use python-setup.sh exactly like setup-code-server-jupyter.sh
FEATURE_DIR=${FEATURE_DIR:-/opt/workspace/setups}
"${FEATURE_DIR}/python-setup.sh" "${PY_VERSION}"

# Ensure venv exists (built from the stable interpreter)
if [ ! -x "${VENV_DIR}/bin/python" ]; then
  mkdir -p "${VENV_DIR%/*}"
  "${STABLE_PY_LINK}/bin/python" -m venv "${VENV_DIR}"
fi
VENV_PY="${VENV_DIR}/bin/python"

# ---- Jupyter kernel registration tunables (match code-server) ----
JUPYTER_KERNEL_NAME="${JUPYTER_KERNEL_NAME:-python3}"
JUPYTER_KERNEL_DISPLAY="${JUPYTER_KERNEL_DISPLAY:-Python ${PY_VERSION} (venv)}"
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"  # installs under /usr/local/share/jupyter/kernels/<name>

# ---- helper: install + verify Jupyter in venv ----
ensure_jupyterlab_in_venv() {
  "${VENV_PY}" -m pip install -U pip setuptools wheel
  "${VENV_PY}" -m pip install -U \
    "ipykernel>=6" \
    "jupyter_core>=5" \
    "jupyter_server>=2" \
    "jupyterlab_server>=2" \
    "jupyterlab>=4,<6"

  # Verify importability
  if ! "${VENV_PY}" - <<'PY'
import importlib.util as u
raise SystemExit(0 if u.find_spec("jupyterlab") else 1)
PY
  then
    return 1
  fi
  return 0
}

echo "🧩 Installing Jupyter into venv ${VENV_DIR} ..."
if ! ensure_jupyterlab_in_venv; then
  CURRENT_MM="$("${VENV_PY}" -c 'import sys;print(".".join(map(str,sys.version_info[:2])))' || echo "")"
  echo "⚠️  JupyterLab failed to import on Python ${CURRENT_MM} in ${VENV_DIR}."
  if [[ "$CURRENT_MM" == "3.13" ]]; then
    echo "↩️  Falling back to Python 3.12 for maximum compatibility ..."
    "${FEATURE_DIR}/python-setup.sh" "3.12"
    # Recreate venv from the new stable interpreter
    rm -rf "${VENV_DIR}"
    "${STABLE_PY_LINK}/bin/python" -m venv "${VENV_DIR}"
    VENV_PY="${VENV_DIR}/bin/python"
    echo "🧩 Re-attempting JupyterLab install on $("${VENV_PY}" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))') in ${VENV_DIR} ..."
    ensure_jupyterlab_in_venv || { echo "❌ JupyterLab still not importable after fallback." >&2; exit 1; }
  else
    echo "❌ JupyterLab install/verify failed (non-3.13). Aborting." >&2
    exit 1
  fi
fi

# ---- Register venv Python as a Jupyter kernel (system-wide, same name/display as code-server) ----
KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${JUPYTER_KERNEL_NAME}"
rm -rf "${KDIR}" || true
"${VENV_PY}" -m ipykernel install \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --name="${JUPYTER_KERNEL_NAME}" \
  --display-name="${JUPYTER_KERNEL_DISPLAY}"
chmod -R a+rX "${KDIR}" || true

# ---- Add a system-wide Bash kernel ----
echo "🧩 Installing Bash kernel and registering kernelspec ..."
"${VENV_PY}" -m pip install -q --upgrade bash_kernel
BASH_KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/bash"
rm -rf "${BASH_KDIR}" || true
"${VENV_PY}" -m bash_kernel.install --prefix="${JUPYTER_KERNEL_PREFIX}"
chmod -R a+rX "${BASH_KDIR}" || true

# ---- Create startup script (ensures terminals inherit the venv) ----
cat > /usr/local/bin/notebook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-10000}

# Ensure PATH and /opt/python are active in non-login shells
source /etc/profile.d/99-custom.sh || true

VENV_DIR="${VENV_DIR:-__VENV_DIR_PLACEHOLDER__}"

# Prefer the venv for everything the server (and its terminals) launch
export PATH="${VENV_DIR}/bin:${PATH}"
export VIRTUAL_ENV="${VENV_DIR}"

# Make sure non-Python kernels in the venv are visible if present
export JUPYTER_PATH="${VENV_DIR}/share/jupyter:/usr/local/share/jupyter:/usr/share/jupyter${JUPYTER_PATH:+:$JUPYTER_PATH}"

exec "${VENV_DIR}/bin/jupyter-lab" \
  --no-browser \
  --ip=0.0.0.0 \
  --port=$PORT \
  --ServerApp.token='' \
  --ServerApp.custom_display_url="http://localhost:$PORT/lab"
EOF
# Bake in the venv path
sed -i "s#__VENV_DIR_PLACEHOLDER__#${VENV_DIR}#g" /usr/local/bin/notebook
chmod +x /usr/local/bin/notebook

# ---- friendly summary ----
"${VENV_PY}" -V || true
"${VENV_DIR}/bin/pip" --version || true
echo "✅ pyenv root (for reference): ${PYENV_ROOT}"
echo "✅ Venvs root (for reference): ${VENV_ROOT}"
echo "✅ Stable Python symlink at ${STABLE_PY_LINK}"
echo "✅ Active venv at ${VENV_DIR}"
echo "✅ Jupyter kernel '${JUPYTER_KERNEL_NAME}' registered at ${KDIR} with display name '${JUPYTER_KERNEL_DISPLAY}'"
echo "✅ Bash kernel registered at ${BASH_KDIR}"

echo
echo "Use it now in this shell (without reopening):"
echo "  . ${PROFILE_FILE} && python -V && which python"
