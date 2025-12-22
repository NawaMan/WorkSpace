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

ACTUAL=$(../../workspace.sh --help | head)

HERE="$PWD"
VERSION="$(cat ../../version.txt)"

EXPECT="\
workspace.sh — launch a Docker-based development workspace

USAGE:
  workspace.sh [options] [--] [command ...]
  workspace.sh --help

COMMAND:
  ws-version             Print the workspace.sh version.

GENERAL:"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  print_test_result "true" "$0" "1" "Help output matches expected"
else
  print_test_result "false" "$0" "1" "Help output matches expected"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
