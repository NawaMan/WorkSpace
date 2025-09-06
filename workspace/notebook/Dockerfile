# syntax=docker/dockerfile:1.7
FROM nawaman/workspace:container-latest

# Stay as root so the base ENTRYPOINT (workspace-user-setup) can align uid/gid, then drop to 'coder'
USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

ENV FEATURE_DIR=/opt/workspace/features
RUN /opt/workspace/features/notebook-setup.sh

CMD ["notebook"]
