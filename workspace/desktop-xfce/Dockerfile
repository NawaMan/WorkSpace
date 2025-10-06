# syntax=docker/dockerfile:1.7
ARG VERSION_TAG=latest
FROM nawaman/workspace:container-0.2.0--rc

ARG PY_VERSION=3.12

# Stay as root so the base ENTRYPOINT (workspace-user-setup) can align uid/gid, then drop to 'coder'
USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

ENV FEATURE_DIR=/opt/workspace/setups

RUN "$FEATURE_DIR/xfce-setup.sh"
ENV PY_VERSION="${PY_VERSION}"

# Not really needed but feel unuseful without them.
RUN "$FEATURE_DIR/firefox-setup.sh"
RUN "$FEATURE_DIR/chrome-setup.sh"
RUN "$FEATURE_DIR/python-setup.sh" "${PY_VERSION}" 
RUN "$FEATURE_DIR/vscode-setup.sh"
RUN "$FEATURE_DIR/python-code-extension-setup.sh"   # Does not seems to work
RUN "$FEATURE_DIR/jupyter-code-extension-setup.sh"  # Does not seems to work
RUN "$FEATURE_DIR/bash-nb-kernel-setup.sh"

CMD ["start-xfce"]
