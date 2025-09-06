# syntax=docker/dockerfile:1.7
ARG VERSION_TAG=latest
FROM nawaman/workspace:container-latest

USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

RUN /opt/workspace/features/codeserver-setup.sh

CMD ["codeserver"]
