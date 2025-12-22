#!/bin/bash
set -euo pipefail

source ../common--source.sh

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Cross-shell PWD : Detect MSYS/Git Bash and convert to Windows path
CURRENT_PATH=$(pwd)
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # pwd -W returns C:/Users/... instead of /c/Users/...
    CURRENT_PATH="$(pwd -W)"
fi

# The workspace is set to be non default
WORKSPACE=".."

ACTUAL=$(../../workspace.sh --skip-main)
ACTUAL=$(printf "%s\n" "$ACTUAL" | tail -n 1)

VERSION="$(cat ../../version.txt)"

# Notice that there is not `-rm`
EXPECT="\
"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  print_test_result "true" "$0" "1" "Skip main output matches expected"
else
  print_test_result "false" "$0" "1" "Skip main output matches expected"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
