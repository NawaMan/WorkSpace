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

RUN "$SETUPS_DIR"/jdk-setup.sh 8
RUN "$SETUPS_DIR"/jdk-setup.sh 9
RUN "$SETUPS_DIR"/java-nb-kernel-setup.sh
# RUN "$SETUPS_DIR"/jdk-setup.sh 10          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$SETUPS_DIR/java-nb-kernel-setup.sh
# RUN "$SETUPS_DIR"/jdk-setup.sh 11          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$SETUPS_DIR/java-nb-kernel-setup.sh
# RUN "$SETUPS_DIR"/jdk-setup.sh 12          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$SETUPS_DIR/java-nb-kernel-setup.sh
# RUN "$SETUPS_DIR"/jdk-setup.sh 13          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$SETUPS_DIR/java-nb-kernel-setup.sh
# RUN "$SETUPS_DIR"/jdk-setup.sh 14          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$SETUPS_DIR/java-nb-kernel-setup.sh
# RUN "$SETUPS_DIR"/jdk-setup.sh 15          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$SETUPS_DIR/java-nb-kernel-setup.sh
# RUN "$SETUPS_DIR"/jdk-setup.sh 16          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$SETUPS_DIR/java-nb-kernel-setup.sh
RUN "$SETUPS_DIR"/jdk-setup.sh 17
RUN "$SETUPS_DIR"/java-nb-kernel-setup.sh
RUN "$SETUPS_DIR"/jdk-setup.sh 18
RUN "$SETUPS_DIR"/java-nb-kernel-setup.sh
RUN "$SETUPS_DIR"/jdk-setup.sh 19
RUN "$SETUPS_DIR"/java-nb-kernel-setup.sh
RUN "$SETUPS_DIR"/jdk-setup.sh 20
RUN "$SETUPS_DIR"/java-nb-kernel-setup.sh
RUN "$SETUPS_DIR"/jdk-setup.sh 21
RUN "$SETUPS_DIR"/java-nb-kernel-setup.sh
RUN "$SETUPS_DIR"/jdk-setup.sh 22
RUN "$SETUPS_DIR"/java-nb-kernel-setup.sh
RUN "$SETUPS_DIR"/jdk-setup.sh 23
RUN "$SETUPS_DIR"/java-nb-kernel-setup.sh
RUN "$SETUPS_DIR"/jdk-setup.sh 24
RUN "$SETUPS_DIR"/java-nb-kernel-setup.sh
RUN "$SETUPS_DIR"/jdk-setup.sh 25
RUN "$SETUPS_DIR"/java-nb-kernel-setup.sh

RUN "$SETUPS_DIR"/mvn-setup.sh
RUN "$SETUPS_DIR"/gradle-setup.sh
RUN "$SETUPS_DIR"/jenv-setup.sh
RUN "$SETUPS_DIR"/eclipse-setup.sh
RUN "$SETUPS_DIR"/jetbrains-setup.sh idea
RUN "$SETUPS_DIR"/java-code-extension-setup.sh
RUN "$SETUPS_DIR"/lombok-eclipse-setup.sh

RUN "$SETUPS_DIR"/jetbrains-plugin-setup.sh idea "Lombook Plugin"