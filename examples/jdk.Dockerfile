# syntax=docker/dockerfile:1.7
ARG VARIANT_TAG=container
ARG VERSION_TAG=latest
ARG PORT=10000
FROM nawaman/workspace:${VARIANT_TAG}-${VERSION_TAG}

# The default value is the latest LTS
ARG JDK_VERSION=21

ARG PORT=10000

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ENV FEATURE_DIR=/opt/workspace/features
ENV JDK_VERSION="${JDK_VERSION}"
ENV PORT="${PORT}"

RUN "$FEATURE_DIR/jdk-setup.sh" "${JDK_VERSION}" 