#!/bin/bash

set -euo pipefail

# This is to be run by sudo
# Ensure script is run as root (EUID == 0)
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

FEATURE_DIR=${FEATURE_DIR:-.}

${FEATURE_DIR}/python-setup.sh

/opt/venv/bin/pip      \
    install            \
    --no-cache-dir     \
    --no-compile       \
    jupyter==1.1.1     \
    jupyterlab==4.2.5  \
    notebook==7.2.2    \
    bash_kernel==0.9.3

/opt/venv/bin/python -m bash_kernel.install

/opt/venv/bin/pip install \
    --no-cache-dir        \
    --no-compile          \
    "httpx<0.28"

rm -rf /root/.cache/pip

# Global (read-only) Jupyter config; user-writable files go to ~/.jupyter
mkdir -p /etc/jupyter
cat > /etc/jupyter/jupyter_lab_config.py <<'EOF'
c.ServerApp.ip = 'localhost'
c.ServerApp.open_browser = False
c.ServerApp.allow_origin = '*'
c.ServerApp.allow_remote_access = True
c.ServerApp.root_dir = '/home/coder/workspace'
# Quiet the extension manager warnings (optional; comment out to enable PyPI manager)
c.LabApp.extension_manager = 'readonly'

# >>> Make JupyterLab terminals use bash
c.ServerApp.terminado_settings = {'shell_command': ['/bin/bash']}
EOF

# Optional: handy aliases
cat >>/etc/profile.d/99-custom.sh <<'EOF'

# ---- Jupyter shortcuts ----
alias jupyter-lab='jupyter lab'
alias jupyter-notebook='jupyter notebook'
alias jlab='jupyter lab'
alias jnb='jupyter notebook'
# ---- end Jupyter shortcuts ----
EOF

# This is needed as it is created by the root and it is done AFTER workspace-user-setup change the permission.
rm -rf /home/coder/.ipython || true


# Create startup script inline
cat <<'EOF' >/usr/local/bin/notebook
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE_PORT="${WORKSPACE_PORT:-10000}"
exec jupyter lab \
  --no-browser \
  --ip=0.0.0.0 \
  --port=10000 \
  --IdentityProvider.token='' \
  --ServerApp.custom_display_url="http://localhost:${WORKSPACE_PORT}/lab"
EOF

# Make it executable
chmod +x /usr/local/bin/notebook