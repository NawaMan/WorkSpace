#!/usr/bin/env bash
# Install the IJava (Java) Jupyter kernel so BOTH:
#   1) a standalone Jupyter, and
#   2) code-server's Jupyter extension
# can see it.
#
# Inputs (flags or env):
#   --py-version <X.Y[.Z]>   -> derive VENV_DIR as /opt/venvs/pyX.Y
#   --venv-dir <path>        -> explicit venv path (takes precedence)
#   --jdk-version <version>  -> display name's JDK version (else auto-detect)
#   --ijava-version <ver>    -> IJava release tag (default: 1.3.0)
#   Env fallbacks: PY_VERSION, JDK_VERSION
#
# Auto-detection (when flags/env missing):
#   - For Python: use python3/python --version to guess X.Y, prefer /opt/venvs/pyX.Y if it exists,
#     else scan /opt/venvs/py*/ for a venv that has jupyter_client installed.
#   - For JDK: parse `java -version` (or $JAVA_HOME/bin/java -version) to get the version for display.
#
# Prereqs:
#   - JDK installed (JAVA_HOME set or java/jshell on PATH).
#   - Target venv already has Jupyter (jupyter_client present).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# ---------------- Defaults / Tunables ----------------
IJAVA_VERSION="${IJAVA_VERSION:-1.3.0}"              # default IJava tag
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-java}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-}"        # optional override
VENV_DIR="${VENV_DIR:-}"                              # may be set by flags below
WORKDIR="${WORKDIR:-/opt/ijava}"
TMPDIR="$(mktemp -d)"

# ---------------- CLI parsing ----------------
PY_VERSION_REQ=""
JDK_VERSION_OVERRIDE=""
print_usage() {
  cat <<'USAGE'
Usage: java-nb-kernel-setup.sh [options]

Options:
  --py-version X.Y[.Z]     Derive VENV_DIR as /opt/venvs/pyX.Y
  --venv-dir PATH          Explicit venv path (overrides --py-version)
  --jdk-version VERSION    JDK version string for display name (e.g. 21.0.4)
  --ijava-version VERSION  IJava release tag (default: 1.3.0)
  --help                   Show this help and exit
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --py-version)   PY_VERSION_REQ="${2:-}"; shift 2;;
    --venv-dir)     VENV_DIR="${2:-}"; shift 2;;
    --jdk-version)  JDK_VERSION_OVERRIDE="${2:-}"; shift 2;;
    --ijava-version)IJAVA_VERSION="${2:-}"; shift 2;;
    --help|-h)      print_usage; exit 0;;
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

detect_java_version_string() {
  # Prefer $JAVA_HOME/bin/java then `java`; print version like 21.0.4, empty on failure.
  local out ver=""
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    out="$("${JAVA_HOME}/bin/java" -version 2>&1 || true)"
  elif command -v java >/dev/null 2>&1; then
    out="$(java -version 2>&1 || true)"
  fi
  # First line, quoted version if present
  ver="$(printf "%s" "$out" | awk -F\" '/version/ {print $2; exit}')"
  if [ -z "$ver" ]; then
    # Fallback: grab first numeric token
    ver="$(printf "%s" "$out" | sed -n '1s/.*\([0-9][0-9.]*\).*/\1/p')"
  fi
  printf "%s" "$ver"
}

# ---------------- Python / venv resolution ----------------
# Prefer explicit flag; else PY_VERSION env; else try to infer from python --version.
if [ -z "${PY_VERSION_REQ}" ] && [ -n "${PY_VERSION:-}" ]; then
  PY_VERSION_REQ="${PY_VERSION}"
fi

# If no explicit VENV_DIR, try to derive it.
if [ -z "${VENV_DIR}" ]; then
  if [ -n "${PY_VERSION_REQ}" ] && [[ "$PY_VERSION_REQ" =~ ^([0-9]+)\.([0-9]+) ]]; then
    VENV_DIR="/opt/venvs/py${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  else
    # Try to infer X.Y from python3/python
    series="$(infer_python_series_from_cmd || true)"
    if [ -n "$series" ] && [ -d "/opt/venvs/py${series}" ]; then
      VENV_DIR="/opt/venvs/py${series}"
    fi
  fi
fi

# If still no VENV_DIR, scan for a venv that already has jupyter_client.
if [ -z "${VENV_DIR}" ]; then
  VENV_DIR="$(find_venv_with_jupyter_client || true)"
fi

# ---------------- Resolve JAVA_HOME (+ jshell) ----------------
if [ -z "${JAVA_HOME:-}" ]; then
  for f in /etc/profile.d/99-custom.sh /etc/profile.d/98-java.sh /etc/profile.d/90-java.sh; do
    [ -r "$f" ] && . "$f"
  done
fi
if [ -z "${JAVA_HOME:-}" ]; then
  CANDIDATE="$(find /opt -maxdepth 1 -type l -name 'jdk*' -exec test -x '{}/bin/jshell' \; -print -quit 2>/dev/null || true)"
  [ -n "$CANDIDATE" ] && export JAVA_HOME="$CANDIDATE"
fi
if [ -z "${JAVA_HOME:-}" ] && command -v /usr/lib/jvm/default-java/bin/jshell >/dev/null 2>&1; then
  export JAVA_HOME="/usr/lib/jvm/default-java"
fi
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME}/bin/jshell" ]; then
  cat >&2 <<'EOF'
❌ JAVA_HOME is not set or jshell is missing.
Run your JDK installer first, e.g.:
  sudo ./jdk-setup.sh 25
Then re-run this script.
EOF
  exit 1
fi

# ---------------- JDK version for display (flag/env, else auto-detect) ----------------
if [ -n "${JDK_VERSION_OVERRIDE}" ]; then
  JDK_VERSION_FULL="${JDK_VERSION_OVERRIDE}"
elif [ -n "${JDK_VERSION:-}" ]; then
  JDK_VERSION_FULL="${JDK_VERSION}"
else
  JDK_VERSION_FULL="$(detect_java_version_string || true)"
  if [ -z "$JDK_VERSION_FULL" ]; then
    cat >&2 <<'EOF'
❌ Could not determine JDK version for kernel display name.
Provide --jdk-version 21.0.4 or export JDK_VERSION=21.0.4
EOF
    exit 2
  fi
fi
JDK_MAJOR="${JDK_VERSION_FULL%%.*}"
[ -z "$JDK_MAJOR" ] && JDK_MAJOR="$JDK_VERSION_FULL"
[ -z "$KERNEL_DISPLAY_NAME" ] && KERNEL_DISPLAY_NAME="Java (JDK ${JDK_MAJOR})"

# ---------------- Basics ----------------
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl unzip ca-certificates python3
rm -rf /var/lib/apt/lists/*

# ---------------- Pick Python to run install.py (must have jupyter_client) ----------------
pick_python() {
  local c
  for c in \
    "${VENV_DIR:+${VENV_DIR}/bin/python}" \
    "$(command -v python3 || true)" \
    "$(command -v python || true)"; do
    [ -n "$c" ] || continue
    if [ -x "$c" ] && "$c" - <<'PY' >/dev/null 2>&1
import importlib.util as u
raise SystemExit(0 if u.find_spec("jupyter_client") else 1)
PY
    then
      printf "%s" "$c"
      return 0
    fi
  done
  return 1
}

if ! PYBIN="$(pick_python)"; then
  cat >&2 <<EOF
❌ Could not find a Python with 'jupyter_client' installed.
Tried:
  - \${VENV_DIR}/bin/python (${VENV_DIR:-not set or missing jupyter_client})
  - python3 / python on PATH
Fixes:
  - Pass --venv-dir /opt/venvs/pyX.Y (your Jupyter venv), or
  - Pass --py-version X.Y (uses /opt/venvs/pyX.Y), or
  - Ensure an interpreter on PATH has 'jupyter_client' installed.
EOF
  exit 1
fi

# ---------------- Fetch IJava release ----------------
mkdir -p "${WORKDIR}"
ZIP_URL="https://github.com/SpencerPark/IJava/releases/download/v${IJAVA_VERSION}/ijava-${IJAVA_VERSION}.zip"
echo "⬇️  Downloading IJava ${IJAVA_VERSION} …"
curl -fsSL "$ZIP_URL" -o "${TMPDIR}/ijava.zip"
unzip -q -o "${TMPDIR}/ijava.zip" -d "${TMPDIR}"

INSTALL_PY="$(find "${TMPDIR}" -maxdepth 2 -type f -name 'install.py' -print -quit)"
if [ -z "$INSTALL_PY" ]; then
  echo "❌ IJava archive did not contain install.py. Aborting." >&2
  exit 1
fi

# Stage into a stable location for reuse
rsync -a --delete "$(dirname "$INSTALL_PY")"/ "${WORKDIR}/"
chmod -R a+rX "${WORKDIR}"

# ---------------- Register system-wide ----------------
echo "🧩 Registering IJava kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide) …"
pushd "${WORKDIR}" >/dev/null
export JAVA_HOME PATH="${JAVA_HOME}/bin:${PATH}"
"$PYBIN" install.py --prefix "${JUPYTER_KERNEL_PREFIX}"

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
if [ ! -d "${KDIR}" ]; then
  echo "❌ Expected kernelspec directory not found at ${KDIR}" >&2
  exit 1
fi
chmod -R a+rX "${KDIR}" || true

# Update display_name and bake JAVA_HOME (ensure the right java is used)
if [ -f "${KDIR}/kernel.json" ]; then
  python3 - "$KDIR" "$KERNEL_DISPLAY_NAME" "$JAVA_HOME" <<'PY'
import json, os, sys
kdir, disp, jh = sys.argv[1], sys.argv[2], sys.argv[3]
p = os.path.join(kdir, "kernel.json")
with open(p) as f:
    data = json.load(f)
data["display_name"] = disp
env = data.get("env", {})
env.setdefault("JAVA_HOME", jh)
argv = data.get("argv", [])
if argv and argv[0] == "java":
    argv[0] = os.path.join(jh, "bin", "java")
data["env"] = env
with open(p, "w") as f:
    json.dump(data, f, indent=2)
PY
fi

# ---------------- Optionally: also register into code-server venv ----------------
if [ -n "${VENV_DIR:-}" ] && [ -x "${VENV_DIR}/bin/python" ]; then
  echo "🧩 Also registering IJava into venv: ${VENV_DIR} (sys-prefix) …"
  export JAVA_HOME PATH="${JAVA_HOME}/bin:${PATH}"
  "${VENV_DIR}/bin/python" install.py --sys-prefix || true
fi

popd >/dev/null

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
echo "✅ IJava installed at: ${KDIR}"
echo "   Display name: ${KERNEL_DISPLAY_NAME}"
echo "   JAVA_HOME:    ${JAVA_HOME}"
echo "   Python used:  ${PYBIN}"
[ -n "${VENV_DIR:-}" ] && echo "   VENV_DIR:     ${VENV_DIR}"
