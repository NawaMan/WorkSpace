#!/usr/bin/env bash
set -euo pipefail

#== ENVIRONMENTAL VARIABLES ==
DOCKER_USER_SCRIPT="${DOCKER_USER_SCRIPT:-}"
DOCKER_PAT_SCRIPT="${DOCKER_PAT_SCRIPT:-}"

# --- Setting ---
IMAGE_NAME="nawaman/workspace"
PLATFORMS="linux/amd64,linux/arm64"
VERSION_FILE="version.txt"

# --- Helpers ---
log() { printf "\033[1;34m[info]\033[0m %s\n" "$1";    }
err() { printf "\033[1;31m[err]\033[0m %s\n" "$1" >&2; }
die() { err "$1"; exit 1; }

# --- Resolve version ---
VERSION_TAG=""
if [[ -f "${VERSION_FILE}" ]]; then
  VERSION_TAG="$(tr -d ' \t\n\r' < "${VERSION_FILE}")"
  [[ -z "${VERSION_TAG}" ]] && die "Version file '${VERSION_FILE}' is empty."
else
  die "No --version provided and '${VERSION_FILE}' not found."
fi

build_variant() {
  VARIANT="${1:-container}"
  TAGS_ARG=()
  CONTEXT_DIR="workspace/${VARIANT}"
  DOCKER_FILE="${CONTEXT_DIR}/Dockerfile"

  TAGS_ARG+=( -t "${IMAGE_NAME}:${VARIANT}-${VERSION_TAG}" )
  TAGS_ARG+=( -t "${IMAGE_NAME}:${VARIANT}-latest"         )
  if [[ "$VARIANT" == "container" ]]; then
    TAGS_ARG+=( -t "${IMAGE_NAME}:${VERSION_TAG}" )
    TAGS_ARG+=( -t "${IMAGE_NAME}:latest"         )
  fi

  # Pretty-print tags
  printf -v TAGS_STR '%s ' "${TAGS_ARG[@]}"
  TAGS_STR="${TAGS_STR//-t /}"

  log "Image:      ${IMAGE_NAME}"
  log "Variant:    ${VARIANT}"
  log "Version:    ${VERSION_TAG}"
  log "Context:    ${CONTEXT_DIR}"
  log "Dockerfile: ${DOCKER_FILE}"
  log "Tags:       ${TAGS_STR}"

  # --- Sanity checks ---
  [[ -d "${CONTEXT_DIR}" ]] || die "Context dir not found: ${CONTEXT_DIR}"
  [[ -f "${DOCKER_FILE}" ]] || die "Dockerfile not found: ${DOCKER_FILE}"

  if [[ "${PUSH}" == "true" ]]; then
    # Multi-arch + push using buildx docker-container driver
    log "Setting up buildx (driver: docker-container; multi-arch: ${PLATFORMS})"
    docker buildx create --use --name ci_builder >/dev/null 2>&1 || docker buildx use ci_builder
    docker buildx inspect --bootstrap >/dev/null

    log "Building with buildx (push)"
    docker buildx build \
      --no-cache \
      --platform "${PLATFORMS}" \
      -f "${DOCKER_FILE}" \
      "${TAGS_ARG[@]}" \
      "${CONTEXT_DIR}" \
      --push
  else
    # Local dev/test: plain docker build (so FROM sees locally built base)
    log "Local build (plain 'docker build')"
    docker build \
      -f "${DOCKER_FILE}" \
      "${TAGS_ARG[@]}" \
      "${CONTEXT_DIR}"
  fi

  log "Done."
  echo
}

usage() {
  cat <<EOF
Usage: ./build.sh [--push]
Examples
  ./build.sh          # local build (plain docker build)
  ./build.sh --push   # multi-arch buildx build and push
EOF
}

# --- Parse parameters ---
PUSH="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)    PUSH="true";                      shift  ;;
    -h|--help) usage;                            exit 0 ;;
    *)         echo "Unknown option: $1"; usage; exit 2 ;;
  esac
done

# --- Docker login (non-interactive) ---
if [[ "${PUSH}" == "true" ]]; then
  if [[ -z "${DOCKERHUB_USERNAME:-}" || -z "${DOCKERHUB_TOKEN:-}" ]]; then
    echo "❌ Username or password not set."
    echo "   Make sure both DOCKERHUB_USERNAME and DOCKERHUB_TOKEN are set."
    exit 3
  fi
  log "Logging in to Docker Hub as ${DOCKERHUB_USERNAME}"
  if ! echo "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USERNAME}" --password-stdin; then
    echo "❌ Docker login failed"
    exit 4
  fi
fi

build_variant container
# build_variant notebook
# build_variant codeserver
