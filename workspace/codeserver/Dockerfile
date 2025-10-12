# syntax=docker/dockerfile:1.7
FROM nawaman/workspace:container-0.2.0--rc

ARG PY_VERSION=3.12

USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

ENV FEATURE_DIR=/opt/workspace/setups
ENV PY_VERSION="${PY_VERSION}"

RUN "$FEATURE_DIR/codeserver-setup.sh" "${PY_VERSION}" 
RUN "$FEATURE_DIR/python-code-extension-setup.sh"
RUN "$FEATURE_DIR/jupyter-code-extension-setup.sh"
RUN "$FEATURE_DIR/bash-code-extension-setup.sh"
RUN "$FEATURE_DIR/base-code-extension-setup.sh"

CMD ["codeserver"]
