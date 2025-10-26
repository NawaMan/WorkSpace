#!/bin/bash

../../workspace.sh --variant container -- '
python3 - <<PY
import os, sys
print("CWD in container:", os.getcwd())
print("Args:", sys.argv)
for i in range(3):
    print("line", i)
PY
' \
# 2>/dev/null      # Uncomment to get only the output of the program
