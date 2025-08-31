# WorkSpace
WorkSpace for your project.

This project create a docker container with access to the current folder (as a current user/group).
This would allows the user to work on the project isolated from their host machine.



# workspace.sh and workspace.ps1

## Feature List

1. Image Selection
    - **Defaults:**
        - Repo: `nawaman/workspace`
        - Variant: `container`
        - Version: `latest`
    - **Overrides:**
        - Env vars: `IMGNAME`, `IMGREPO`, `IMG_TAG`, `VARIANT`, `VERSION`
        - Config file: `workspace.env`
        - CLI options: --variant, --version
    - **Precedence:** CLI > config file > environment vars > built-in defaults.
    - **Derived:**
        `IMGNAME` = `IMGREPO:IMG_TAG`
        `IMG_TAG` = defaults to `VARIANT-VERSION`

2. Container Name
    - Default: sanitized current folder name (workspace if empty).
    - Overrides:
        - Env var: `CONTAINER`
        - Config file: `workspace.env`
        - CLI: `--name <name>`

3. Config Files`
    - **Launcher config (`workspace.env`)**
        - Sourced before parsing CLI.
        - Keys: `IMGNAME`, `IMGREPO`, `IMG_TAG`, `VARIANT`, `VERSION`, `CONTAINER`, `HOST_UID`, `HOST_GID`, `NOTEBOOK_PORT`, `CODESERVER_PORT`.
    - **Container env-file (`.env`)**
        - Passed with `--env-file`.
        - Typical keys: `PASSWORD`, `JUPYTER_TOKEN`, `TZ`, `AWS_*`, etc.
        - Override with `--env-file F` or `CONTAINER_ENV_FILE`.
    - **Docker args file (`workspace-docker.args`)**
        - Lines are parsed into extra docker run args.
        - Override with `--docker-args F` or `DOCKER_ARGS_FILE`.
        - Supports comments and quoted paths.

4. Host UID/GID Handling
    - Defaults: use `id -u`, `id -g`.
    - Override via env vars `HOST_UID`, `HOST_GID`, or config file.
    - Passed into container as envs.

5. Run Modes
    - **Interactive shell (default)**
        - `docker run --rm -it ... $IMGNAME`
    - **Command mode (`-- <cmd>`)**
        - Runs given command under `bash -lc`.
    - **Daemon mode (`-d` or `--daemon`)**
        - Detached container.
        - For `container` variant, runs an infinite sleep loop.

6. Ports
    - **Notebook** variant → publishes `${NOTEBOOK_PORT:-8888}:8888`
    - **CodeServer** variant → publishes `${NOTEBOOK_PORT:-8888}:8888` and `${CODESERVER_PORT:-8080}:8080`
    - All ports can be overridden in workspace.env.

7. Pulling Images
    - `--pull` forces a pull.
    - Otherwise, pulls if image missing.
    - Errors if image not found locally afterwards.

8. Container Cleanup
    - Automatically `docker rm -f` old container with same name before run.

9. Dry-Run Mode
    - `--dryrun` prints the fully assembled `docker run ...` command.
    - No side effects (no docker checks, no container run).

10. Help

    - `-h` / `--help` prints detailed usage, configuration, and notes.

✅ Summary

Both **Bash** and **PowerShell** versions now support:
    - Config-driven launch (`workspace.env`, `.env`, `workspace-docker.args`)
    - Strong override precedence
    - Variant-sensitive defaults (ports, container name)
    - Robust run modes (interactive, command, daemon)
    - Dry-run preview
