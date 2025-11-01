# syntax=docker/dockerfile:1.7
FROM nawaman/workspace:container-0.3.0

ARG PY_VERSION=3.12

USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

ENV SETUPS_DIR=/opt/workspace/setups
ENV PY_VERSION="${PY_VERSION}"

RUN "$SETUPS_DIR/python--setup.sh" "${PY_VERSION}" 
RUN "$SETUPS_DIR/codeserver--setup.sh"
RUN "$SETUPS_DIR/python-code-extension--setup.sh"
RUN "$SETUPS_DIR/jupyter-code-extension--setup.sh"
RUN "$SETUPS_DIR/base-code-extension--setup.sh"
RUN "$SETUPS_DIR/bash-code-extension--setup.sh"
RUN "$SETUPS_DIR/bash-nb-kernel--setup.sh"

CMD ["codeserver"]
