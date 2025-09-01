# syntax=docker/dockerfile:1.7
FROM nawaman/workspace:container-latest

# Stay as root so the base ENTRYPOINT (workspace-user-setup) can align uid/gid, then drop to 'coder'
USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

# --- System deps for Python/Jupyter ---
RUN set -euo pipefail \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-venv \
        python3-dev \
        build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# --- Python env + Jupyter ---
RUN set -euo pipefail \
    && if [ ! -d "/opt/venv" ]; then python3 -m venv /opt/venv; fi \
    && /opt/venv/bin/python -m ensurepip --upgrade \
    && /opt/venv/bin/pip install --no-cache-dir --no-compile \
        pip==25.2 setuptools==80.9.0 wheel==0.44.0 \
    && /opt/venv/bin/pip install --no-cache-dir --no-compile \
        jupyter==1.1.1 \
        jupyterlab==4.2.5 \
        notebook==7.2.2 \
        bash_kernel==0.9.3 \
    && /opt/venv/bin/python -m bash_kernel.install \
    && /opt/venv/bin/pip install --no-cache-dir --no-compile "httpx<0.28" \
    && rm -rf /root/.cache/pip

# Global (read-only) Jupyter config; user-writable files go to ~/.jupyter
RUN mkdir -p /etc/jupyter \
 && cat > /etc/jupyter/jupyter_lab_config.py <<'EOF'
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.allow_origin = '*'
c.ServerApp.allow_remote_access = True
c.ServerApp.root_dir = '/home/coder/workspace'
# Quiet the extension manager warnings (optional; comment out to enable PyPI manager)
c.LabApp.extension_manager = 'readonly'
EOF

# Optional: handy aliases
RUN cat >>/etc/profile.d/99-custom.sh <<'EOF'

# ---- Jupyter shortcuts ----
alias jupyter-lab='jupyter lab'
alias jupyter-notebook='jupyter notebook'
alias jlab='jupyter lab'
alias jnb='jupyter notebook'
# ---- end Jupyter shortcuts ----
EOF

EXPOSE 8888
WORKDIR /home/coder/workspace

# Inherit the base ENTRYPOINT (tini + /usr/local/bin/workspace-user-setup).
# Only set CMD; workspace-user-setup will realign ids and exec this as 'coder'.
# Empty token == no auth (dev only). Provide one via -e JUPYTER_TOKEN=... if needed.
CMD ["bash","-lc","jupyter lab --no-browser --ip=0.0.0.0 --IdentityProvider.token=''"]
