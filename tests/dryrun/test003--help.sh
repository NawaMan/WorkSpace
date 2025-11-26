#!/bin/bash
set -euo pipefail

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
PWD=$(pwd)

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
