#!/usr/bin/env bash
set -euo pipefail

#== ENVIRONMENTAL VARIABLES ==
DOCKER_USER_SCRIPT="${DOCKER_USER_SCRIPT:-}"
DOCKER_PAT_SCRIPT="${DOCKER_PAT_SCRIPT:-}"

# Cosign key configuration
COSIGN_KEY_FILE_DEFAULT="${HOME}/.config/nawaman-workspace/cosign.key"
COSIGN_KEY_FILE="${COSIGN_KEY_FILE:-$COSIGN_KEY_FILE_DEFAULT}"
COSIGN_KEY_REF=""

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

select_cosign_key() {
  if [[ -n "${COSIGN_KEY:-}" ]]; then
    COSIGN_KEY_REF="env://COSIGN_KEY"
    log "Cosign: using key from COSIGN_KEY environment variable"
  else
    COSIGN_KEY_FILE="${COSIGN_KEY_FILE:-$COSIGN_KEY_FILE_DEFAULT}"
    if [[ ! -f "${COSIGN_KEY_FILE}" ]]; then
      die "Cosign key file not found at '${COSIGN_KEY_FILE}'. Set COSIGN_KEY or COSIGN_KEY_FILE."
    fi
    COSIGN_KEY_REF="${COSIGN_KEY_FILE}"
    log "Cosign: using key file ${COSIGN_KEY_FILE}"
  fi
}

sign_images() {
  local -a args=("$@")
  local -a tags=()
  local token expect_ref=0

  echo "Extract image references from -t <ref> pairs"
  for token in "${args[@]}"; do
    if (( expect_ref )); then
      tags+=("$token")
      expect_ref=0
    elif [[ "$token" == "-t" ]]; then
      expect_ref=1
    fi
  done

  if (( expect_ref )); then
    die "Malformed TAGS_ARG: '-t' at end with no image reference"
  fi

  if [[ "${#tags[@]}" -eq 0 ]]; then
    log "Cosign: no images found to sign (TAGS_ARG was empty?)"
    return 0
  fi

  log "Cosign: signing the following tags (cosign will resolve digests):"
  for tag in "${tags[@]}"; do
    log "  - ${tag}"
  done

  for tag in "${tags[@]}"; do
    if [[ "${VERBOSE:-false}" == "true" ]]; then
      log "Cosign: signing tag ${tag} with key ${COSIGN_KEY_REF}"
      COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" \
      cosign sign --yes --key "${COSIGN_KEY_REF}" "${tag}" || \
        die "cosign sign failed for image tag: ${tag}"
    else
      log "Cosign: signing tag ${tag}"
      if ! COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" \
        cosign sign --yes --key "${COSIGN_KEY_REF}" "${tag}" >/dev/null 2>&1; then
        die "cosign sign failed for image tag: ${tag} (re-run with VERBOSE=true for details)"
      fi
    fi
  done

  log "Cosign: successfully signed ${#tags[@]} tag(s)."
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
    log "Setting up buildx (driver: docker-container; multi-arch: ${PLATFORMS})"
    docker buildx create --use --name ci_builder >/dev/null 2>&1 || docker buildx use ci_builder
    docker buildx inspect --bootstrap >/dev/null

    log "Building with buildx (push)"
    docker buildx build \
      "${NO_CACHE_ARG[@]}" \
      --platform "${PLATFORMS}" \
      -f "${DOCKER_FILE}" \
      --build-arg "VERSION_TAG=${VERSION_TAG}" \
      "${TAGS_ARG[@]}" \
      "${CONTEXT_DIR}" \
      --push

    log "Calling cosign to sign pushed images for variant '${VARIANT}'"
    sign_images "${TAGS_ARG[@]}"
  else
    log "Local build (plain 'docker build')"
    export DOCKER_BUILDKIT=1
    docker build \
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
  --push          Build and push using buildx (multi-arch) and sign images with cosign
  --no-cache      Build without using cache
  -h, --help      Show this help

Variants (if none provided, all are built):
  container
  ide-notebook
  ide-codeserver
  desktop-xfce
  desktop-kde
  desktop-lxqt

Environment:
  COSIGN_KEY        Cosign private key content (PEM) stored directly in env; used if set
  COSIGN_KEY_FILE   Path to cosign private key file (default: ${COSIGN_KEY_FILE_DEFAULT})
  COSIGN_PASSWORD   Password for the private key (if the key is encrypted)

Examples:
  ./build.sh                         # local build of all variants
  ./build.sh container               # build only 'container'
  ./build.sh ide-notebook desktop-xfce
                                     # build two specific variants
  ./build.sh --push container        # push + sign only 'container' variant
  COSIGN_KEY_FILE=/path/to/cosign.key ./build.sh --push container
                                     # push + sign using key file
  COSIGN_KEY="\$(cat cosign.key)" ./build.sh --push container
                                     # push + sign using key from env
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

set -- "${POSITIONAL[@]}"

if [[ $# -gt 0 ]]; then
  VARIANTS_TO_BUILD=("$@")
else
  VARIANTS_TO_BUILD=("${ALL_VARIANTS[@]}")
fi

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

  if ! command -v cosign >/dev/null 2>&1; then
    die "cosign not found in PATH but --push was requested. Install cosign to sign images."
  fi

  select_cosign_key
fi

for v in "${VARIANTS_TO_BUILD[@]}"; do
  build_variant "$v"
done
