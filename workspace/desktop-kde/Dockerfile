# syntax=docker/dockerfile:1.7
FROM nawaman/workspace:container-0.2.0--rc

ARG PY_VERSION=3.12

# Stay as root so the base ENTRYPOINT (workspace-user-setup) can align uid/gid, then drop to 'coder'
USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

ENV FEATURE_DIR=/opt/workspace/setups
ENV PY_VERSION="${PY_VERSION}"

RUN "$FEATURE_DIR/kde-setup.sh"

# Not really "needed" but feel unuseful without them so put here as a "good starting point".
RUN "$FEATURE_DIR/firefox-setup.sh"
RUN "$FEATURE_DIR/chrome-setup.sh"
RUN "$FEATURE_DIR/python-setup.sh" "${PY_VERSION}" 
RUN "$FEATURE_DIR/vscode-setup.sh"
RUN "$FEATURE_DIR/jupyter-code-extension-setup.sh"
RUN "$FEATURE_DIR/bash-code-extension-setup.sh"
RUN "$FEATURE_DIR/python-code-extension-setup.sh"
RUN "$FEATURE_DIR/base-code-extension-setup.sh"
RUN "$FEATURE_DIR/bash-nb-kernel-setup.sh"

# This is so that some basic GTK would work.
RUN apt-get update && apt-get install -y \
        breeze-gtk-theme \
        gnome-themes-extra \
        libgtk-3-0 \
        libcanberra-gtk3-module \
        lxappearance \
        kde-config-gtk-style


CMD ["start-kde"]
