# syntax=docker/dockerfile:1.7
ARG VARIANT_TAG=container
ARG VERSION_TAG=latest
FROM nawaman/workspace:${VARIANT_TAG}-${VERSION_TAG}

# The default value is the latest LTS
ARG PY_VERSION=3.12
ARG VARIANT_TAG=container
ARG NODE_MAJOR=24
ARG NVM_VERSION=0.40.3

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ENV SETUPS_DIR=/opt/workspace/setups
ENV VARIANT_TAG="${VARIANT_TAG}"
ENV WS_VARIANT_TAG="${VARIANT_TAG}"
ENV PY_VERSION="${PY_VERSION}"
ENV NODE_MAJOR="${NODE_MAJOR}"
ENV NVM_VERSION="${NVM_VERSION}"

RUN "$SETUPS_DIR/nodejs-setup.sh" ${NODE_MAJOR} --nvm-version=${NVM_VERSION}

RUN if [[ "$VARIANT_TAG" == desktop-* ]]; then "$SETUPS_DIR/jetbrains-setup.sh" webstorm ; fi
