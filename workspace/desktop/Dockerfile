# syntax=docker/dockerfile:1.7
ARG VERSION_TAG=latest
FROM nawaman/workspace:container-0.2.0--rc

USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

ENV FEATURE_DIR=/opt/workspace/setups

RUN "$FEATURE_DIR/xfce-setup.sh"
RUN "$FEATURE_DIR/firefox-setup.sh"
RUN "$FEATURE_DIR/chrome-setup.sh"

CMD ["start-xfce"]
