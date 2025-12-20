#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Cross-shell PWD : Detect MSYS/Git Bash and convert to Windows path
CURRENT_PATH=$(pwd)
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # pwd -W returns C:/Users/... instead of /c/Users/...
    CURRENT_PATH="$(pwd -W)"
fi

ACTUAL=$(../../workspace.sh --verbose --dryrun --pull --variant base -- tree -C)
ACTUAL=$(printf "%s\n" "$ACTUAL" | head -n 3)

HERE="$CURRENT_PATH"
VERSION="$(cat ../../version.txt)"

EXPECT="\
ARGS:  \"--verbose\" \"--dryrun\" \"--pull\" \"--variant\" \"base\" \"--\" \"tree\" \"-C\"
Pulling image (forced): nawaman/workspace:base-${VERSION}
docker pull nawaman/workspace:base-${VERSION} \
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
