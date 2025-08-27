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
RUN set -euo pipefail \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      jq \
      less \
      locales \
      nano \
      python3 \
      python3-venv \
      sudo \
      tini \
      tree \
      unzip \
      wget \
      zip \
      zsh \
 && sed -i "/${LOCALE}/s/^# //g" /etc/locale.gen \
 && locale-gen "${LOCALE}" \
 # ensure any system setuptools/pip are removed so scanners don't see them
 && apt-get purge -y python3-setuptools python3-pip || true \
 && rm -rf \
      /usr/lib/python*/dist-packages/setuptools* \
      /usr/lib/python*/dist-packages/pkg_resources* \
      /usr/lib/python*/dist-packages/_distutils_hack* \
 && rm -rf /var/lib/apt/lists/*

# Fixed values (name & paths). UID/GID come from HOST_UID/HOST_GID at runtime.
ENV USER_NAME=coder  \
    HOME=/home/coder \
    LANG=${LOCALE}   \
    LC_ALL=${LOCALE} \
    WORKSPACE=/home/coder/workspace

# Create a Python venv and upgrade pip/setuptools/wheel (addresses setuptools CVEs)
# Pin exact versions for reproducibility and avoid caching.
RUN set -euo pipefail                                               \
 && python3 -m venv /opt/venv                                       \
 && /opt/venv/bin/python -m ensurepip --upgrade                     \
 && /opt/venv/bin/python -m pip install --no-cache-dir --no-compile \
      pip==24.2 setuptools==75.1.0 wheel==0.44.0                    \
 && rm -rf /root/.cache/pip

# Make the venv default and set pip knobs AFTER the upgrade above
ENV PATH=/opt/venv/bin:/home/coder/.local/bin:$PATH \
    EDITOR=nano                                     \
    PIP_DISABLE_PIP_VERSION_CHECK=1                 \
    PIP_NO_CACHE_DIR=1

# Entry that aligns coder’s uid/gid to host, then drops privileges
COPY --chmod=0755 entry-script /usr/local/bin/entry-script

WORKDIR /home/coder/workspace

# Seed dirs; ownership finalized at runtime
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
export PIP_DISABLE_PIP_VERSION_CHECK=1
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

# tini as PID 1, then run the aligner which execs as 'coder'
ENTRYPOINT ["tini","-g","--","/usr/local/bin/entry-script"]
CMD ["bash"]
