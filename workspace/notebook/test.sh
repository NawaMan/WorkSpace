#!/bin/bash
set -euo pipefail

# Define cleanup
cleanup() {
  rm -f in-container.txt in-host.txt
}
trap cleanup EXIT  # run cleanup on script exit (success or error)

cleanup
DATE=$(date)
echo $DATE > in-host.txt
./run.sh -- echo $DATE '>' in-container.txt

if diff -u in-container.txt in-host.txt; then
  echo "✅ Files match"
else
  echo "❌ Files differ"
  exit 1
fi