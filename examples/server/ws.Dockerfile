# syntax=docker/dockerfile:1.7
ARG WS_VARIANT_TAG=base
ARG WS_VERSION_TAG=latest
FROM nawaman/workspace:${WS_VARIANT_TAG}-${WS_VERSION_TAG}

# The default value is the latest LTS
ARG WS_PY_VERSION=3.12
ARG WS_VARIANT_TAG=base
ARG WS_JDK_VERSION=24
ARG WS_JDK_VENDOR=temurin
ARG WS_MVN_VERSION=3.9.11

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG WS_SETUPS_DIR=/opt/workspace/setups
ARG WS_VARIANT_TAG="${WS_VARIANT_TAG}"
ARG WS_VERSION_TAG="${WS_VERSION_TAG}"
ARG WS_PY_VERSION="${WS_PY_VERSION}"
ARG WS_JDK_VERSION="${WS_JDK_VERSION}"
ARG WS_JDK_VENDOR="${WS_JDK_VENDOR}"

RUN "$WS_SETUPS_DIR"/python--setup.sh ${WS_PY_VERSION}

# Needed by pycharm. if you don't use pycharm, remove this.
RUN "$WS_SETUPS_DIR"/jdk--setup.sh 25

RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/pycharm--setup.sh                                       ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/jetbrains-plugin--setup.sh pycharm ru.adelf.idea.dotenv ; fi
