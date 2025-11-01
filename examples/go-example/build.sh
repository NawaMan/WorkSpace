#!/usr/bin/env bash
set -euo pipefail

# Simple build script for treemoji (now at repo root)
# Use environment variables to cross-compile:
#   - GOOS   : target OS (linux, darwin, windows, freebsd, etc.)
#   - GOARCH : target architecture (amd64, arm64, 386, riscv64, etc.)
#   - GOFLAGS: extra flags passed to `go build` (optional)
#
# Examples:
#   # Build for your current platform
#   ./build.sh
#
#   # Build for Linux on amd64
#   GOOS=linux GOARCH=amd64 ./build.sh
#
#   # Build for macOS on Apple Silicon (arm64)
#   GOOS=darwin GOARCH=arm64 ./build.sh
#
#   # Build for Windows on amd64
#   GOOS=windows GOARCH=amd64 ./build.sh
#
# Show help:
#   ./build.sh -h
#   ./build.sh --help

usage() {
  cat <<'EOF'
Usage: ./build.sh [options]

Cross-compile by setting environment variables before the command:
  GOOS    Target OS (e.g., linux, darwin, windows)
  GOARCH  Target architecture (e.g., amd64, arm64)
  GOFLAGS Extra flags forwarded to `go build` (optional)

Examples:
  ./build.sh
  GOOS=linux   GOARCH=amd64 ./build.sh
  GOOS=darwin  GOARCH=arm64 ./build.sh
  GOOS=windows GOARCH=amd64 ./build.sh

Notes:
- Output binary is written to ./bin/treemoji
- When GOOS/GOARCH are not set, Go builds for the current platform.
- See all supported targets: https://golang.org/doc/install/source#environment
EOF
}

# Parse arguments for help
if [[ ${1-} == "-h" || ${1-} == "--help" ]]; then
  usage
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$ROOT_DIR/bin"
mkdir -p "$BIN_DIR"

GOFLAGS=${GOFLAGS:-}
GOOS=${GOOS:-}
GOARCH=${GOARCH:-}

# Derive effective target for display (falls back to go env when unset)
TARGET_OS=${GOOS:-$(go env GOOS)}
TARGET_ARCH=${GOARCH:-$(go env GOARCH)}

echo "Building treemoji for ${TARGET_OS}/${TARGET_ARCH}..."
cd "$ROOT_DIR"
GOFLAGS="$GOFLAGS" GOOS="$GOOS" GOARCH="$GOARCH" go build -o "$BIN_DIR/treemoji" ./cmd/treemoji

echo "Built: $BIN_DIR/treemoji"
