#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

# ===== Must be root (we edit files in /opt) =====
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# ===== Config (override via env if desired) =====
LOMBOK_URL="${LOMBOK_URL:-https://projectlombok.org/downloads/lombok.jar}"  # assumed reachable
SHIM_BIN="${SHIM_BIN:-/usr/local/bin/eclipse}"                               # your system shim

# ===== Locate Eclipse install =====
resolve_eclipse_home() {
  local home=""
  # 1) Explicit env
  if [[ -n "${ECLIPSE_HOME:-}" && -x "${ECLIPSE_HOME}/eclipse" ]]; then
    echo "${ECLIPSE_HOME}"
    return 0
  fi
  # 2) Parse shim for STARTER_FILE
  if [[ -r "${SHIM_BIN}" ]]; then
    # Expect a line: exec "/opt/eclipse-.../eclipse-starter.sh" "$@"
    local starter
    starter="$(sed -n 's/^exec "\([^"]*eclipse-starter\.sh\)".*$/\1/p' "${SHIM_BIN}" | head -n1 || true)"
    if [[ -n "${starter}" && -r "${starter}" ]]; then
      echo "$(dirname "${starter}")"
      return 0
    fi
  fi
  # 3) Fall back to newest /opt/eclipse-* directory that contains the binary
  local cand
  for cand in $(ls -1d /opt/eclipse-* 2>/dev/null | sort -r); do
    if [[ -x "${cand}/eclipse" ]]; then
      echo "${cand}"
      return 0
    fi
  done
  return 1
}

ECLIPSE_HOME="$(resolve_eclipse_home)" || {
  echo "Could not determine Eclipse install directory." >&2
  echo "Set ECLIPSE_HOME to your install (e.g. /opt/eclipse-java-2025-09) and re-run." >&2
  exit 1
}

ECLIPSE_BIN="${ECLIPSE_HOME}/eclipse"
ECLIPSE_INI="${ECLIPSE_HOME}/eclipse.ini"
LOMBOK_DIR="${ECLIPSE_HOME}"
LOMBOK_JAR="${LOMBOK_DIR}/lombok.jar"

echo "• Eclipse home:     ${ECLIPSE_HOME}"
echo "• eclipse.ini:      ${ECLIPSE_INI}"
echo "• Lombok jar target:${LOMBOK_JAR}"
echo

# ===== Pre-flight checks =====
[[ -x "${ECLIPSE_BIN}" ]] || { echo "Eclipse binary not found at ${ECLIPSE_BIN}"; exit 1; }
[[ -f "${ECLIPSE_INI}" ]] || { echo "eclipse.ini not found at ${ECLIPSE_INI}"; exit 1; }

# ===== Fetch Lombok =====
mkdir -p "${LOMBOK_DIR}"
echo "Downloading Lombok from: ${LOMBOK_URL}"
wget -O "${LOMBOK_JAR}.tmp" "${LOMBOK_URL}"
mv -f "${LOMBOK_JAR}.tmp" "${LOMBOK_JAR}"

# ===== Patch eclipse.ini (idempotent) =====
# We must ensure a line:   -javaagent:/abs/path/to/lombok.jar
# It should appear BEFORE the first '-vmargs' line.

ABS_LOMBOK_JAR="${LOMBOK_JAR}"  # already absolute
JAVAAGENT_LINE="-javaagent:${ABS_LOMBOK_JAR}"

if grep -Fq -- "${JAVAAGENT_LINE}" "${ECLIPSE_INI}"; then
  echo "eclipse.ini already contains Lombok javaagent; skipping edit."
else
  echo "Patching eclipse.ini to add Lombok javaagent..."
  # Insert before first -vmargs; if -vmargs not found, append to end.
  if grep -qE '^[[:space:]]*-vmargs[[:space:]]*$' "${ECLIPSE_INI}"; then
    awk -v agent="${JAVAAGENT_LINE}" '
      BEGIN { inserted=0 }
      /^[[:space:]]*-vmargs[[:space:]]*$/ && !inserted {
        print agent
        inserted=1
      }
      { print }
      END {
        if (!inserted) {
          print agent
        }
      }
    ' "${ECLIPSE_INI}" > "${ECLIPSE_INI}.patched"
  else
    # No -vmargs; just append with a newline
    cp "${ECLIPSE_INI}" "${ECLIPSE_INI}.patched"
    printf "\n%s\n" "${JAVAAGENT_LINE}" >> "${ECLIPSE_INI}.patched"
  fi

  mv -f "${ECLIPSE_INI}.patched" "${ECLIPSE_INI}"
fi

# ===== Permissions: keep system-wide read-only stance =====
chown -R root:root "${LOMBOK_DIR}" "${ECLIPSE_INI}"
chmod -R a+rX "${LOMBOK_DIR}"
chmod a+r "${ECLIPSE_INI}"

echo
echo "✅ Lombok installed at: ${LOMBOK_JAR}"
echo "🧩 eclipse.ini updated with: ${JAVAAGENT_LINE}"
echo "▶ Start Eclipse (system-wide starter/shim will keep working):"
echo "   $ ${SHIM_BIN##*/}    # or run ${ECLIPSE_BIN}"
echo
echo "ℹ️  If you switch Eclipse versions later, re-run this script (it patches that version's eclipse.ini)."
