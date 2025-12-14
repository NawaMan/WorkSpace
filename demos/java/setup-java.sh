#!/bin/bash

# --- Root check ---
[[ "${EUID}" -eq 0 ]] || die "This script must be run as root (use sudo)."

export WS_SETUPS_DIR=/opt/workspace/setups/
export WS_JDK_VERSION=25

"$WS_SETUPS_DIR"/jdk--setup.sh $WS_JDK_VERSION
"$WS_SETUPS_DIR"/java-nb-kernel--setup.sh

echo 'class Hi { public static void main(String[] args) { System.out.println("Hi again"); }}' | jbang -

"$WS_SETUPS_DIR"/mvn--setup.sh
"$WS_SETUPS_DIR"/gradle--setup.sh
"$WS_SETUPS_DIR"/jenv--setup.sh

if [[ "$WS_HAS_VSCODE"  != false ]]; then "$WS_SETUPS_DIR"/java-code-extension--setup.sh ; fi
if [[ "$WS_HAS_VSCODE"  != false ]]; then "$WS_SETUPS_DIR"/java-nb-kernel--setup.sh      ; fi