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
WS_PY_VERSION=${PY_VERSION}
if [[ ! "$WS_PY_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "❌ Invalid Python version format: '$WS_PY_VERSION'"
  echo "   Expected format: X.Y or X.Y.Z (e.g., 3.11 or 3.11.6)"
  exit 1
fi


PY_SERIES="$(echo "${WS_PY_VERSION}" | cut -d. -f1-2)"

# ---- vraibles ----
WS_PYENV_ROOT="/opt/pyenv"                        # system-wide pyenv
WS_VENV_ROOT="/opt/venvs"                         # shared venvs root
WS_VENV_DIR="${WS_VENV_ROOT}/py${WS_PY_VERSION}"  # venv directory

STABLE_PY_LINK="/opt/python"                   # stable, version-agnostic symlink
PIP_CACHE_DIR="/opt/pip-cache"                 # shared pip cache
PROFILE_FILE="/etc/profile.d/53-ws-python.sh"  # profile to be run when login


# System-wide location to host UV-installed pythons (mirrored out of /root, etc.)
UV_PYTHONS_DIR="/opt/local-pythons"

export DEBIAN_FRONTEND=noninteractive


# ---- dirs & shared perms ----
mkdir -p   "$WS_PYENV_ROOT" "$WS_VENV_ROOT" "$PIP_CACHE_DIR" "$UV_PYTHONS_DIR"
chmod 0755 "$WS_PYENV_ROOT"
chmod 0755 "$UV_PYTHONS_DIR"
chmod 1777 "$WS_VENV_ROOT" "$PIP_CACHE_DIR"

# ---- install or reuse pyenv (idempotent) ----
if [ -x "${WS_PYENV_ROOT}/bin/pyenv" ]; then
  echo "ℹ️  Found existing pyenv at ${WS_PYENV_ROOT} — reusing."
else
  echo "⬇️  Installing pyenv to ${WS_PYENV_ROOT} ..."
  git clone --depth 1 https://github.com/pyenv/pyenv.git "$WS_PYENV_ROOT"
fi

# Make pyenv available in this shell
export WS_PYENV_ROOT
export PATH="$WS_PYENV_ROOT/bin:$PATH"
eval "$("$WS_PYENV_ROOT/bin/pyenv" init -)"

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
if [[ "$WS_PY_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "🔎 Installing latest patch for $WS_PY_VERSION via uv and detecting exact version ..."
  uv python install "$WS_PY_VERSION" >/dev/null
  UV_PY_BIN="$(uv python find "$WS_PY_VERSION" || true)"
  [ -n "${UV_PY_BIN}" ] || { echo "❌ uv could not find installed Python $WS_PY_VERSION"; exit 1; }
  # If we accidentally got a project venv, we’ll fix it in the guard below.
  WS_PY_VERSION="$("$UV_PY_BIN" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null || echo "$WS_PY_VERSION")"
fi

# ---- ensure prebuilt CPython $WS_PY_VERSION is available via uv ----
echo "⚡ Ensuring prebuilt CPython $WS_PY_VERSION is available ..."
_unused="$(uv python install "$WS_PY_VERSION" >/dev/null || true)"
UV_PY_BIN="$(uv python find "$WS_PY_VERSION")"
[ -n "$UV_PY_BIN" ] || { echo "❌ uv could not find installed Python $WS_PY_VERSION"; exit 1; }

# ---- GUARD: reject project venv paths (…/.venv/…) ----
if [[ "$UV_PY_BIN" =~ /(\.venv|venv|\.env)[^/]*/bin/ ]]; then
  echo "⚠️  uv returned a project venv interpreter: $UV_PY_BIN"
  echo "    Forcing a clean UV-managed interpreter..."
  uv python install "$WS_PY_VERSION" >/dev/null
  UV_PY_BIN="$(uv python find "$WS_PY_VERSION")"
  [[ ! "$UV_PY_BIN" =~ /(\.venv|venv|\.env)[^/]*/bin/ ]] || {
    echo "❌ still pointing to a venv; aborting to avoid copying a broken tree"; exit 1; }
fi

UV_PREFIX="$(dirname "$(dirname "$UV_PY_BIN")")"
PY_EXE="$UV_PREFIX/bin/python"
[ -x "$PY_EXE" ] || PY_EXE="$UV_PREFIX/bin/python3"
[ -x "$PY_EXE" ] || { echo "❌ expected python or python3 in $UV_PREFIX/bin"; exit 1; }

# ---- sanity-check that we're mirroring a real Python prefix (not /usr) ----
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
if [ ! -d "$UV_PREFIX/lib/python${PY_SERIES}" ]; then
  echo "❌ $UV_PREFIX missing expected lib/python${PY_SERIES} tree; refusing to mirror"
  exit 1
fi

# ---- COPY uv interpreter out of /root into world-readable location ----
# Mirror interpreter tree into /opt/local-pythons/$WS_PY_VERSION and link pyenv to it.
DEST_PREFIX="${UV_PYTHONS_DIR}/${WS_PY_VERSION}"
if [ -x "${DEST_PREFIX}/bin/python" ]; then
  echo "ℹ️  Using existing system Python at ${DEST_PREFIX}."
else
  echo "📦  Copying Python $WS_PY_VERSION from ${UV_PREFIX} to ${DEST_PREFIX} ..."
  mkdir -p      "${DEST_PREFIX}"
  cp    -RPp    "${UV_PREFIX}/." "$DEST_PREFIX/"
  chmod -R a+rX "${DEST_PREFIX}"
fi

# ---- register this interpreter inside pyenv (no build) ----
mkdir -p "$WS_PYENV_ROOT/versions"
ln -snf "$DEST_PREFIX" "$WS_PYENV_ROOT/versions/$WS_PY_VERSION"

PY_PREFIX="$(PYENV_ROOT="$WS_PYENV_ROOT" "$WS_PYENV_ROOT/bin/pyenv" prefix "$WS_PY_VERSION")"
[ -x "$PY_PREFIX/bin/python" ] || { echo "❌ pyenv prefix invalid"; exit 1; }

# ---- create venv at a fixed path using uv (avoid ensurepip issues) ----
# Use full patch in the directory name: /opt/venvs/py3.12.11
ENV_NAME="py${WS_PY_VERSION}"            # e.g. py3.12.11
ENV_PATH="${WS_VENV_ROOT}/${ENV_NAME}"

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

# maintain a series convenience symlink (e.g., py3.12 -> py3.12.11)
ln -sfn "${ENV_PATH}" "${WS_VENV_ROOT}/py${PY_SERIES}"

# ---- stable symlink & convenience shims ----
ln -snf "$ENV_PATH" "$STABLE_PY_LINK"
ln -sfn "${STABLE_PY_LINK}/bin/python" /usr/local/bin/python  || true
ln -sfn "${STABLE_PY_LINK}/bin/pip"    /usr/local/bin/pip     || true
ln -sfn "${STABLE_PY_LINK}/bin/python" /usr/local/bin/python3 || true
ln -sfn "${STABLE_PY_LINK}/bin/pip"    /usr/local/bin/pip3    || true

# refresh command lookup cache in case this shell keeps running more commands
hash -r || true

# ---- system-wide shell defaults (last install wins) ----
cat >"$PROFILE_FILE" <<'EOF'
# Stable Python (managed by python-setup.sh)
export WS_PYENV_ROOT="/opt/pyenv"
export WS_PY_STABLE="/opt/python"
export WS_VENV_ROOT="/opt/venvs"
export PIP_CACHE_DIR="/opt/pip-cache"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONUNBUFFERED=1

# Put /opt/python/bin first exactly once
case ":$PATH:" in
  *":${WS_PY_STABLE}/bin:"*) ;;
  *) PATH="${WS_PY_STABLE}/bin:${PATH}" ;;
esac

# Ensure pyenv shims are on PATH (once)
case ":$PATH:" in
  *":${WS_PYENV_ROOT}/bin:"*) ;;
  *) PATH="${WS_PYENV_ROOT}/bin:${PATH}" ;;
esac

# Ensure uv is on PATH (once) — supports both layouts: /usr/local/uv and /usr/local/uv/bin
case ":$PATH:" in
  *":/usr/local/uv/bin:"*|*":/usr/local/uv:"*) ;;
  *) PATH="/usr/local/uv/bin:/usr/local/uv:${PATH}" ;;
esac

source "/opt/python/bin/activate"


# Auto-activate the series venv that matches /opt/python (managed by python-setup.sh)

# 1) Resolve active version from the stable symlink
if [ -x /opt/python/bin/python ]; then
  WS_PY_VERSION="$(/opt/python/bin/python -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null || true)"
else
  WS_PY_VERSION=""
fi
export WS_PY_VERSION
export WS_VENV_DIR="/opt/venvs/py${WS_PY_VERSION}"

# 2) Compute the series (X.Y) from WS_PY_STABLE_VERSION (POSIX-safe)
# Examples: 3.12.11 -> 3.12 ; 3.12 -> 3.12 ; 3 -> ""
case "${WS_PY_VERSION}" in
  *.*.*) WS_PY_SERIES="${WS_PY_VERSION%.*}" ;;  # strip patch only
  *.*)   WS_PY_SERIES="${WS_PY_VERSION}"    ;;  # already X.Y form
  *)     WS_PY_SERIES="" ;;
esac
export WS_PY_SERIES

# 3) Choose the series venv dir if available, else fall back to /opt/python
export WS_VENV_SERIES_DIR="/opt/venvs/py${WS_PY_SERIES}"

# 4) Put the chosen interpreter FIRST on PATH (exactly once)
#    Strip any other /opt/venvs/py*/bin entries to avoid confusion.
if [ -n "$WS_VENV_SERIES_DIR" ] && [ -d "${WS_VENV_SERIES_DIR}/bin" ]; then
  CLEAN_PATH="$(printf '%s' "$PATH" \
    | awk -v RS=: -v ORS=: '!/^[[:space:]]*$/{print}' \
    | sed -E 's#(^|:)/opt/venvs/py[0-9]+\.[0-9]+(\.[0-9]+)?/bin(:|$)#\1#g; s#::#:#g; s#^:|:$##g')"

  case ":$CLEAN_PATH:" in
    *":${WS_VENV_SERIES_DIR}/bin:"*) PATH="$CLEAN_PATH" ;;
    *) PATH="${WS_VENV_SERIES_DIR}/bin:${CLEAN_PATH}" ;;
  esac
  export PATH
fi

# ---- python_setup_info helper ----
python_setup_info() {
  set -o pipefail
  _ok()  { printf "✅ %s\n" "$*"; }
  _hdr() { printf "\n\033[1m%s\033[0m\n" "$*"; }

  _hdr "Python setup summary"
  printf "WS_PYENV_ROOT=%s\n"        "$WS_PYENV_ROOT"
  printf "WS_PY_STABLE=%s\n"         "$WS_PY_STABLE"
  printf "WS_VENV_ROOT=%s\n"         "$WS_VENV_ROOT"
  printf "WS_PY_STABLE_VERSION=%s\n" "$WS_PY_STABLE_VERSION"
  printf "WS_PY_SERIES=%s\n"         "$WS_PY_SERIES"
  printf "WS_VENV_SERIES_DIR=%s\n"   "$WS_VENV_SERIES_DIR"
}

alias python-setup-info='python_setup_info'
EOF
chmod 0644 "$PROFILE_FILE"


ensure_env() {
  key="$1"; val="$2"
  if grep -qE "^${key}=" /etc/environment 2>/dev/null; then
    sed -i -E "s|^${key}=.*$|${key}=${val}|" /etc/environment
  else
    echo "${key}=${val}" >> /etc/environment
  fi
}

ensure_env WS_PYENV_ROOT                 /opt/pyenv
ensure_env PY_STABLE                     /opt/python
ensure_env WS_VENV_ROOT                  /opt/venvs
ensure_env PIP_CACHE_DIR                 /opt/pip-cache
ensure_env PIP_DISABLE_PIP_VERSION_CHECK 1
ensure_env PYTHONUNBUFFERED              1

# ---- summary ----
ACTIVE_VER="$("${STABLE_PY_LINK}/bin/python" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null || true)"
"${STABLE_PY_LINK}/bin/python" -V || true
"${STABLE_PY_LINK}/bin/pip" --version || true
echo "✅ pyenv at ${WS_PYENV_ROOT}"
echo "✅ Python ${WS_PY_VERSION} mirrored at ${DEST_PREFIX} and registered under pyenv at ${PY_PREFIX}"
echo "✅ Venv '${ENV_NAME}' at ${ENV_PATH}"
echo "✅ Stable Python symlink at ${STABLE_PY_LINK} → $(readlink -f "${STABLE_PY_LINK}")"
echo "✅ ${PROFILE_FILE} ensures /opt/python/bin to auto-activates /opt/venvs/py\${PY_SERIES}"
echo "✅ ACTIVE_VER detected now: ${ACTIVE_VER}"
echo
echo "Open a NEW shell and verify:"
echo "  source /etc/profile.d/53-ws-python.sh"
echo "  which python && python -V"
echo "  echo \"PY_STABLE_VERSION=\$PY_STABLE_VERSION  PY_SERIES=\$PY_SERIES  VENV_SERIES_DIR=\$VENV_SERIES_DIR\""
