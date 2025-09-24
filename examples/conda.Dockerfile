# syntax=docker/dockerfile:1.7
ARG VARIANT_TAG=container
ARG VERSION_TAG=latest
ARG PORT=10000
FROM nawaman/workspace:${VARIANT_TAG}-${VERSION_TAG}

# The default value is the latest LTS
ARG PY_VERSION=3.11

ARG PORT=10000

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ENV FEATURE_DIR=/opt/workspace/features
ENV PY_VERSION="${PY_VERSION}"
ENV PORT="${PORT}"

RUN chmod +x ${FEATURE_DIR}/conda-setup.sh
RUN "$FEATURE_DIR/conda-setup.sh" "${PY_VERSION}"
