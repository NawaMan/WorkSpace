#!/usr/bin/env bash
set -euo pipefail

#== ENVIRONMENTAL VARIABLES ==
DOCKER_USER_SCRIPT="${DOCKER_USER_SCRIPT:-}"
DOCKER_PAT_SCRIPT="${DOCKER_PAT_SCRIPT:-}"

# --- Setting ---
IMAGE_NAME="nawaman/workspace"
PLATFORMS="linux/amd64,linux/arm64"
VERSION_FILE="version.txt"

# All known variants
ALL_VARIANTS=(
  container
  ide-notebook
  ide-codeserver
  desktop-xfce
  desktop-kde
  desktop-lxqt
)

# --- Helpers ---
log() { printf "\033[1;34m[info]\033[0m %s\n" "$1";    }
err() { printf "\033[1;31m[err]\033[0m %s\n" "$1" >&2; }
die() { err "$1"; exit 1; }

is_valid_variant() {
  local v="$1"
  for known in "${ALL_VARIANTS[@]}"; do
    if [[ "$known" == "$v" ]]; then
      return 0
    fi
  done
  return 1
}

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
  if [[ "$VARIANT" == "container" ]]; then
    TAGS_ARG+=( -t "${IMAGE_NAME}:${VERSION_TAG}" )
  fi

  if [[ ! "$VERSION_TAG" =~ --rc([0-9]+)?$ ]]; then
    TAGS_ARG+=( -t "${IMAGE_NAME}:${VARIANT}-latest" )
    if [[ "$VARIANT" == "container" ]]; then
      TAGS_ARG+=( -t "${IMAGE_NAME}:latest" )
    fi
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
  log "No cache:   ${NO_CACHE}"

  # --- Sanity checks ---
  [[ -d "${CONTEXT_DIR}" ]] || die "Context dir not found: ${CONTEXT_DIR}"
  [[ -f "${DOCKER_FILE}" ]] || die "Dockerfile not found: ${DOCKER_FILE}"

  # Optional args
  NO_CACHE_ARG=()
  if [[ "${NO_CACHE}" == "true" ]]; then
    NO_CACHE_ARG+=( --no-cache )
  fi

  if [[ "${PUSH}" == "true" ]]; then
    # Multi-arch + push using buildx docker-container driver
    log "Setting up buildx (driver: docker-container; multi-arch: ${PLATFORMS})"
    docker buildx create --use --name ci_builder >/dev/null 2>&1 || docker buildx use ci_builder
    docker buildx inspect --bootstrap >/dev/null

    log "Building with buildx (push)"
    docker buildx build --no-cache \
      "${NO_CACHE_ARG[@]}" \
      --platform "${PLATFORMS}" \
      -f "${DOCKER_FILE}" \
      --build-arg "VERSION_TAG=${VERSION_TAG}" \
      "${TAGS_ARG[@]}" \
      "${CONTEXT_DIR}" \
      --push
  else
    # Local dev/test: plain docker build (so FROM sees locally built base)
    log "Local build (plain 'docker build')"
    export DOCKER_BUILDKIT=1
    docker build --no-cache \
      "${NO_CACHE_ARG[@]}" \
      -f "${DOCKER_FILE}" \
      --build-arg "VERSION_TAG=${VERSION_TAG}" \
      "${TAGS_ARG[@]}" \
      "${CONTEXT_DIR}"
  fi

  log "Done."
  echo
}

usage() {
  cat <<EOF
Usage: ./build.sh [--push] [--no-cache] [variant ...]
Options:
  --push          Build and push using buildx (multi-arch)
  --no-cache      Build without using cache
  -h, --help      Show this help

Variants (if none provided, all are built):
  container
  ide-notebook
  ide-codeserver
  desktop-xfce
  desktop-kde
  desktop-lxqt

Examples:
  ./build.sh                         # local build of all variants
  ./build.sh container               # build only 'container'
  ./build.sh ide-notebook desktop-xfce
                                     # build two specific variants
  ./build.sh --push container        # push only 'container' variant
  ./build.sh --push --no-cache desktop-kde
                                     # build+push KDE without cache
EOF
}

# --- Parse parameters ---
PUSH="false"
NO_CACHE="false"
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      PUSH="true"
      shift
      ;;
    --no-cache)
      NO_CACHE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# Restore positional args (variants)
set -- "${POSITIONAL[@]}"

# Determine which variants to build
if [[ $# -gt 0 ]]; then
  VARIANTS_TO_BUILD=("$@")
else
  VARIANTS_TO_BUILD=("${ALL_VARIANTS[@]}")
fi

# Validate variants
for v in "${VARIANTS_TO_BUILD[@]}"; do
  if ! is_valid_variant "$v"; then
    err "Unknown variant: '$v'"
    echo
    usage
    exit 2
  fi
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

# --- Build requested variants ---
for v in "${VARIANTS_TO_BUILD[@]}"; do
  build_variant "$v"
done
