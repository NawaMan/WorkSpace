# syntax=docker/dockerfile:1.7
ARG VARIANT_TAG=container
ARG VERSION_TAG=latest
ARG PORT=10000
FROM nawaman/workspace:${VARIANT_TAG}-${VERSION_TAG}

# The default value is the latest LTS
ARG PY_VERSION=3.12
ARG VARIANT_TAG=container
ARG JDK_VERSION=25
ARG JDK_VENDOR=temurin
ARG MVN_VERSION=3.9.11
ARG PORT=10000

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ENV FEATURE_DIR=/opt/workspace/setups
ENV VARIANT_TAG="${VARIANT_TAG}"
ENV WS_VARIANT_TAG="${VARIANT_TAG}"
ENV PY_VERSION="${PY_VERSION}"
ENV JDK_VERSION="${JDK_VERSION}"
ENV JDK_VENDOR="${JDK_VENDOR}"
ENV MVN_VERSION="${MVN_VERSION}"
ENV PORT="${PORT}"

RUN "$FEATURE_DIR/python-setup.sh" "${PY_VERSION}"
RUN "$FEATURE_DIR/variant-setup.sh" "${PY_VERSION}"

RUN "$FEATURE_DIR/jdk-setup.sh" "${JDK_VERSION}" "${JDK_VENDOR}"
RUN "$FEATURE_DIR/mvn-setup.sh" "${MVN_VERSION}" 
RUN "$FEATURE_DIR/java-nb-kernel-setup.sh"
