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

# Use python-setup.sh exactly like setup-code-server-jupyter.sh
PY_VERSION=${1:-3.12}                    # accepts X.Y or X.Y.Z
FEATURE_DIR=${FEATURE_DIR:-/opt/workspace/setups}
"${FEATURE_DIR}/python-setup.sh" "${PY_VERSION}"

# Load python env exported by the base setup
source /etc/profile.d/53-python.sh         2>/dev/null || true
source /etc/profile.d/54-python-version.sh 2>/dev/null || true

# Choose the venv path:
# - Prefer the series symlink (/opt/venvs/py3.12) so kernels survive patch bumps
# - Fall back to the exact patch if needed
VENV_DIR="${VENV_DIR:-${VENV_SERIES_DIR:-/opt/venvs/py${PY_STABLE_VERSION:-${PY_VERSION}}}}"
VENV_PY="${VENV_DIR}/bin/python"

# Ensure venv exists (should already be created by python-setup.sh; keep as a guard)
if [ ! -x "${VENV_PY}" ]; then
  mkdir -p "${VENV_DIR%/*}"
  "${PY_STABLE}/bin/python" -m venv "${VENV_DIR}"
fi

# ---- Jupyter kernel registration tunables (match code-server) ----
JUPYTER_KERNEL_NAME="${JUPYTER_KERNEL_NAME:-python3}"
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"  # installs under /usr/local/share/jupyter/kernels/<name>

# ---- helper: install + verify Jupyter in venv ----
ensure_jupyterlab_in_venv() {
  env PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
    "${VENV_PY}" -m pip install -U pip setuptools wheel

  env PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
    "${VENV_PY}" -m pip install -U \
      "ipykernel>=6" \
      "jupyter_core>=5" \
      "jupyter_server>=2" \
      "jupyterlab_server>=2" \
      "jupyterlab>=4,<6"

  # Verify importability
  if ! "${VENV_PY}" - <<'PY'
import importlib.util as u
ok = all(u.find_spec(m) for m in ("jupyterlab","ipykernel"))
raise SystemExit(0 if ok else 1)
PY
  then
    return 1
  fi
  return 0
}

echo "🧩 Installing Jupyter into venv ${VENV_DIR} ..."
if ! ensure_jupyterlab_in_venv; then
  ACTUAL="$("${VENV_PY}" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' || echo "?")"
  echo "❌ JupyterLab not importable in ${VENV_DIR} (Python ${ACTUAL})."
  echo "   If you chose a very new Python (e.g., 3.13), the ecosystem may not be ready yet."
  exit 1
fi

# Recompute actual version/display in case we fell back and recreated the venv
ACTUAL_VER="$("${VENV_PY}" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))')"
JUPYTER_KERNEL_DISPLAY="${JUPYTER_KERNEL_DISPLAY:-Python ${ACTUAL_VER} (venv)}"

# ---- Register venv Python as a Jupyter kernel (primary: python3) ----
KDIR_BASE="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels"
KDIR="${KDIR_BASE}/${JUPYTER_KERNEL_NAME}"
rm -rf "${KDIR}" || true
"${VENV_PY}" -m ipykernel install \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --name="${JUPYTER_KERNEL_NAME}" \
  --display-name="${JUPYTER_KERNEL_DISPLAY}"
chmod -R a+rX "${KDIR}" || true

# ---- Add series alias (e.g., python3.12) pointing to the same venv ----
ACTUAL_SERIES="$("${VENV_PY}" -c 'import sys;print(".".join(map(str,sys.version_info[:2])))')"
KDIR_ALIAS="${KDIR_BASE}/python${ACTUAL_SERIES}"
rm -rf "${KDIR_ALIAS}" || true
"${VENV_PY}" -m ipykernel install \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --name="python${ACTUAL_SERIES}" \
  --display-name="Python ${ACTUAL_VER} (venv)"
chmod -R a+rX "${KDIR_ALIAS}" || true

# ---- Bash kernel: delegate to external installer ----
echo "🧩 Installing Bash kernel via external script ..."
if [ -x "${FEATURE_DIR}/bash-nb-kernel-setup.sh" ]; then
  "${FEATURE_DIR}/bash-nb-kernel-setup.sh" --venv-dir "${VENV_DIR}" --prefix "${JUPYTER_KERNEL_PREFIX}"
else
  echo "⚠️  ${FEATURE_DIR}/bash-nb-kernel-setup.sh not found or not executable; skipping Bash kernel install." >&2
fi


# ---- notebook_setup_info helper (for new shells) ----
PROFILE_NOTEBOOK_INFO="/etc/profile.d/55-notebook-info.sh"
cat >"$PROFILE_NOTEBOOK_INFO" <<'EOF'
# Jupyter/Notebook setup info (managed by notebook-setup.sh)
notebook_setup_info() {
  set -o pipefail

  _ok()   { printf "✅ %s\n" "$*"; }
  _hdr()  { printf "\n\033[1m%s\033[0m\n" "$*"; }
  _warn() { printf "⚠️  %s\n" "$*"; }

  local PY_STABLE="${PY_STABLE:-/opt/python}"
  local VENV_SERIES_DIR="${VENV_SERIES_DIR:-}"
  local VENV_DIR=""
  local NB="/usr/local/bin/notebook"

  # Try to read the baked venv path from the launcher
  if [ -r "$NB" ]; then
    local line
    line="$(grep -E '^VENV_DIR=' "$NB" 2>/dev/null || true)"
    if [ -n "$line" ]; then
      unset VENV_DIR
      eval "$line"   # sets VENV_DIR="${VENV_DIR:-/path/from/bake}"
      VENV_DIR="${VENV_DIR:-}"
    fi
  fi

  # Fallbacks
  [ -z "$VENV_DIR" ] && [ -n "$VENV_SERIES_DIR" ] && VENV_DIR="$VENV_SERIES_DIR"
  if [ -z "$VENV_DIR" ] && [ -x "$PY_STABLE/bin/python" ]; then
    local series
    series="$("$PY_STABLE/bin/python" - <<'PY' 2>/dev/null || true
import sys; print(".".join(map(str,sys.version_info[:2])))
PY
)"
    [ -d "/opt/venvs/py${series}" ] && VENV_DIR="/opt/venvs/py${series}"
  fi

  local PYBIN="${VENV_DIR:+$VENV_DIR/bin/python}"
  [ -x "${PYBIN:-}" ] || PYBIN="$PY_STABLE/bin/python"

  _hdr "Jupyter/Notebook setup summary"
  [ -x "$PYBIN" ] && _ok "$("$PYBIN" -V 2>&1)" || _warn "No Python resolved"
  [ -n "$VENV_DIR" ] && _ok "Active venv: $VENV_DIR" || _warn "No venv resolved"
  [ -x "$NB" ] && _ok "Launcher: $NB" || _warn "Launcher not found: $NB"

  _hdr "Jupyter components"
  "$PYBIN" - <<'PY' 2>/dev/null || true
def v(mod):
    try:
        import importlib
        m = importlib.import_module(mod)
        print(f"{mod}: {getattr(m,'__version__','?')}")
    except Exception:
        print(f"{mod}: (not importable)")
for m in ["jupyterlab","jupyter_server","jupyter_core","ipykernel","jupyterlab_server","bash_kernel"]:
    v(m)
PY

  _hdr "Kernelspecs (system)"
  jupyter kernelspec list 2>/dev/null || true
}
alias notebook-setup-info='notebook_setup_info'
EOF
chmod 0644 "$PROFILE_NOTEBOOK_INFO"


# ---- Create startup script (ensures terminals inherit the venv) ----
cat > /usr/local/bin/notebook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-10000}

# Ensure PATH and /opt/python are active in non-login shells
source /etc/profile.d/53-python.sh         2>/dev/null || true
source /etc/profile.d/54-python-version.sh 2>/dev/null || true

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
  --ServerApp.custom_display_url="http://localhost:$PORT/lab" \
  --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}'
EOF
# Bake in the venv path
_safe() { printf '%s' "$1" | sed -e 's/[&]/\\&/g'; }
sed -i "s#__VENV_DIR_PLACEHOLDER__#$(_safe "${VENV_DIR}")#g" /usr/local/bin/notebook
chmod +x /usr/local/bin/notebook

# ---- friendly summary ----
"${VENV_PY}" -V || true
"${VENV_DIR}/bin/pip" --version || true
BASH_KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/bash"
echo "✅ pyenv root (for reference): ${PYENV_ROOT}"
echo "✅ Venvs root (for reference): ${VENV_ROOT}"
echo "✅ Stable Python symlink at ${PY_STABLE}"
echo "✅ Active venv at ${VENV_DIR}"
echo "✅ Jupyter kernel '${JUPYTER_KERNEL_NAME}' registered at ${KDIR} with display name '${JUPYTER_KERNEL_DISPLAY}'"
echo "✅ Jupyter alias kernel 'python${ACTUAL_SERIES}' registered at ${KDIR_ALIAS}"
echo "✅ Bash kernel installed via ${FEATURE_DIR}/bash-nb-kernel-setup.sh (expected at ${BASH_KDIR})"

echo 
echo "To start using notebook, start a new shell session, OR"
echo "Load the Notebook helpers into THIS shell (no restart):"
echo "  . /etc/profile.d/53-python.sh \\"
echo "    && . /etc/profile.d/54-python-version.sh \\"
echo "    && . /etc/profile.d/55-notebook-info.sh"
echo
echo "Then you can run:"
echo "  notebook-setup-info"
echo "  notebook            # launches JupyterLab on port 10000"

echo
echo "Use it now in this shell (without reopening):"
echo "python -V && which python"
