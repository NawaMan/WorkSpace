# syntax=docker/dockerfile:1.7
FROM nawaman/workspace:notebook-latest

USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

# -----------------------------------------------------------
# Install code-server (uses Open VSX for extensions)
# -----------------------------------------------------------
RUN set -euo pipefail \
 && curl -fsSL https://code-server.dev/install.sh | bash \
 && code-server --version

# -----------------------------------------------------------
# Global config + preinstalled extensions (Open VSX)
# - Jupyter in code-server
# - Python support
# - Ruff + Black for a solid DX without Pylance (not on Open VSX)
# -----------------------------------------------------------
ENV CODESERVER_EXT_DIR=/opt/code-server/extensions \
    WORKSPACE_PORT=10000

RUN mkdir -p /etc/code-server "$CODESERVER_EXT_DIR" \
 && cat >/etc/code-server/config.yaml <<'EOF'
bind-addr: 0.0.0.0:10000
auth: none                # dev default; set PASSWORD at runtime to enable password auth
cert: false
extensions-dir: /opt/code-server/extensions
EOF

# Preinstall extensions to global dir (read-only at image level)
# Guard: ensure 'coder' user/group exist before chown (some base variants may not seed them)
RUN set -euo pipefail \
 && code-server --extensions-dir "$CODESERVER_EXT_DIR" --install-extension ms-toolsai.jupyter \
 && code-server --extensions-dir "$CODESERVER_EXT_DIR" --install-extension ms-toolsai.jupyter-keymap \
 && code-server --extensions-dir "$CODESERVER_EXT_DIR" --install-extension ms-toolsai.jupyter-renderers \
 && code-server --extensions-dir "$CODESERVER_EXT_DIR" --install-extension ms-python.python \
 && code-server --extensions-dir "$CODESERVER_EXT_DIR" --install-extension charliermarsh.ruff \
 && code-server --extensions-dir "$CODESERVER_EXT_DIR" --install-extension ms-python.black-formatter \
 && { getent group coder >/dev/null 2>&1 || groupadd -r coder; } \
 && { id -u coder >/dev/null 2>&1 || useradd -m -g coder -s /bin/bash coder; } \
 && chown -R coder:coder /opt/code-server

# Handy aliases
RUN cat >>/etc/profile.d/99-custom.sh <<'EOF'

# ---- code-server shortcuts ----
alias code='code-server'
alias cserver='code-server'
# ---- end code-server shortcuts ----
EOF

# -----------------------------------------------------------
# Launcher:
# - Keeps base ENTRYPOINT (tini -> workspace-user-setup) to align UID/GID
# - Starts code-server
# - Optionally starts JupyterLab too when RUN_JUPYTER=1
# - Auth: default none; set PASSWORD to switch to password auth
# -----------------------------------------------------------
RUN cat >/usr/local/bin/start-workbench <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_PORT="${WORKSPACE_PORT:-10000}"
ROOT="${WORKSPACE:-$HOME}"
AUTH="none"
if [[ -n "${PASSWORD:-}" ]]; then
  AUTH="password"  # code-server reads PASSWORD env when auth=password
fi

# Optionally run JupyterLab alongside code-server
if [[ "${RUN_JUPYTER:-0}" = "1" ]]; then
  jupyter lab \
    --no-browser \
    --ip=0.0.0.0 \
    --port="${WORKSPACE_PORT:-10000}" \
    --IdentityProvider.token="${JUPYTER_TOKEN:-}" \
    --ServerApp.allow_origin='*' \
    --ServerApp.allow_remote_access=True \
    --ServerApp.root_dir="${ROOT}" \
    >/tmp/jupyter.log 2>&1 &
fi

exec code-server \
  --config /etc/code-server/config.yaml \
  --bind-addr "0.0.0.0:${WORKSPACE_PORT}" \
  --user-data-dir "$HOME/.local/share/code-server" \
  --extensions-dir "/opt/code-server/extensions" \
  --disable-update-check \
  --disable-telemetry \
  --auth "${AUTH}" \
  "${ROOT}"
EOF
RUN chmod 0755 /usr/local/bin/start-workbench

# This is needed as it is created by the root and it is done AFTER workspace-user-setup change the permission.
RUN rm -rf /home/coder/.cache /home/coder/.config /home/coder/.local || true

# Keep base ENTRYPOINT (tini -> /usr/local/bin/workspace-user-setup)
EXPOSE 10000
WORKDIR /home/coder/workspace
CMD ["start-workbench"]
