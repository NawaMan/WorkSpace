#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- configurable args (safe defaults) ----
PY_VERSION=${1:-3.11}              # accepts X.Y or X.Y.Z (exact patch recommended)
PYENV_ROOT="/opt/pyenv"            # system-wide pyenv
VENV_ROOT="/opt/venvs"             # shared venvs root
PIP_CACHE_DIR="/opt/pip-cache"     # shared pip cache
STABLE_PY_LINK="/opt/python"       # stable, version-agnostic symlink
PROFILE_FILE="/etc/profile.d/99-custom.sh"

# New: system-wide location to host UV-installed pythons (to avoid /root paths)
UV_PYTHONS_DIR="/opt/local-pythons"

# (kept for compatibility; not used now that Jupyter code is removed)
JUPYTER_KERNEL_NAME="${JUPYTER_KERNEL_NAME:-python-opt}"
JUPYTER_KERNEL_DISPLAY="${JUPYTER_KERNEL_DISPLAY:-Python (/opt/python)}"
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"  # system-wide

export DEBIAN_FRONTEND=noninteractive

# ---- base tools (no compilers needed) ----
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git tini xz-utils rsync
rm -rf /var/lib/apt/lists/*

# ---- dirs & shared perms ----
mkdir -p "$PYENV_ROOT" "$VENV_ROOT" "$PIP_CACHE_DIR" "$UV_PYTHONS_DIR"
chmod 0755 "$PYENV_ROOT"
chmod 0755 "$UV_PYTHONS_DIR"
chmod 1777 "$VENV_ROOT" "$PIP_CACHE_DIR"

# ---- install or reuse pyenv (idempotent) ----
if [ -x "${PYENV_ROOT}/bin/pyenv" ]; then
  echo "ℹ️  Found existing pyenv at ${PYENV_ROOT} — reusing."
else
  echo "⬇️  Installing pyenv to ${PYENV_ROOT} ..."
  git clone --depth 1 https://github.com/pyenv/pyenv.git "$PYENV_ROOT"
fi

# Make pyenv available in this shell
export PYENV_ROOT
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$("$PYENV_ROOT/bin/pyenv" init -)"

# ---- install uv (fast prebuilt CPython manager) ----
if ! command -v uv >/dev/null 2>&1; then
  echo "⬇️  Installing uv (prebuilt Python manager) ..."
  INSTALL_DIR="/usr/local/uv"
  curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$INSTALL_DIR" sh

  # Add uv to PATH (handles both $INSTALL_DIR and $INSTALL_DIR/bin layouts)
  if [ -x "$INSTALL_DIR/uv" ]; then
    export PATH="$INSTALL_DIR:$PATH"
  elif [ -x "$INSTALL_DIR/bin/uv" ]; then
    export PATH="$INSTALL_DIR/bin:$PATH"
  fi
  hash -r 2>/dev/null || true
fi
command -v uv >/dev/null 2>&1 || { echo "❌ uv not on PATH"; exit 1; }

# ---- resolve exact patch if only X.Y was given (NO --resolve) ----
if [[ "$PY_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "🔎 Installing latest patch for $PY_VERSION via uv and detecting exact version ..."
  uv python install "$PY_VERSION" >/dev/null
  UV_PY_BIN="$(uv python find "$PY_VERSION")"
  [ -n "$UV_PY_BIN" ] || { echo "❌ uv could not find installed Python $PY_VERSION"; exit 1; }
  PY_VERSION="$("$UV_PY_BIN" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))')"
fi

# ---- ensure prebuilt CPython $PY_VERSION is available via uv ----
echo "⚡ Ensuring prebuilt CPython $PY_VERSION is available ..."
uv python install "$PY_VERSION" >/dev/null
UV_PY_BIN="$(uv python find "$PY_VERSION")"
[ -n "$UV_PY_BIN" ] || { echo "❌ uv could not find installed Python $PY_VERSION"; exit 1; }

UV_PREFIX="$(dirname "$(dirname "$UV_PY_BIN")")"
[ -x "$UV_PREFIX/bin/python" ] || { echo "❌ expected $UV_PREFIX/bin/python"; exit 1; }

# ---- COPY uv interpreter out of /root into world-readable location ----
# Many uv installs end up under /root/.local/share/uv when run as root; users can’t traverse /root.
# Mirror that interpreter tree into /opt/local-pythons/$PY_VERSION and link pyenv to it.
DEST_PREFIX="${UV_PYTHONS_DIR}/${PY_VERSION}"
if [ -x "${DEST_PREFIX}/bin/python" ]; then
  echo "ℹ️  Using existing system Python at ${DEST_PREFIX}."
else
  echo "📦  Copying Python $PY_VERSION from ${UV_PREFIX} to ${DEST_PREFIX} ..."
  mkdir -p "${DEST_PREFIX}"
  rsync -a "${UV_PREFIX}/" "${DEST_PREFIX}/"
  # ensure everyone can traverse/execute
  chmod -R a+rX "${DEST_PREFIX}"
fi

# ---- register this interpreter inside pyenv (no build) ----
mkdir -p "$PYENV_ROOT/versions"
ln -snf "$DEST_PREFIX" "$PYENV_ROOT/versions/$PY_VERSION"

PY_PREFIX="$("$PYENV_ROOT/bin/pyenv" prefix "$PY_VERSION")"
[ -x "$PY_PREFIX/bin/python" ] || { echo "❌ pyenv prefix invalid"; exit 1; }

# ---- create venv at a fixed path (idempotent) ----
SERIES="${PY_VERSION%.*}"            # e.g. 3.13.7 -> 3.13
ENV_NAME="py${SERIES//./}"           # py313
ENV_PATH="${VENV_ROOT}/${ENV_NAME}"

if [ -d "${ENV_PATH}" ]; then
  echo "ℹ️  Venv '${ENV_NAME}' already exists at ${ENV_PATH} — skipping creation."
else
  echo "🧪  Creating venv '${ENV_NAME}' at ${ENV_PATH} ..."
  "${PY_PREFIX}/bin/python" -m venv "${ENV_PATH}"
  "${ENV_PATH}/bin/python" -m pip install --upgrade pip setuptools wheel
  # --- minimal hardening so `python` always exists even if only `python3` was created ---
  [ -x "${ENV_PATH}/bin/python" ] || { [ -x "${ENV_PATH}/bin/python3" ] && ln -sfn python3 "${ENV_PATH}/bin/python"; }
fi
chmod -R 0777 "${ENV_PATH}"

# ---- stable symlink & convenience shims ----
ln -snf "$ENV_PATH" "$STABLE_PY_LINK"
ln -sfn "${STABLE_PY_LINK}/bin/python" /usr/local/bin/python || true
ln -sfn "${STABLE_PY_LINK}/bin/pip"    /usr/local/bin/pip    || true

# ---- system-wide shell defaults ----
cat >"$PROFILE_FILE" <<'EOF'
export PYENV_ROOT="/opt/pyenv"
export PY_STABLE="/opt/python"
if [ -d "${PY_STABLE}/bin" ] && [[ ":$PATH:" != *":${PY_STABLE}/bin:"* ]]; then
  export PATH="${PY_STABLE}/bin:${PATH}"
fi
if [ -d "${PYENV_ROOT}/bin" ] && [[ ":$PATH:" != *":${PYENV_ROOT}/bin:"* ]]; then
  export PATH="${PYENV_ROOT}/bin:${PATH}"
fi
export PIP_CACHE_DIR="/opt/pip-cache"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONUNBUFFERED=1
EOF
chmod 0644 "$PROFILE_FILE"

# ---- summary ----
"${STABLE_PY_LINK}/bin/python" -V || true
# shellcheck disable=SC2230
"${STABLE_PY_LINK}/bin/pip" --version || true
echo "✅ pyenv at ${PYENV_ROOT}"
echo "✅ Python ${PY_VERSION} copied to ${DEST_PREFIX} and registered under pyenv at ${PY_PREFIX}"
echo "✅ Venv '${ENV_NAME}' at ${ENV_PATH} (world-writable)"
echo "✅ Stable Python symlink at ${STABLE_PY_LINK} and shims in /usr/local/bin"
echo "✅ ${PROFILE_FILE} puts /opt/python/bin first and sets a shared pip cache"
echo
echo "Use it now in this shell:"
echo "  . /etc/profile.d/99-custom.sh && python -V && which python"
