#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
PWD=$(pwd)

ACTUAL=$(../../workspace.sh --verbose --dryrun --pull --variant container -- tree -C)
ACTUAL=$(printf "%s\n" "$ACTUAL" | head -n 3)

HERE="$PWD"
VERSION="$(cat ../../version.txt)"

EXPECT="\
ARGS:  \"--verbose\" \"--dryrun\" \"--pull\" \"--variant\" \"container\" \"--\" \"tree\" \"-C\"
Pulling image (forced): nawaman/workspace:container-${VERSION}
docker pull nawaman/workspace:container-${VERSION} \
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
