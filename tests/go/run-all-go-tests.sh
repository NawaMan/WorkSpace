#!/bin/bash

# Go test runner script
# Runs all Go tests in the workspace

set -e  # Exit on first failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "========================================"
echo "Running All Go Tests"
echo "========================================"
echo ""

# Run all Go tests with verbose output
echo "Running: go test -v ./..."
echo ""

cd "$WORKSPACE_ROOT"

if go test -v ./...; then
    echo ""
    echo "========================================"
    echo "✓ All Go tests passed!"
    echo "========================================"
    exit 0
else
    echo ""
    echo "========================================"
    echo "✗ Some Go tests FAILED"
    echo "========================================"
    exit 1
fi
