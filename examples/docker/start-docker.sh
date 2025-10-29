#!/usr/bin/env bash
set -euo pipefail


SERVER_PORT=8080


DIND_NAME="${WS_CONTAINER_NAME}-${WS_HOST_PORT}-dind"
socat TCP-LISTEN:${SERVER_PORT},reuseaddr,fork TCP:${DIND_NAME}:8080 &
SOCAT_PID=$!

cleanup() {
  echo "Stopping socat..."
  if [ -n "${SOCAT_PID:-}" ] && kill -0 "$SOCAT_PID" 2>/dev/null; then
    kill "$SOCAT_PID" 2>/dev/null || true
    wait "$SOCAT_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

DOCKER_BUILDKIT=1 docker build -t http-server .
docker run -p ${SERVER_PORT}:${SERVER_PORT} http-server
