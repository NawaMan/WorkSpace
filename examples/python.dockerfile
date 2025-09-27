# syntax=docker/dockerfile:1.7
ARG VARIANT_TAG=container
ARG VERSION_TAG=latest
ARG PORT=10000
FROM nawaman/workspace:${VARIANT_TAG}-${VERSION_TAG}

# The default value is the latest LTS
ARG PY_VERSION=3.11
ARG VARIANT_TAG=container
ARG PORT=10000

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ENV FEATURE_DIR=/opt/workspace/features
ENV VARIANT_TAG="${VARIANT_TAG}"
ENV WS_VARIANT_TAG="${VARIANT_TAG}"
ENV PORT="${PORT}"
ENV PY_VERSION="${PY_VERSION}"
ENV BASH_ENV=/etc/profile.d/99-custom.sh

# For python, we need to reinstall variant specific script.
RUN "$FEATURE_DIR/python-setup.sh"  "${PY_VERSION}"
RUN "$FEATURE_DIR/variant-setup.sh" "${PY_VERSION}"
