# syntax=docker/dockerfile:1.7
ARG VERSION_TAG=latest
FROM nawaman/workspace:container-latest

ARG PY_VERSION=3.11
ARG PORT=10000

USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

ENV FEATURE_DIR=/opt/workspace/features
ENV PY_VERSION="${PY_VERSION}"
ENV PORT="${PORT}"

RUN "$FEATURE_DIR/codeserver-setup.sh" "${PY_VERSION}" 

CMD ["codeserver"]
