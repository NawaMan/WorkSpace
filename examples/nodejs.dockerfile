# syntax=docker/dockerfile:1.7
ARG VARIANT_TAG=container
ARG VERSION_TAG=latest
FROM nawaman/workspace:${VARIANT_TAG}-${VERSION_TAG}

# The default value is the latest LTS
ARG NODEJS_VERSION=24.9.0

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ENV SETUPS_DIR=/opt/workspace/setups
ENV NODEJS_VERSION="${NODEJS_VERSION}"
ENV PORT="${PORT}"

RUN "$SETUPS_DIR/nodejs-setup.sh" "${NODEJS_VERSION}" 
