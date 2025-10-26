# syntax=docker/dockerfile:1.7
ARG VARIANT_TAG=container
ARG VERSION_TAG=latest
FROM nawaman/workspace:${VARIANT_TAG}-${VERSION_TAG}

# The default value is the latest LTS
ARG PY_VERSION=3.12
ARG VARIANT_TAG=container
ARG JDK_VERSION=24
ARG JDK_VENDOR=temurin
ARG MVN_VERSION=3.9.11

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ENV SETUPS_DIR=/opt/workspace/setups
ENV VARIANT_TAG="${VARIANT_TAG}"
ENV WS_VARIANT_TAG="${VARIANT_TAG}"
ENV PY_VERSION="${PY_VERSION}"
ENV JDK_VERSION="${JDK_VERSION}"
ENV JDK_VENDOR="${JDK_VENDOR}"

RUN "$SETUPS_DIR"/python-setup.sh ${PY_VERSION}

# Needed by pycharm. if you don't use pycharm, remove this.
RUN "$SETUPS_DIR"/jdk-setup.sh 25

RUN if [[ "$VARIANT_TAG" == desktop-* ]]; then "$SETUPS_DIR"/pycharm-setup.sh                                       ; fi
RUN if [[ "$VARIANT_TAG" == desktop-* ]]; then "$SETUPS_DIR"/jetbrains-plugin-setup.sh pycharm ru.adelf.idea.dotenv ; fi
