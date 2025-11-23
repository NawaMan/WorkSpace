#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
PWD=$(pwd)

# The workspace is set to be non default
WORKSPACE=".."

ACTUAL=$(../../workspace.sh --skip-main)
ACTUAL=$(printf "%s\n" "$ACTUAL" | tail -n 1)

VERSION="$(cat ../../version.txt)"

# Notice that there is not `-rm`
EXPECT="\
"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  echo "✅ Match"
else
  echo "❌ Differ"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
