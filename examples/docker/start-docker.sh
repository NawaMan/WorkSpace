#!/usr/bin/env bash
set -euo pipefail



# # Remove old Docker repos if any
# sudo apt-get remove -y docker-buildx-plugin || true

# # Setup required deps
# sudo apt-get update
# sudo apt-get install -y ca-certificates curl gnupg

# # Add Docker’s official GPG key
# sudo install -m 0755 -d /etc/apt/keyrings
# curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
#   | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
# sudo chmod a+r /etc/apt/keyrings/docker.gpg

# # Add Docker’s official apt repo
# echo \
#   "deb [arch=$(dpkg --print-architecture) \
#   signed-by=/etc/apt/keyrings/docker.gpg] \
#   https://download.docker.com/linux/ubuntu \
#   $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
# | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# # Install buildx plugin from Docker repo
# sudo apt-get update
# sudo apt-get install -y docker-buildx-plugin

# # Verify
# docker buildx version

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
