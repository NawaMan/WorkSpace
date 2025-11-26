#!/bin/bash
set -euo pipefail

DOCKERFILE=test--dockerfile

cat > $DOCKERFILE <<'EOF'
# syntax=docker/dockerfile:1.7
ARG VARIANT_TAG=container
ARG VERSION_TAG=latest
FROM nawaman/workspace:${VARIANT_TAG}-${VERSION_TAG}

# The default value is the latest LTS
ARG PY_VERSION=3.12
ARG VARIANT_TAG=container

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ENV SETUPS_DIR=/opt/workspace/setups
ENV VARIANT_TAG="${VARIANT_TAG}"
ENV WS_VARIANT_TAG="${VARIANT_TAG}"
ENV PY_VERSION="${PY_VERSION}"

ARG TEST_VALUE=Default-Test-Value
ENV TEST_VAR=$TEST_VALUE
EOF

# Basic test

rm -f $0.log
ACTUAL=$(../../workspace.sh --dockerfile $DOCKERFILE -- 'echo TEST_VAR=$TEST_VAR' 2>/dev/null)

EXPECT="TEST_VAR=Default-Test-Value"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  echo "✅ Match - the default test value"
else
  echo "❌ Differ - the default test value"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi


# BuildArg

rm -f $0.log
ACTUAL=$(../../workspace.sh --dockerfile $DOCKERFILE --build-arg TEST_VALUE=Overriden-Test-Value -- 'echo TEST_VAR=$TEST_VAR' 2> $0.log)

EXPECT="TEST_VAR=Overriden-Test-Value"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  echo "✅ Match - the overriden test value"
else
  echo "❌ Differ - the overriden test value"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi

# Validate that $0.log exists and is not empty
if [[ -s "$0.log" ]]; then
  echo "✅ Log file '$0.log' exists and is not empty -- contain the build log"
else
  echo "❌ Log file '$0.log' is missing or empty"
  exit 1
fi


# Check Silence Build

rm -f $0.log
ACTUAL=$(../../workspace.sh --dockerfile $DOCKERFILE --silence-build -- 'echo TEST_VAR=$TEST_VAR' 2> $0.log)

# Validate that $0.log exists and is empty
if [[ -e "$0.log" && ! -s "$0.log" ]]; then
    echo "✅ Log file '$0.log' exists and is empty -- no build log as the build is silence"
else
    echo "❌ Log file '$0.log' is missing or not empty -- contain the build log"
    exit 1
fi
