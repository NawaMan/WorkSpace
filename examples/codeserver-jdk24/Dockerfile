# syntax=docker/dockerfile:1.7
ARG VERSION_TAG=latest
FROM nawaman/workspace:codeserver-latest

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ENV FEATURE_DIR=/opt/workspace/features
RUN /opt/workspace/features/jdk-setup.sh 24

CMD ["codeserver"]
