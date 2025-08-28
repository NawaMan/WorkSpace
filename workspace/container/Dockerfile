# syntax=docker/dockerfile:1.7

# Dockerfile for workspace container (the base)
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive
ARG LOCALE=en_US.UTF-8

# Safer default shell
SHELL ["/bin/bash","-o","pipefail","-lc"]

# Update base OS, install packages, generate locale
# NOTE: we intentionally DO NOT install python3-pip (it can pull in an old setuptools)
RUN set -euo pipefail         \
 && apt-get update            \
 && apt-get install           \
      -y                      \
      --no-install-recommends \
      bash                    \
      ca-certificates         \
      curl                    \
      git                     \
      jq                      \
      less                    \
      locales                 \
      nano                    \
      sudo                    \
      tini                    \
      tree                    \
      unzip                   \
      wget                    \
      yq                      \
      zip                     \
      zsh                     \
 && sed -i "/${LOCALE}/s/^# //g" /etc/locale.gen \
 && locale-gen "${LOCALE}"

# Fixed values (name & paths). UID/GID come from HOST_UID/HOST_GID at runtime.
ENV USER_NAME=coder  \
    HOME=/home/coder \
    LANG=${LOCALE}   \
    LC_ALL=${LOCALE} \
    WORKSPACE=/home/coder/workspace

# Make the venv default and set pip knobs AFTER the upgrade above
ENV PATH=/opt/venv/bin:/home/coder/.local/bin:$PATH \
    EDITOR=nano

# ---- Belt & suspenders: seed a 'coder' user/group even if 1000 is taken ----
# We pick the first free UID/GID >= 1000 so name lookups always work.
RUN set -eux; \
  free_uid() { local uid=1000; while getent passwd "$uid" >/dev/null; do uid=$((uid+1)); done; echo "$uid"; }; \
  free_gid() { local gid=1000; while getent group  "$gid" >/dev/null; do gid=$((gid+1)); done; echo "$gid"; }; \
  if ! getent group coder >/dev/null; then \
    gid="$(free_gid)"; \
    groupadd -g "$gid" coder; \
  fi; \
  if ! id -u coder >/dev/null 2>&1; then \
    uid="$(free_uid)"; \
    useradd -m -u "$uid" -g coder -s /bin/bash coder; \
  fi; \
  mkdir -p /home/coder/workspace; \
  chown -R coder:coder /home/coder

# Entry that aligns coder’s uid/gid to host, then drops privileges
COPY --chmod=0755 entry-script /usr/local/bin/entry-script

# Seed dirs (already created above; harmless if repeated)
RUN mkdir -p /home/coder/workspace

# --- Shared shell config: create the file ---
RUN cat >/etc/profile.d/99-custom.sh <<'EOF'
# ---- container defaults (safe to source multiple times) ----
alias cp='cp -p'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias tree='tree -C'
# Environment
export EDITOR=${EDITOR:-nano}
export EDITOR=${EDITOR:-nano}
# Permissions: default to 0664 files / 0775 dirs
umask 0002
# ---- end defaults ----
EOF

# --- Make bash and zsh source it ---
RUN set -euo pipefail                                                                                         \
 && mkdir -p /etc/zsh                                                                                         \
 && touch /etc/bash.bashrc /etc/zsh/zshrc                                                                     \
 && grep -Fq '/etc/profile.d/99-custom.sh' /etc/bash.bashrc                                                   \
      || printf "\n[ -f /etc/profile.d/99-custom.sh ] && . /etc/profile.d/99-custom.sh\n" >> /etc/bash.bashrc \
 && grep -Fq '/etc/profile.d/99-custom.sh' /etc/zsh/zshrc                                                     \
      || printf "\n[ -f /etc/profile.d/99-custom.sh ] && . /etc/profile.d/99-custom.sh\n" >> /etc/zsh/zshrc

# Always start as root so entry-script can realign ids (decisive fix)
USER root

# Workdir (created earlier; ownership finalized by entry-script at runtime)
WORKDIR /home/coder/workspace

# tini as PID 1, then run the aligner which execs as 'coder'
ENTRYPOINT ["tini","-g","--","/usr/local/bin/entry-script"]
CMD ["bash"]
