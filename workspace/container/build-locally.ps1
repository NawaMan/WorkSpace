[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$h
)

# Set error action preference to stop on errors (equivalent to set -e)
$ErrorActionPreference = "Stop"

###########################################################
# Script to build the workspace docker image for local run.
###########################################################

# ---------- Defaults ----------
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$IMAGE_NAME = if ($env:IMAGE_NAME) { $env:IMAGE_NAME } else { "nawaman/workspace:container-local" }

function Show-Help {
    @"
Usage:
 build-locally.ps1 [OPTIONS]

Builds the local Docker image. No containers are run.

Options:
 -h, -Help    Show this help message
"@
}

# --------- Parse CLI ---------
if ($Help -or $h) {
    Show-Help
    exit 0
}

# Check for any unrecognized parameters
$BoundParameters = $PSBoundParameters.Keys
$ValidParameters = @('Help', 'h', 'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction')
foreach ($param in $BoundParameters) {
    if ($param -notin $ValidParameters) {
        Write-Error "Error: unrecognized option: '$param'"
        Write-Host "Try 'build-locally.ps1 -Help'."
        exit 2
    }
}

# --------- Build local image only ---------
$DockerfilePath = Join-Path $SCRIPT_DIR "Dockerfile"
if (-not (Test-Path $DockerfilePath)) {
    Write-Error "Error: no Dockerfile found in $SCRIPT_DIR"
    exit 1
}

Write-Host "Building local image: $IMAGE_NAME"

try {
    docker build -t $IMAGE_NAME -f $DockerfilePath $SCRIPT_DIR --no-cache
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed with exit code $LASTEXITCODE"
    }
    Write-Host "Build complete: $IMAGE_NAME"
}
catch {
    Write-Error "Build failed: $_"
    exit 1
}