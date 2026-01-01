#!/bin/bash

# Master test runner script
# Runs all test suites in the tests directory

set -e  # Exit on first failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failed=0
failed_suites=()
total_suites=0

echo "========================================"
echo "Running All Test Suites"
echo "========================================"
echo ""

# Run units tests
echo "----------------------------------------"
echo "Running Units Tests"
echo "----------------------------------------"
total_suites=$((total_suites + 1))
if ! (cd "$SCRIPT_DIR/units" && ./run-all-tests.sh); then
    failed=1
    failed_suites+=("units")
fi
echo ""

# Run Go tests
echo "----------------------------------------"
echo "Running Go Tests"
echo "----------------------------------------"
total_suites=$((total_suites + 1))
if ! (cd "$SCRIPT_DIR/go" && ./run-all-go-tests.sh); then
    failed=1
    failed_suites+=("go")
fi
echo ""

# Run basic tests
echo "----------------------------------------"
echo "Running Basic Tests"
echo "----------------------------------------"
total_suites=$((total_suites + 1))
if ! (cd "$SCRIPT_DIR/basic" && ./run-basic-tests.sh); then
    failed=1
    failed_suites+=("basic")
fi
echo ""

# Run dryrun tests
echo "----------------------------------------"
echo "Running Dryrun Tests"
echo "----------------------------------------"
total_suites=$((total_suites + 1))
if ! (cd "$SCRIPT_DIR/dryrun" && ./run-dryrun-tests.sh); then
    failed=1
    failed_suites+=("dryrun")
fi
echo ""

# Run workspace-env tests
echo "----------------------------------------"
echo "Running Workspace-Env Tests"
echo "----------------------------------------"
total_suites=$((total_suites + 1))
if ! (cd "$SCRIPT_DIR/workspace-env" && ./run-test.sh); then
    failed=1
    failed_suites+=("workspace-env")
fi
echo ""

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
num_failed=${#failed_suites[@]}

if [ $failed -eq 0 ]; then
    echo "✓ All $total_suites test suites passed!"
else
    echo "✗ $num_failed out of $total_suites test suites FAILED."
    echo "Failed suites:"
    for suite in "${failed_suites[@]}"; do
        echo "  - $suite"
    done
fi
echo ""

exit $failed
