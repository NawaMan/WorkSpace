#!/bin/bash

failed=0
failed_tests=()
total_tests=0

for f in test*.sh ; do
    echo "==============================================================================="
    echo "Running: $f"
    echo "==============================================================================="
    total_tests=$((total_tests + 1))

    if ! ./"$f"; then
        failed=1
        failed_tests+=("$f")
    fi
    echo ""
done

num_failed=${#failed_tests[@]}

echo "==============================================================================="
echo "FINAL SUMMARY"
echo "==============================================================================="
if [ $failed -eq 0 ]; then
    echo "✅ All $total_tests tests passed."
else
    echo "❌ $num_failed out of $total_tests tests FAILED."
    echo ""
    echo "Failed tests:"
    for t in "${failed_tests[@]}"; do
        echo "  - $t"
    done
fi
echo "==============================================================================="

exit $failed
