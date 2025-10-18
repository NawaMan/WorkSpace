#!/usr/bin/env bash
# Minimal-but-robust IJava (Java) Jupyter kernel installer.
# - Finds a Jupyter-capable venv under /opt/venvs
# - Detects JAVA_HOME or java/jshell on PATH
# - Installs IJava system-wide and (if possible) into the venv's sys-prefix
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [[ "$WS_VARIANT_TAG" == "container" ]] || [[ "$WS_VARIANT_TAG" == "notebook" ]]; then
    echo "Variant does not include VS Code (code) or CodeServer" >&2
    exit 0
fi


SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/workspace/setups/libs}
CODE_EXTENSION_LIB=${CODE_EXTENSION_LIB:-code-extension-source.sh}
source "${SETUP_LIBS_DIR}/${CODE_EXTENSION_LIB}"

install_extensions                                      \
    redhat.java                                         \
    visualstudioexptteam.intellicode-api-usage-examples \
    visualstudioexptteam.vscodeintellicode              \
    vscjava.vscode-gradle                               \
    vscjava.vscode-java-debug                           \
    vscjava.vscode-java-dependency                      \
    vscjava.vscode-java-pack                            \
    vscjava.vscode-java-test                            \
    vscjava.vscode-maven                                \
