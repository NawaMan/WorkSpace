#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- configurable args (safe defaults) ----
PY_VERSION=${1:-3.12}              # accepts X.Y or X.Y.Z (exact patch recommended)
PYENV_ROOT="/opt/pyenv"            # system-wide pyenv
VENV_ROOT="/opt/venvs"             # shared venvs root
PIP_CACHE_DIR="/opt/pip-cache"     # shared pip cache
STABLE_PY_LINK="/opt/python"       # stable, version-agnostic symlink
PROFILE_FILE="/etc/profile.d/99-custom.sh"
PROFILE_VER_FILE="/etc/profile.d/99-python-version.sh"

# System-wide location to host UV-installed pythons (mirrored out of /root, etc.)
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
  UV_PY_BIN="$(uv python find "$PY_VERSION" || true)"
  [ -n "${UV_PY_BIN}" ] || { echo "❌ uv could not find installed Python $PY_VERSION"; exit 1; }
  # If we accidentally got a project venv, we’ll fix it in the guard below.
  PY_VERSION="$("$UV_PY_BIN" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null || echo "$PY_VERSION")"
fi

# ---- ensure prebuilt CPython $PY_VERSION is available via uv ----
echo "⚡ Ensuring prebuilt CPython $PY_VERSION is available ..."
you_can_ignore_output="$(uv python install "$PY_VERSION" >/dev/null || true)"
UV_PY_BIN="$(uv python find "$PY_VERSION")"
[ -n "$UV_PY_BIN" ] || { echo "❌ uv could not find installed Python $PY_VERSION"; exit 1; }

# ---- GUARD: reject project venv paths (…/.venv/…) ----
if [[ "$UV_PY_BIN" == *"/.venv/"* ]]; then
  echo "⚠️  uv returned a project venv interpreter: $UV_PY_BIN"
  echo "    Forcing a clean UV-managed interpreter..."
  uv python install "$PY_VERSION" >/dev/null
  UV_PY_BIN="$(uv python find "$PY_VERSION")"
  [[ "$UV_PY_BIN" != *"/.venv/"* ]] || { echo "❌ still pointing to a venv; aborting to avoid copying a broken tree"; exit 1; }
fi

UV_PREFIX="$(dirname "$(dirname "$UV_PY_BIN")")"
[ -x "$UV_PREFIX/bin/python" ] || { echo "❌ expected $UV_PREFIX/bin/python"; exit 1; }

# ---- COPY uv interpreter out of /root into world-readable location ----
# Mirror interpreter tree into /opt/local-pythons/$PY_VERSION and link pyenv to it.
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

# ---- create venv at a fixed path using uv (avoid ensurepip issues) ----
# Use full patch in the directory name: /opt/venvs/py3.12.11
ENV_NAME="py${PY_VERSION}"            # e.g. py3.12.11
ENV_PATH="${VENV_ROOT}/${ENV_NAME}"

if [ -d "${ENV_PATH}" ]; then
  echo "ℹ️  Venv '${ENV_NAME}' already exists at ${ENV_PATH} — skipping creation."
else
  echo "🧪  Creating venv '${ENV_NAME}' at ${ENV_PATH} using uv ..."
  UV_PY_EXE="${DEST_PREFIX}/bin/python"
  [ -x "$UV_PY_EXE" ] || { echo "❌ expected $UV_PY_EXE"; exit 1; }

  # Create the venv
  uv venv --python "$UV_PY_EXE" "${ENV_PATH}"

  # ✅ Ensure classic pip/setuptools/wheel exist inside the venv
  # (some tooling calls 'pip' directly; uv alone won't provide that console script)
  uv pip install --python "${ENV_PATH}/bin/python" --upgrade pip setuptools wheel
fi
# safer perms than 0777
chmod -R 0755 "${ENV_PATH}"

# Optional: maintain a series convenience symlink (e.g., py3.12 -> py3.12.11)
SERIES="${PY_VERSION%.*}"                              # 3.12
ln -sfn "${ENV_PATH}" "${VENV_ROOT}/py${SERIES}"

# ---- stable symlink & convenience shims ----
ln -snf "$ENV_PATH" "$STABLE_PY_LINK"
ln -sfn "${STABLE_PY_LINK}/bin/python" /usr/local/bin/python || true
ln -sfn "${STABLE_PY_LINK}/bin/pip"    /usr/local/bin/pip    || true

# refresh command lookup cache in case this shell keeps running more commands
hash -r || true

# ---- system-wide shell defaults (last install wins) ----
cat >"$PROFILE_FILE" <<'EOF'
# Stable Python (managed by python-setup.sh)
export PYENV_ROOT="/opt/pyenv"
export PY_STABLE="/opt/python"
export PIP_CACHE_DIR="/opt/pip-cache"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONUNBUFFERED=1

# Put /opt/python/bin first exactly once
case ":$PATH:" in
  *":${PY_STABLE}/bin:"*) ;;
  *) PATH="${PY_STABLE}/bin:${PATH}" ;;
esac

# Ensure pyenv shims are on PATH (once)
case ":$PATH:" in
  *":${PYENV_ROOT}/bin:"*) ;;
  *) PATH="${PYENV_ROOT}/bin:${PATH}" ;;
esac

# Helpful for VS Code/Jupyter to find kernels from the current interpreter
export JUPYTER_PATH="${PY_STABLE}/share/jupyter:/usr/local/share/jupyter:/usr/share/jupyter${JUPYTER_PATH:+:$JUPYTER_PATH}"

export PATH
EOF
chmod 0644 "$PROFILE_FILE"

# ---- dynamic series auto-activation & ACTIVE_VER (for new shells) ----
cat >"$PROFILE_VER_FILE" <<'EOF'
# Auto-activate the series venv that matches /opt/python (managed by python-setup.sh)

# 1) Resolve active version from the stable symlink
if [ -x /opt/python/bin/python ]; then
  export PY_STABLE_VERSION="$(/opt/python/bin/python -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null || true)"
else
  export PY_STABLE_VERSION=""
fi

# 2) Compute the series (X.Y) from PY_STABLE_VERSION robustly
# Accepts: 3.12.11 -> 3.12, 3.12 -> 3.12, 3 -> (empty/error path)
if [[ -n "$PY_STABLE_VERSION" && "$PY_STABLE_VERSION" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]]; then
  export PY_SERIES="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
else
  export PY_SERIES=""
fi

# Choose the series venv dir if available, else fall back to /opt/python
VENV_SERIES_DIR=""
if [ -n "$PY_SERIES" ] && [ -d "/opt/venvs/py${PY_SERIES}/bin" ]; then
  VENV_SERIES_DIR="/opt/venvs/py${PY_SERIES}"
elif [ -x /opt/python/bin/python ]; then
  VENV_SERIES_DIR="/opt/python"
fi
export VENV_SERIES_DIR

# 3) Put the chosen interpreter FIRST on PATH (exactly once)
#    Strip any other /opt/venvs/py*/bin entries to avoid confusion.
if [ -n "$VENV_SERIES_DIR" ] && [ -d "${VENV_SERIES_DIR}/bin" ]; then
  CLEAN_PATH="$(printf '%s' "$PATH" \
    | awk -v RS=: -v ORS=: '!/^[[:space:]]*$/{print}' \
    | sed -E 's#(^|:)/opt/venvs/py[0-9]+\.[0-9]+(\.[0-9]+)?/bin(:|$)#\1#g; s#::#:#g; s#^:||:$##g')"

  case ":$CLEAN_PATH:" in
    *":${VENV_SERIES_DIR}/bin:"*) PATH="$CLEAN_PATH" ;;
    *) PATH="${VENV_SERIES_DIR}/bin:${CLEAN_PATH}" ;;
  esac
  export PATH
fi

# 4) Keep Jupyter discovery path aligned
if [ -n "$VENV_SERIES_DIR" ]; then
  JP="${VENV_SERIES_DIR}/share/jupyter:/usr/local/share/jupyter:/usr/share/jupyter"
  case ":${JUPYTER_PATH:-}:" in
    *":${VENV_SERIES_DIR}/share/jupyter:"*) ;;      # already there
    *) export JUPYTER_PATH="${JP}${JUPYTER_PATH:+:$JUPYTER_PATH}" ;;
  esac
fi
EOF
chmod 0644 "$PROFILE_VER_FILE"

# ---- summary ----
ACTIVE_VER="$("${STABLE_PY_LINK}/bin/python" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null || true)"
"${STABLE_PY_LINK}/bin/python" -V || true
"${STABLE_PY_LINK}/bin/pip" --version || true
echo "✅ pyenv at ${PYENV_ROOT}"
echo "✅ Python ${PY_VERSION} mirrored at ${DEST_PREFIX} and registered under pyenv at ${PY_PREFIX}"
echo "✅ Venv '${ENV_NAME}' at ${ENV_PATH}"
echo "✅ Stable Python symlink at ${STABLE_PY_LINK} → $(readlink -f "${STABLE_PY_LINK}")"
echo "✅ ${PROFILE_FILE} ensures /opt/python/bin first; ${PROFILE_VER_FILE} auto-activates /opt/venvs/py\${PY_SERIES}"
echo "✅ ACTIVE_VER detected now: ${ACTIVE_VER}"
echo
echo "Open a NEW shell and verify:"
echo "  . /etc/profile.d/99-custom.sh && . /etc/profile.d/99-python-version.sh"
echo "  which python && python -V"
echo "  echo \"PY_STABLE_VERSION=\$PY_STABLE_VERSION  PY_SERIES=\$PY_SERIES  VENV_SERIES_DIR=\$VENV_SERIES_DIR\""
