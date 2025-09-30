# syntax=docker/dockerfile:1.7
ARG VARIANT_TAG=container
ARG VERSION_TAG=latest
ARG PORT=10000
FROM nawaman/workspace:${VARIANT_TAG}-${VERSION_TAG}

# The default value is the latest LTS
ARG NODEJS_VERSION=24.9.0
ARG PORT=10000

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ENV FEATURE_DIR=/opt/workspace/setups
ENV NODEJS_VERSION="${NODEJS_VERSION}"
ENV PORT="${PORT}"

RUN "$FEATURE_DIR/nodejs-setup.sh" "${NODEJS_VERSION}" 
