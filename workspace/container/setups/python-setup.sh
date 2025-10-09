#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- validate python version format ----
# accepts X.Y or X.Y.Z (exact patch recommended)
PY_VERSION=${1:-3.12}
if [[ ! "$PY_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "❌ Invalid Python version format: '$PY_VERSION'"
  echo "   Expected format: X.Y or X.Y.Z (e.g., 3.11 or 3.11.6)"
  exit 1
fi

# ---- configurable args (safe defaults) ----
PYENV_ROOT="/opt/pyenv"            # system-wide pyenv
VENV_ROOT="/opt/venvs"             # shared venvs root
PIP_CACHE_DIR="/opt/pip-cache"     # shared pip cache
STABLE_PY_LINK="/opt/python"       # stable, version-agnostic symlink
PROFILE_FILE="/etc/profile.d/53-python.sh"
PROFILE_VER_FILE="/etc/profile.d/54-python-version.sh"

# System-wide location to host UV-installed pythons (mirrored out of /root, etc.)
UV_PYTHONS_DIR="/opt/local-pythons"

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
chmod -R a+rX /usr/local/uv

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
_unused="$(uv python install "$PY_VERSION" >/dev/null || true)"
UV_PY_BIN="$(uv python find "$PY_VERSION")"
[ -n "$UV_PY_BIN" ] || { echo "❌ uv could not find installed Python $PY_VERSION"; exit 1; }

# ---- GUARD: reject project venv paths (…/.venv/…) ----
if [[ "$UV_PY_BIN" =~ /(\.venv|venv|\.env)[^/]*/bin/ ]]; then
  echo "⚠️  uv returned a project venv interpreter: $UV_PY_BIN"
  echo "    Forcing a clean UV-managed interpreter..."
  uv python install "$PY_VERSION" >/dev/null
  UV_PY_BIN="$(uv python find "$PY_VERSION")"
  [[ ! "$UV_PY_BIN" =~ /(\.venv|venv|\.env)[^/]*/bin/ ]] || {
    echo "❌ still pointing to a venv; aborting to avoid copying a broken tree"; exit 1; }
fi

UV_PREFIX="$(dirname "$(dirname "$UV_PY_BIN")")"
PY_EXE="$UV_PREFIX/bin/python"
[ -x "$PY_EXE" ] || PY_EXE="$UV_PREFIX/bin/python3"
[ -x "$PY_EXE" ] || { echo "❌ expected python or python3 in $UV_PREFIX/bin"; exit 1; }

# ---- sanity-check that we're mirroring a real Python prefix (not /usr) ----
SERIES="${PY_VERSION%.*}"  # e.g., 3.12

case "$UV_PREFIX" in
  /usr|/usr/local|"")
    echo "❌ Refusing to mirror system prefix: $UV_PREFIX"
    exit 1
    ;;
esac

# Expect a CPython-like layout (bin/python and lib/pythonX.Y)
if [ ! -x "$UV_PREFIX/bin/python" ] && [ ! -x "$UV_PREFIX/bin/python3" ]; then
  echo "❌ $UV_PREFIX does not contain a Python binary under bin/"
  exit 1
fi
if [ ! -d "$UV_PREFIX/lib/python${SERIES}" ]; then
  echo "❌ $UV_PREFIX missing expected lib/python${SERIES} tree; refusing to mirror"
  exit 1
fi

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
chmod -R 0777 "${ENV_PATH}"

# Optional: maintain a series convenience symlink (e.g., py3.12 -> py3.12.11)
SERIES="${PY_VERSION%.*}"                              # 3.12
ln -sfn "${ENV_PATH}" "${VENV_ROOT}/py${SERIES}"

# ---- stable symlink & convenience shims ----
ln -snf "$ENV_PATH" "$STABLE_PY_LINK"
ln -sfn "${STABLE_PY_LINK}/bin/python" /usr/local/bin/python || true
ln -sfn "${STABLE_PY_LINK}/bin/pip"    /usr/local/bin/pip    || true
ln -sfn "${STABLE_PY_LINK}/bin/python" /usr/local/bin/python3 || true
ln -sfn "${STABLE_PY_LINK}/bin/pip"    /usr/local/bin/pip3    || true

# refresh command lookup cache in case this shell keeps running more commands
hash -r || true

# ---- system-wide shell defaults (last install wins) ----
cat >"$PROFILE_FILE" <<'EOF'
# Stable Python (managed by python-setup.sh)
export PYENV_ROOT="/opt/pyenv"
export PY_STABLE="/opt/python"
export VENV_ROOT="/opt/venvs"
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

# Ensure uv is on PATH (once) — supports both layouts: /usr/local/uv and /usr/local/uv/bin
case ":$PATH:" in
  *":/usr/local/uv/bin:"*|*":/usr/local/uv:"*) ;;
  *) PATH="/usr/local/uv/bin:/usr/local/uv:${PATH}" ;;
esac

export PATH
EOF
chmod 0644 "$PROFILE_FILE"

# ---- dynamic series auto-activation & ACTIVE_VER (for new shells) ----
cat >"$PROFILE_VER_FILE" <<'EOF'
# Auto-activate the series venv that matches /opt/python (managed by python-setup.sh)

# 1) Resolve active version from the stable symlink
if [ -x /opt/python/bin/python ]; then
  PY_STABLE_VERSION="$(/opt/python/bin/python -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null || true)"
else
  PY_STABLE_VERSION=""
fi
export PY_STABLE_VERSION

# 2) Compute the series (X.Y) from PY_STABLE_VERSION (POSIX-safe)
# Examples: 3.12.11 -> 3.12 ; 3.12 -> 3.12 ; 3 -> ""
case "$PY_STABLE_VERSION" in
  *.*) PY_SERIES="${PY_STABLE_VERSION%.*}" ;;
  *)   PY_SERIES="" ;;
esac
export PY_SERIES

# 3) Choose the series venv dir if available, else fall back to /opt/python
VENV_SERIES_DIR=""
if [ -n "$PY_SERIES" ] && [ -d "/opt/venvs/py${PY_SERIES}/bin" ]; then
  VENV_SERIES_DIR="/opt/venvs/py${PY_SERIES}"
elif [ -x /opt/python/bin/python ]; then
  VENV_SERIES_DIR="/opt/python"
fi
export VENV_SERIES_DIR

# 4) Put the chosen interpreter FIRST on PATH (exactly once)
#    Strip any other /opt/venvs/py*/bin entries to avoid confusion.
if [ -n "$VENV_SERIES_DIR" ] && [ -d "${VENV_SERIES_DIR}/bin" ]; then
  CLEAN_PATH="$(printf '%s' "$PATH" \
    | awk -v RS=: -v ORS=: '!/^[[:space:]]*$/{print}' \
    | sed -E 's#(^|:)/opt/venvs/py[0-9]+\.[0-9]+(\.[0-9]+)?/bin(:|$)#\1#g; s#::#:#g; s#^:|:$##g')"

  case ":$CLEAN_PATH:" in
    *":${VENV_SERIES_DIR}/bin:"*) PATH="$CLEAN_PATH" ;;
    *) PATH="${VENV_SERIES_DIR}/bin:${CLEAN_PATH}" ;;
  esac
  export PATH
fi

# ---- python_setup_info helper ----
alias python-setup-info='python_setup_info'

python_setup_info() {
  set -o pipefail
  _ok()  { printf "✅ %s\n" "$*"; }
  _hdr() { printf "\n\033[1m%s\033[0m\n" "$*"; }

  local PY_STABLE="${PY_STABLE:-/opt/python}"
  local PYENV_ROOT="${PYENV_ROOT:-/opt/pyenv}"
  local VENV_ROOT="${VENV_ROOT:-/opt/venvs}"
  local PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}"
  local BIN_PY="$PY_STABLE/bin/python"

  _hdr "Python setup summary"
  if [ -x "$BIN_PY" ]; then
    _ok "Python: $("$BIN_PY" -V 2>&1)"
    _ok "Location: $BIN_PY"
  else
    printf "❌ No stable python found at %s\n" "$BIN_PY"
  fi

  _hdr "Paths and environment"
  printf "PY_STABLE=%s\n" "$PY_STABLE"
  printf "PYENV_ROOT=%s\n" "$PYENV_ROOT"
  printf "VENV_ROOT=%s\n" "$VENV_ROOT"
  printf "PIP_CACHE_DIR=%s\n" "$PIP_CACHE_DIR"

  _hdr "PATH head"
  printf "%s\n" "$(printf '%s' "$PATH" | awk -F: '{print $1}')"

  _hdr "Version info"
  [ -x "$BIN_PY" ] && "$BIN_PY" - <<'PY'
import sys, os
print("sys.executable:", sys.executable)
print("sys.version:", sys.version.split()[0])
print("site:", os.__file__)
PY
}
EOF
chmod 0644 "$PROFILE_VER_FILE"

ensure_env() {
  key="$1"; val="$2"
  if grep -qE "^${key}=" /etc/environment 2>/dev/null; then
    sed -i -E "s|^${key}=.*$|${key}=${val}|" /etc/environment
  else
    echo "${key}=${val}" >> /etc/environment
  fi
}

ensure_env PYENV_ROOT                    /opt/pyenv
ensure_env PY_STABLE                     /opt/python
ensure_env VENV_ROOT                     /opt/venvs
ensure_env PIP_CACHE_DIR                 /opt/pip-cache
ensure_env PIP_DISABLE_PIP_VERSION_CHECK 1
ensure_env PYTHONUNBUFFERED              1

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
echo "  . /etc/profile.d/53-python.sh && . /etc/profile.d/54-python-version.sh"
echo "  which python && python -V"
echo "  echo \"PY_STABLE_VERSION=\$PY_STABLE_VERSION  PY_SERIES=\$PY_SERIES  VENV_SERIES_DIR=\$VENV_SERIES_DIR\""
