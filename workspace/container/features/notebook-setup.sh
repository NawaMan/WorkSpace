#!/bin/bash
# pythong-setup.sh
# Builds CPython via pyenv, creates a shared venv, exposes it at /opt/python,
# and registers /opt/python as a system-wide Jupyter kernel.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- configurable args (safe defaults) ----
PY_VERSION=${1:-3.11}                # accepts 3.13, 3.13.7, 3.12, ...
PYENV_ROOT="/opt/pyenv"              # system-wide pyenv
VENV_ROOT="/opt/venvs"               # shared venvs root  (fixed: define before use)
PIP_CACHE_DIR="/opt/pip-cache"       # shared pip cache
STABLE_PY_LINK="/opt/python"         # stable, version-agnostic symlink
PROFILE_FILE="/etc/profile.d/99-custom.sh"

# ---- Jupyter kernel registration tunables (can override via env) ----
JUPYTER_KERNEL_NAME="${JUPYTER_KERNEL_NAME:-python-opt}"
JUPYTER_KERNEL_DISPLAY="${JUPYTER_KERNEL_DISPLAY:-Python (/opt/python)}"
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"  # installs under /usr/local/share/jupyter/kernels/<name>

# Make these visible during this script, too
export PYENV_ROOT
export PATH="$PYENV_ROOT/bin:$PATH"
export PIP_CACHE_DIR

# ---- helpers ----
enforce_shared_perms() {
  mkdir -p "$VENV_ROOT" "$PIP_CACHE_DIR"
  # sticky world-writable (like /tmp) so any runtime user can install packages
  chmod 1777 "$VENV_ROOT" "$PIP_CACHE_DIR"
  # pyenv itself should be readable/executable by all; typically only root writes here
  chmod 0755 "$PYENV_ROOT" || true
}

resolve_latest_patch() {
  # $1 is an X.Y series, returns X.Y.Z (latest) or empty string
  local series="$1"
  "$PYENV_ROOT/bin/pyenv" install -l \
    | sed -n "s/^[[:space:]]*\(${series}\.[0-9]\+\)$/\1/p" \
    | tail -n 1
}

ensure_python_series() {
  # Ensures a pyenv CPython X.Y.Z and venv /opt/venvs/pyX.Y.Z exist, links /opt/python -> that venv
  # $1 = X.Y or X.Y.Z
  local req="$1"
  local ver="$req"
  if [[ "$req" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "🔎 Resolving latest patch for $req ..."
    ver="$(resolve_latest_patch "$req")"
    if [[ -z "$ver" ]]; then
      echo "❌ Could not find a patch release for $req in pyenv's list." >&2
      exit 1
    fi
    echo "✅ Using $ver"
  fi

  local series="${ver%.*}"           # X.Y
  local env_name="py${ver}"          # <= keep dots: py3.13.7
  local env_path="${VENV_ROOT}/${env_name}"

  # Install CPython via pyenv if missing
  if "$PYENV_ROOT/bin/pyenv" versions --bare | grep -qx "${ver}"; then
    echo "ℹ️  Python ${ver} already installed under pyenv."
  else
    echo "🛠️  Building Python ${ver} via pyenv (this may take a while) ..."
    export PYTHON_CONFIGURE_OPTS="--enable-optimizations --with-lto"
    "$PYENV_ROOT/bin/pyenv" install -s "${ver}"
  fi
  local py_prefix="$("$PYENV_ROOT/bin/pyenv" prefix "${ver}")"

  # Create venv if missing
  if [ -d "${env_path}" ]; then
    echo "ℹ️  Venv '${env_name}' already exists at ${env_path} — skipping creation."
  else
    echo "🧪  Creating venv '${env_name}' at ${env_path} ..."
    "${py_prefix}/bin/python" -m venv "${env_path}"
    "${env_path}/bin/python" -m pip install --upgrade pip setuptools wheel
  fi

  chmod -R 0777 "${env_path}"

  # Point stable symlink at this venv
  ln -snf "${env_path}" "${STABLE_PY_LINK}"

  # Optional convenience symlink: /opt/venvs/py3.13 -> /opt/venvs/py3.13.7
  ln -sfn "${env_path}" "${VENV_ROOT}/py${series}"

  # Return values via globals for later steps
  PY_VERSION_RESOLVED="$ver"
  ENV_NAME="$env_name"
  ENV_PATH="$env_path"
}

ensure_jupyterlab_in_stable() {
  # Installs JupyterLab + friends into /opt/python and verifies import
  "${STABLE_PY_LINK}/bin/python" -m pip install -U pip setuptools wheel
  "${STABLE_PY_LINK}/bin/python" -m pip install -U \
    "ipykernel>=6" \
    "jupyter_core>=5" \
    "jupyter_server>=2" \
    "jupyterlab_server>=2" \
    "jupyterlab>=4,<6"

  # Verify importability
  if ! "${STABLE_PY_LINK}/bin/python" - <<'PY'
import importlib.util as u
raise SystemExit(0 if u.find_spec("jupyterlab") else 1)
PY
  then
    return 1
  fi
  return 0
}

# ---- base tools / build deps for CPython via pyenv ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y        \
  --no-install-recommends \
  build-essential         \
  ca-certificates         \
  curl                    \
  git                     \
  libbz2-dev              \
  libffi-dev              \
  libgdbm-dev             \
  liblzma-dev             \
  libncurses5-dev         \
  libnss3-dev             \
  libreadline-dev         \
  libsqlite3-dev          \
  libssl-dev              \
  tini                    \
  tk-dev                  \
  uuid-dev                \
  xz-utils                \
  zlib1g-dev
rm -rf /var/lib/apt/lists/*

mkdir -p "$PYENV_ROOT"
chmod 0755 "$PYENV_ROOT"

# apply perms once before install
enforce_shared_perms

# ---- install or reuse pyenv (idempotent) ----
if [ -x "${PYENV_ROOT}/bin/pyenv" ]; then
  echo "ℹ️  Found existing pyenv at ${PYENV_ROOT} — reusing."
else
  echo "⬇️  Installing pyenv to ${PYENV_ROOT} ..."
  git clone --depth 1 https://github.com/pyenv/pyenv.git "$PYENV_ROOT"
fi

# Initialize pyenv for this non-interactive shell
eval "$("$PYENV_ROOT/bin/pyenv" init -)"

# ---- ensure requested Python series and venv, point /opt/python there ----
ensure_python_series "$PY_VERSION"

# Re-apply shared perms in case anything changed
enforce_shared_perms

# ---- system-wide shell defaults for any future user/session ----
cat >"$PROFILE_FILE" <<'EOF'
# ---- container defaults (safe to source multiple times) ----
export PYENV_ROOT="/opt/pyenv"
# Put stable venv first
export PY_STABLE="/opt/python"
if [ -d "${PY_STABLE}/bin" ]; then
  case ":$PATH:" in *":${PY_STABLE}/bin:"*) : ;; *)
    export PATH="${PY_STABLE}/bin:${PATH}"
  esac
fi
# Expose pyenv (optional; you usually won't need it at runtime)
if [ -d "${PYENV_ROOT}/bin" ]; then
  case ":$PATH:" in *":${PYENV_ROOT}/bin:"*) : ;; *)
    export PATH="${PYENV_ROOT}/bin:${PATH}"
  esac
fi
# Shared pip cache & sane defaults
export PIP_CACHE_DIR="/opt/pip-cache"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONUNBUFFERED=1
# ---- end defaults ----
EOF
chmod 0644 "$PROFILE_FILE"

# ===== Install Jupyter (with repair) into the CURRENT /opt/python =====
echo "🧩 Installing Jupyter into ${STABLE_PY_LINK} (Python ${PY_VERSION_RESOLVED}) ..."
if ! ensure_jupyterlab_in_stable; then
  echo "⚠️  JupyterLab failed to import on Python ${PY_VERSION_RESOLVED} at ${STABLE_PY_LINK}."
  if [[ "${PY_VERSION_RESOLVED}" =~ ^3\.13(\.|$) ]]; then
    echo "↩️  Falling back to Python 3.12 for maximum compatibility ..."
    ensure_python_series "3.12"
    # perms again (new venv)
    enforce_shared_perms
    echo "🧩 Re-attempting JupyterLab install on ${PY_VERSION_RESOLVED} at ${STABLE_PY_LINK} ..."
    ensure_jupyterlab_in_stable || { echo "❌ JupyterLab still not importable after fallback." >&2; exit 1; }
  else
    echo "❌ JupyterLab install/verify failed (non-3.13). Aborting." >&2
    exit 1
  fi
fi

# ===== Register /opt/python as a Jupyter kernel (system-wide) =====
KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${JUPYTER_KERNEL_NAME}"
rm -rf "${KDIR}" || true
"${STABLE_PY_LINK}/bin/python" -m ipykernel install \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --name="${JUPYTER_KERNEL_NAME}" \
  --display-name="${JUPYTER_KERNEL_DISPLAY}"
chmod -R a+rX "${KDIR}" || true

# ===== Add a system-wide Bash kernel =====
echo "🧩 Installing Bash kernel and registering kernelspec ..."
"${STABLE_PY_LINK}/bin/python" -m pip install -q --upgrade bash_kernel
BASH_KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/bash"
rm -rf "${BASH_KDIR}" || true
"${STABLE_PY_LINK}/bin/python" -m bash_kernel.install --prefix="${JUPYTER_KERNEL_PREFIX}"
chmod -R a+rX "${BASH_KDIR}" || true

# ===== Create startup script (self-healing) =====
cat <<'EOF' >/usr/local/bin/notebook
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE_PORT="${WORKSPACE_PORT:-10000}"

source /etc/profile.d/99-custom.sh

exec /opt/python/bin/jupyter-lab \
  --no-browser \
  --ip=0.0.0.0 \
  --port="${WORKSPACE_PORT}" \
  --ServerApp.token='' \
  --ServerApp.custom_display_url="http://localhost:${WORKSPACE_PORT}/lab"
EOF
chmod +x /usr/local/bin/notebook

# ---- friendly summary ----
"${STABLE_PY_LINK}/bin/python" -V || true
"${STABLE_PY_LINK}/bin/pip" --version || true
echo "✅ pyenv at ${PYENV_ROOT}"
echo "✅ Python ${PY_VERSION_RESOLVED} installed under pyenv"
echo "✅ Venv '${ENV_NAME}' at ${ENV_PATH} (world-writable)"
echo "✅ Stable Python symlink at ${STABLE_PY_LINK} and shims in /usr/local/bin"
echo "✅ ${PROFILE_FILE} puts /opt/python/bin first and sets a shared pip cache"
echo "✅ Jupyter kernel '${JUPYTER_KERNEL_NAME}' registered at ${KDIR} with display name '${JUPYTER_KERNEL_DISPLAY}'"
echo "✅ Bash kernel registered at ${BASH_KDIR}"

echo
echo "Use it now in this shell (without reopening):"
echo "  . /etc/profile.d/99-custom.sh && python -V && which python"
