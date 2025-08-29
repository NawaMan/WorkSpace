param(
    [switch]$h,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

# Set error action preference to stop on errors
$ErrorActionPreference = "Stop"

###########################################################
# Example PowerShell script for running things on the workspace.
###########################################################

# ---------- Constants ----------
$IMAGE_NAME = if ($env:IMAGE_NAME) { $env:IMAGE_NAME } else { "nawaman/workspace:notebook-local" }
$CONTAINER_NAME = if ($env:CONTAINER_NAME) { $env:CONTAINER_NAME } else { "workspace-run" }
$WORKSPACE = "/home/coder/workspace"

# Get current user ID equivalent (Windows doesn't have uid/gid like Unix)
# For Windows/WSL compatibility, use default values or environment overrides
$HOST_UID = if ($env:HOST_UID) { $env:HOST_UID } else { "1000" }
$HOST_GID = if ($env:HOST_GID) { $env:HOST_GID } else { "1000" }

$SHELL_NAME = "bash"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Help {
    @"
Usage:
 run.ps1 [OPTIONS]                    # interactive shell (bash)
 run.ps1 [OPTIONS] -- <command...>    # run a command then exit

Options:
 -h, -Help    Show this help message

Note: Use '--' to separate Docker run arguments from the command to execute.
      Everything before '--' goes to 'docker run', everything after goes to the command.
"@
}

# --------- Parse CLI ---------
if ($Help -or $h) {
    Show-Help
    exit 0
}

# In PowerShell, -- is consumed by the parser, so we need a different approach
# We'll treat everything as either docker run args (starts with -) or command parts
$RunArgsList = @()
$CMD = @()
$FoundNonFlag = $false

foreach ($arg in $Arguments) {
    if ($arg.StartsWith("-") -and -not $FoundNonFlag) {
        # This is a docker run argument (flag)
        $RunArgsList += $arg
    } else {
        # This is part of the command to execute
        $FoundNonFlag = $true
        $CMD += $arg
    }
}

# Debug output (remove in production)
# Write-Host "DEBUG: Arguments   = $($Arguments   -join ', ')" -ForegroundColor Yellow
# Write-Host "DEBUG: RunArgsList = $($RunArgsList -join ', ')" -ForegroundColor Yellow
# Write-Host "DEBUG: CMD         = $($CMD         -join ', ')" -ForegroundColor Yellow

# --------- Ensure image exists ---------
try {
    docker image inspect $IMAGE_NAME *>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Image not found"
    }
}
catch {
    Write-Host "Image $IMAGE_NAME not found. Building it via build.ps1..."
    $BuildScript = Join-Path $SCRIPT_DIR "build-locally.ps1"
    if (-not (Test-Path $BuildScript)) {
        Write-Error "Error: build.ps1 not found in $SCRIPT_DIR"
        exit 1
    }
    & $BuildScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build script failed"
        exit 1
    }
}

# Clean up any previous container with the same name
try {
    docker rm -f $CONTAINER_NAME *>$null
} catch {
    # Ignore errors if container doesn't exist
}

# Determine TTY arguments
$TTY_ARGS = @("-i")
# Check if running in interactive mode (simplified check for PowerShell)
if ([Environment]::UserInteractive) {
    $TTY_ARGS = @("-i", "-t")
}

$COMMON_ARGS = @(
    "--name", $CONTAINER_NAME,
    "-e", "HOST_UID=$HOST_UID",
    "-e", "HOST_GID=$HOST_GID",
    "-v", "${PWD}:$WORKSPACE",
    "-w", $WORKSPACE,
    "-p", "8888:8888"
)

# --------- Run container ---------
if ($CMD.Length -eq 0) {
    # Interactive shell
    $DockerArgs = @("run", "--rm") + $TTY_ARGS + $COMMON_ARGS + $RunArgsList + @($IMAGE_NAME)
    # Write-Host "DEBUG: Docker command: docker $($DockerArgs -join ' ')" -ForegroundColor Green
    & docker @DockerArgs
} else {
    # Run specific command
    $USER_CMD = $CMD -join " "
    $DockerArgs = @("run", "--rm") + $TTY_ARGS + $COMMON_ARGS + $RunArgsList + @($IMAGE_NAME, $SHELL_NAME, "-lc", $USER_CMD)
    # Write-Host "DEBUG: Docker command: docker $($DockerArgs -join ' ')" -ForegroundColor Green
    & docker @DockerArgs
}

# Exit with the same code as docker
exit $LASTEXITCODE