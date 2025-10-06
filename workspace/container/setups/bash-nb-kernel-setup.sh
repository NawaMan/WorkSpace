#!/usr/bin/env bash
# bash-nb-kernel-setup.sh
#
# Install the Bash Jupyter kernel so BOTH:
#   1) a standalone Jupyter, and
#   2) code-server's Jupyter extension
# can see it.
#
# Inputs (flags or env):
#   --py-version <X.Y[.Z]>  -> derive VENV_DIR as /opt/venvs/pyX.Y
#   --venv-dir <path>       -> explicit venv path (takes precedence)
#   --prefix <path>         -> system-wide kernelspec prefix (default: /usr/local)
#   --kernel-name <name>    -> kernelspec dir name (default: bash)
#   --kernel-display <name> -> display name override (default: Bash)
#   Env fallbacks: PY_VERSION
#
# Auto-detection (when flags/env missing):
#   - For Python: use python3/python --version to guess X.Y, prefer /opt/venvs/pyX.Y if it exists,
#     else scan /opt/venvs/py*/ for a venv that has jupyter_client installed.
#
# Prereqs:
#   - Target Python can install packages with pip.
#   - jupyter_client should be present (this script will ensure it if needed).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-bash}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Bash}"
VENV_DIR="${VENV_DIR:-}"  # may be set by flags
TMPDIR="$(mktemp -d)"

# ---------------- CLI parsing ----------------
PY_VERSION_REQ=""
print_usage() {
  cat <<'USAGE'
Usage: bash-nb-kernel-setup.sh [options]

Options:
  --py-version X.Y[.Z]   Derive VENV_DIR as /opt/venvs/pyX.Y
  --venv-dir PATH        Explicit venv path (overrides --py-version)
  --prefix PATH          System-wide kernelspec prefix (default: /usr/local)
  --kernel-name NAME     Kernelspec directory name (default: bash)
  --kernel-display NAME  Display name override (default: Bash)
  --help                 Show this help and exit
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --py-version)     PY_VERSION_REQ="${2:-}"; shift 2;;
    --venv-dir)       VENV_DIR="${2:-}"; shift 2;;
    --prefix)         JUPYTER_KERNEL_PREFIX="${2:-}"; shift 2;;
    --kernel-name)    KERNEL_NAME="${2:-}"; shift 2;;
    --kernel-display) KERNEL_DISPLAY_NAME="${2:-}"; shift 2;;
    --help|-h)        print_usage; exit 0;;
    *) echo "❌ Unknown option: $1" >&2; print_usage; exit 2;;
  esac
done

# ---------------- Helpers ----------------
infer_python_series_from_cmd() {
  # Print X.Y inferred from python3/python; empty on failure.
  local series=""
  if command -v python3 >/dev/null 2>&1; then
    series="$(python3 - <<'PY' 2>/dev/null || true
import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")
PY
)"
  fi
  if [ -z "$series" ] && command -v python >/dev/null 2>&1; then
    series="$(python - <<'PY' 2>/dev/null || true
import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")
PY
)"
  fi
  printf "%s" "$series"
}

find_venv_with_jupyter_client() {
  # Print venv dir whose python has jupyter_client; empty if none.
  local p
  for p in /opt/venvs/py*/bin/python; do
    [ -x "$p" ] || continue
    if "$p" - <<'PY' >/dev/null 2>&1
import importlib.util as u
raise SystemExit(0 if u.find_spec("jupyter_client") else 1)
PY
    then
      printf "%s\n" "${p%/bin/python}"
      return 0
    fi
  done
  return 1
}

pick_python() {
  # Prefer the venv; else python3/python that has pip.
  local c
  for c in \
    "${VENV_DIR:+${VENV_DIR}/bin/python}" \
    "$(command -v python3 || true)" \
    "$(command -v python || true)"; do
    [ -n "$c" ] || continue
    if [ -x "$c" ]; then
      printf "%s" "$c"
      return 0
    fi
  done
  return 1
}

has_module() {
  local pybin="$1" mod="$2"
  "$pybin" - <<PY >/dev/null 2>&1
import importlib.util as u; import sys
sys.exit(0 if u.find_spec("${mod}") else 1)
PY
}

# ---------------- Python / venv resolution ----------------
if [ -z "${PY_VERSION_REQ}" ] && [ -n "${PY_VERSION:-}" ]; then
  PY_VERSION_REQ="${PY_VERSION}"
fi

if [ -z "${VENV_DIR}" ]; then
  if [ -n "${PY_VERSION_REQ}" ] && [[ "$PY_VERSION_REQ" =~ ^([0-9]+)\.([0-9]+) ]]; then
    VENV_DIR="/opt/venvs/py${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  else
    series="$(infer_python_series_from_cmd || true)"
    if [ -n "$series" ] && [ -d "/opt/venvs/py${series}" ]; then
      VENV_DIR="/opt/venvs/py${series}"
    fi
  fi
fi

if [ -z "${VENV_DIR}" ]; then
  VENV_DIR="$(find_venv_with_jupyter_client || true)"
fi

# ---------------- Pick Python & ensure deps ----------------
if ! PYBIN="$(pick_python)"; then
  cat >&2 <<EOF
❌ Could not find a Python interpreter.
Tried:
  - \${VENV_DIR}/bin/python (${VENV_DIR:-not set})
  - python3 / python on PATH
EOF
  exit 1
fi

# If VENV_DIR exists, prefer its python explicitly.
if [ -n "${VENV_DIR:-}" ] && [ -x "${VENV_DIR}/bin/python" ]; then
  PYBIN="${VENV_DIR}/bin/python"
fi

# Ensure pip + needed packages in the chosen Python
"$PYBIN" -m pip install -U pip setuptools wheel >/dev/null
"$PYBIN" -m pip install -U bash_kernel jupyter_client >/dev/null

# ---------------- Register system-wide ----------------
echo "🧩 Registering Bash kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)…"
"$PYBIN" -m bash_kernel.install --prefix "${JUPYTER_KERNEL_PREFIX}"

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
# If the module's default name isn't what we want, detect created dir
if [ ! -d "${KDIR}" ]; then
  # Find any bash kernelspec just created
  CANDIDATE="$(jupyter --paths --json 2>/dev/null | sed -n 's/.*"data":\s*\["\([^"]*\)".*/\1/p' | head -n1)"
  if [ -z "$CANDIDATE" ]; then
    # Generic fallback
    CANDIDATE="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels"
  fi
  # Look for a dir containing kernel.json with "bash_kernel" argv
  if [ -d "$CANDIDATE/kernels" ]; then
    for d in "$CANDIDATE/kernels"/*; do
      [ -f "$d/kernel.json" ] || continue
      if grep -q 'bash_kernel' "$d/kernel.json"; then
        KDIR="$d"
        break
      fi
    done
  fi
fi

if [ ! -d "${KDIR}" ]; then
  echo "❌ Expected kernelspec directory not found (looked under ${JUPYTER_KERNEL_PREFIX})." >&2
  exit 1
fi
chmod -R a+rX "${KDIR}" || true

# Update display_name and (optionally) rename kernelspec dir if custom name requested
if [ -f "${KDIR}/kernel.json" ]; then
  python3 - "$KDIR" "$KERNEL_DISPLAY_NAME" "$KERNEL_NAME" <<'PY'
import json, os, sys, shutil
kdir, disp, kname = sys.argv[1], sys.argv[2], sys.argv[3]
p = os.path.join(kdir, "kernel.json")
with open(p) as f:
    data = json.load(f)
data["display_name"] = disp or data.get("display_name", "Bash")
with open(p, "w") as f:
    json.dump(data, f, indent=2)
# If the directory basename isn't the requested kernelspec name, rename it.
parent, base = os.path.dirname(kdir), os.path.basename(kdir)
if kname and base != kname:
    target = os.path.join(parent, kname)
    if not os.path.exists(target):
        shutil.move(kdir, target)
        print(target)
    else:
        print(kdir)
else:
    print(kdir)
PY
  # Capture possibly updated path
  KDIR="$(tail -n1 <<<"$(true)")"  # no-op placeholder to avoid set -e pipefail breaking; path already echoed above if needed
fi

# ---------------- Also register into the venv (sys-prefix), if available ----------------
if [ -n "${VENV_DIR:-}" ] && [ -x "${VENV_DIR}/bin/python" ]; then
  echo "🧩 Also registering Bash kernel into venv: ${VENV_DIR} (sys-prefix)…"
  "${VENV_DIR}/bin/python" -m bash_kernel.install --sys-prefix || true
fi

# ---------------- Verification ----------------
echo
echo "🔎 Kernels (system):"
"$PYBIN" -m jupyter kernelspec list || true
if [ -n "${VENV_DIR:-}" ] && [ -x "${VENV_DIR}/bin/python" ]; then
  echo
  echo "🔎 Kernels (venv):"
  "${VENV_DIR}/bin/python" -m jupyter kernelspec list || true
fi

echo
echo "✅ Bash kernel installed."
echo "   System kernelspec: ${KDIR}"
echo "   Display name:      ${KERNEL_DISPLAY_NAME}"
echo "   Python used:       ${PYBIN}"
[ -n "${VENV_DIR:-}" ] && echo "   VENV_DIR:          ${VENV_DIR}"
