# syntax=docker/dockerfile:1.7
FROM nawaman/workspace:desktop-xfce-0.2.0--rc

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

RUN "$FEATURE_DIR/vscode-setup.sh"
RUN "$FEATURE_DIR/jupyter-code-extension-setup.sh"
RUN "$FEATURE_DIR/bash-code-extension-setup.sh"
RUN "$FEATURE_DIR/python-code-extension-setup.sh"
RUN "$FEATURE_DIR/base-code-extension-setup.sh"
RUN "$FEATURE_DIR/bash-nb-kernel-setup.sh"
