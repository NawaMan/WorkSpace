#!/usr/bin/env bash

# notebook-setup.sh
# Uses consolidated Python setup (/opt/workspace/setups/python-setup.sh),
# then installs Jupyter and registers kernels + a "notebook" launcher.
# NOTE: Bash kernel installation is delegated to ${FEATURE_DIR}/bash-nb-kernel-setup.sh
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---- root check (match other scripts) ----
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi


# Load python env exported by the base setup
source /etc/profile.d/53-ws-python.sh 2>/dev/null || true


# ---- Jupyter kernel registration tunables (match code-server) ----
JUPYTER_KERNEL_NAME="${JUPYTER_KERNEL_NAME:-python}"
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"


# ---- helper: install + verify Jupyter in venv ----
ensure_jupyterlab_in_venv() {
  env PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
    python -m pip install -U pip setuptools wheel

  env PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
    python -m pip install -U \
      "ipykernel>=6"         \
      "jupyter_core>=5"      \
      "jupyter_server>=2"    \
      "jupyterlab_server>=2" \
      "jupyterlab>=4,<6"

  # Verify importability
  if ! python - <<'PY'
import importlib.util as u
ok = all(u.find_spec(m) for m in ("jupyterlab","ipykernel"))
raise SystemExit(0 if ok else 1)
PY
  then
    return 1
  fi
  return 0
}


echo "🧩 Installing Jupyter into venv ${WS_VENV_DIR} ..."
if ! ensure_jupyterlab_in_venv; then
  ACTUAL="$(python -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' || echo "?")"
  echo "❌ JupyterLab not importable in ${WS_VENV_DIR} (Python ${ACTUAL})."
  echo "   If you chose a very new Python (e.g., 3.13), the ecosystem may not be ready yet."
  exit 1
fi


# Recompute actual version/display in case we fell back and recreated the venv
ACTUAL_VER="$(python -c 'import sys;print(".".join(map(str,sys.version_info[:3])))')"
JUPYTER_KERNEL_DISPLAY="${JUPYTER_KERNEL_DISPLAY:-Python ${ACTUAL_VER} (venv)}"

# ---- Register venv Python as a Jupyter kernel (primary: python3) ----
KDIR_BASE="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels"
KDIR="${KDIR_BASE}/${JUPYTER_KERNEL_NAME}"
rm -rf "${KDIR}" || true
python -m ipykernel install           \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --name="${JUPYTER_KERNEL_NAME}"     \
  --display-name="${JUPYTER_KERNEL_DISPLAY}"
chmod -R a+rX "${KDIR}" || true


# ---- Create startup script (ensures terminals inherit the venv) ----
STARTER_FILE=/usr/local/bin/notebook
cat > ${STARTER_FILE} <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-10000}

# Ensure PATH and /opt/python are active in non-login shells
source /etc/profile.d/53-ws-python.sh 2>/dev/null || true

# Make sure non-Python kernels in the venv are visible if present
export JUPYTER_PATH="${WS_VENV_DIR}/share/jupyter:/usr/local/share/jupyter:/usr/share/jupyter${JUPYTER_PATH:+:$JUPYTER_PATH}"

exec "${WS_VENV_DIR}/bin/jupyter-lab" \
  --no-browser \
  --ip=0.0.0.0 \
  --port=$PORT \
  --ServerApp.token='' \
  --ServerApp.custom_display_url="http://localhost:$PORT/lab" \
  --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}'
EOF
# Bake in the venv path
_safe() { printf '%s' "$1" | sed -e 's/[&]/\\&/g'; }
sed -i "s#__VENV_DIR_PLACEHOLDER__#$(_safe "${WS_VENV_DIR}")#g" /usr/local/bin/notebook
chmod +x ${STARTER_FILE}

# ---- friendly summary ----
python --version || true
pip    --version || true

BASH_KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/bash"
echo "✅ pyenv root:  ${WS_PYENV_ROOT}"
echo "✅ Venvs root:  ${WS_VENV_DIR}"
echo "✅ Active venv: ${WS_VENV_DIR}"
echo "✅ Jupyter kernel '${JUPYTER_KERNEL_NAME}' registered at ${KDIR} with display name '${JUPYTER_KERNEL_DISPLAY}'"

echo 
echo "To start using notebook, start a new shell session, OR"
echo "Load the Notebook helpers into THIS shell (no restart):"
echo "     source /etc/profile.d/53-ws-python.sh         \\"
echo "  && source /etc/profile.d/55-ws-notebook-info.sh"
echo
echo "Then you can run:"
echo "  notebook-setup-info"
echo "  notebook            # launches JupyterLab on port 10000"

echo
echo "Use it now in this shell (without reopening):"
echo "python -V && which python"
