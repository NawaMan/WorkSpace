# syntax=docker/dockerfile:1.7
FROM nawaman/workspace:container-0.3.0

ARG PY_VERSION=3.12

# Stay as root so the base ENTRYPOINT (workspace-user-setup) can align uid/gid, then drop to 'coder'
USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

ENV SETUPS_DIR=/opt/workspace/setups
ENV PY_VERSION="${PY_VERSION}"

RUN "$SETUPS_DIR/lxqt--setup.sh"

# Not really "needed" but feel unuseful without them so put here as a "good starting point".
RUN "$SETUPS_DIR/firefox--setup.sh"
RUN "$SETUPS_DIR/google-chrome--setup.sh"
RUN "$SETUPS_DIR/chromium-browser--setup.sh"
RUN "$SETUPS_DIR/python--setup.sh" "${PY_VERSION}" 
RUN "$SETUPS_DIR/vscode--setup.sh"
RUN "$SETUPS_DIR/jupyter-code-extension--setup.sh"
RUN "$SETUPS_DIR/bash-code-extension--setup.sh"
RUN "$SETUPS_DIR/python-code-extension--setup.sh"
RUN "$SETUPS_DIR/base-code-extension--setup.sh"
RUN "$SETUPS_DIR/bash-nb-kernel--setup.sh"

# This is so that some basic GTK would work.
RUN apt-get update && apt-get install -y \
        breeze-gtk-theme \
        gnome-themes-extra \
        libgtk-3-0 \
        libcanberra-gtk3-module \
        lxappearance \
        kde-config-gtk-style

CMD ["start-lxqt"]
