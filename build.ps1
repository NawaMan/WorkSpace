#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
  PowerShell port of build.sh

  Features:
    • Reads version from version.txt
    • --push flag to build+push (Docker Hub login via DOCKERHUB_USERNAME/DOCKERHUB_TOKEN)
    • Multi-arch via buildx (configurable PLATFORMS)
    • In non-push mode, restricts to host platform to allow --load
    • Builds variants: container, notebook, codeserver with appropriate tags
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ===== ENVIRONMENTAL VARIABLES (kept for parity; not used directly here) =====
$DOCKER_USER_SCRIPT = $env:DOCKER_USER_SCRIPT
$DOCKER_PAT_SCRIPT  = $env:DOCKER_PAT_SCRIPT

# ===== Settings =====
$IMAGE_NAME   = 'nawaman/workspace'
$PLATFORMS    = 'linux/amd64,linux/arm64'
$VERSION_FILE = 'version.txt'

# ===== Helpers =====
function Log([string]$msg) { Write-Host "[info] $msg" -ForegroundColor Cyan }
function Err([string]$msg) { Write-Host "[err ] $msg" -ForegroundColor Red }
function Die([string]$msg) { Err $msg; exit 1 }

function Usage {
@"
Usage: ./build.ps1 [--push]

Examples
  ./build.ps1        # build only (no push, loads image to local docker)
  ./build.ps1 --push # build and push (requires DOCKERHUB_USERNAME and DOCKERHUB_TOKEN)
"@ | Write-Host
}

# ===== Resolve version =====
if (Test-Path -LiteralPath $VERSION_FILE) {
  $VERSION_TAG = (Get-Content -LiteralPath $VERSION_FILE -Raw).Trim()
  if (-not $VERSION_TAG) { Die "Version file '$VERSION_FILE' is empty." }
} else {
  Die "No --push provided and '$VERSION_FILE' not found."  # mirrors bash wording intent
}

# ===== Arg parsing =====
$PUSH = $false
for ($i = 0; $i -lt $args.Count; $i++) {
  switch ($args[$i]) {
    '--push'  { $PUSH = $true }
    '-h'      { Usage; exit 0 }
    '--help'  { Usage; exit 0 }
    default   { Err "Unknown option: $($args[$i])"; Usage; exit 2 }
  }
}

# ===== Build function =====
function Build-Variant([string]$Variant = 'container') {
  $CONTEXT_DIR = "workspace/$Variant"
  $DOCKER_FILE = "$CONTEXT_DIR/Dockerfile"

  $tags = @(
    '-t', "${IMAGE_NAME}:${Variant}-${VERSION_TAG}",
    '-t', "${IMAGE_NAME}:${Variant}-latest"
  )
  if ($Variant -eq 'container') {
    $tags += @(
      '-t', "${IMAGE_NAME}:${VERSION_TAG}",
      '-t', "${IMAGE_NAME}:latest"
    )
  }

  Log "Image:      $IMAGE_NAME"
  Log "Variant:    $Variant"
  Log "Version:    $VERSION_TAG"
  Log "Context:    $CONTEXT_DIR"
  Log "Dockerfile: $DOCKER_FILE"
  Log ("Tags:       " + (($tags | Where-Object { $_ -ne '-t' }) -join ' ' -replace '(^|\s)-t\s+',''))

  # Sanity checks
  if (-not (Test-Path -LiteralPath $CONTEXT_DIR)) { Die "Context dir not found: $CONTEXT_DIR" }
  if (-not (Test-Path -LiteralPath $DOCKER_FILE)) { Die "Dockerfile not found:  $DOCKER_FILE" }

  # Buildx setup
  Log "Setting up buildx (multi-arch: $PLATFORMS)"
  # Try to create or use existing 'ci_builder'
  & docker buildx create --use --name ci_builder *> $null
  if ($LASTEXITCODE -ne 0) {
    & docker buildx use ci_builder
    if ($LASTEXITCODE -ne 0) { Die "Failed to create or select buildx builder 'ci_builder'." }
  }
  & docker buildx inspect --bootstrap *> $null
  if ($LASTEXITCODE -ne 0) { Die "docker buildx inspect --bootstrap failed." }

  # Decide platforms (avoid manifest-list load error on --load)
  $HOST_PLATFORM = (& docker version -f '{{.Server.Os}}/{{.Server.Arch}}' 2>$null)
  if (-not $HOST_PLATFORM) { $HOST_PLATFORM = 'linux/amd64' }

  if ($PUSH) {
    $EFFECTIVE_PLATFORMS = $PLATFORMS
  } else {
    $EFFECTIVE_PLATFORMS = $HOST_PLATFORM
    Log "Build-only mode: restricting platforms to $EFFECTIVE_PLATFORMS (--load can't import manifest lists)"
  }

  Log "Building with buildx"

  $buildArgs = @(
    'buildx','build',
    '--platform', $EFFECTIVE_PLATFORMS,
    '-f', $DOCKER_FILE
  ) + $tags + @(
    $CONTEXT_DIR
  )

  if ($PUSH) {
    $buildArgs += @('--push')
  } else {
    $buildArgs += @('--load')
  }

  & docker @buildArgs
  if ($LASTEXITCODE -ne 0) { Die "docker buildx build failed for variant '$Variant'." }

  Log "Done."
  Write-Host
}

# ===== Docker login (if pushing) =====
if ($PUSH) {
  $DOCKERHUB_USERNAME = $env:DOCKERHUB_USERNAME
  $DOCKERHUB_TOKEN    = $env:DOCKERHUB_TOKEN
  if (-not $DOCKERHUB_USERNAME -or -not $DOCKERHUB_TOKEN) {
    Err "❌ Username or token not set."
    Err "   Make sure both DOCKERHUB_USERNAME and DOCKERHUB_TOKEN are set."
    exit 3
  }
  Log "Logging in to Docker Hub as $DOCKERHUB_USERNAME"
  $login = $DOCKERHUB_TOKEN | & docker login -u $DOCKERHUB_USERNAME --password-stdin
  if ($LASTEXITCODE -ne 0) { Err "❌ Docker login failed"; exit 4 }
}

# ===== Build variants =====
Build-Variant 'container'
Build-Variant 'notebook'
Build-Variant 'codeserver'
