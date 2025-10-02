# syntax=docker/dockerfile:1.7
FROM nawaman/workspace:container-0.2.0--rc

ARG PY_VERSION=3.12

# Stay as root so the base ENTRYPOINT (workspace-user-setup) can align uid/gid, then drop to 'coder'
USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

ENV FEATURE_DIR=/opt/workspace/setups
ENV PY_VERSION="${PY_VERSION}"

RUN "$FEATURE_DIR/notebook-setup.sh" "${PY_VERSION}" 

CMD ["notebook"]
