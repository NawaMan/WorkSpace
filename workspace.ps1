#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
  PowerShell port of your Bash "run container" script.

  Features:
    • Same flags: -d/--daemon, --pull, --variant, --version, --name, -h/--help
    • Unknown args before `--` -> RUN_ARGS
    • Everything after `--` (or first bare word if PowerShell eats `--`) -> CMDS
    • Env-var overrides: IMAGE_REPO, VARIANT, VERSION_TAG, IMAGE_TAG, CONTAINER_NAME, HOST_UID, HOST_GID
#>

# ---------- Shell strictness ----------
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------- Defaults ----------
$IMAGE_REPO_DEFAULT = 'nawaman/workspace'
$VARIANT_DEFAULT    = 'container'
$VERSION_DEFAULT    = 'latest'
$WORKSPACE          = '/home/coder/workspace'
$SHELL_NAME         = 'bash'

# ---------- Env overrides ----------
$IMAGE_REPO   = if ($env:IMAGE_REPO)   { $env:IMAGE_REPO }   else { $IMAGE_REPO_DEFAULT }
$VARIANT      = if ($env:VARIANT)      { $env:VARIANT }      else { $VARIANT_DEFAULT }
$VERSION_TAG  = if ($env:VERSION_TAG)  { $env:VERSION_TAG }  else { $VERSION_DEFAULT }

# Derived (will recompute after parsing too)
$IMAGE_TAG      = if ($env:IMAGE_TAG)      { $env:IMAGE_TAG }      else { "$VARIANT-$VERSION_TAG" }
$IMAGE_NAME     = "${IMAGE_REPO}:$IMAGE_TAG"
$CONTAINER_NAME = if ($env:CONTAINER_NAME) { $env:CONTAINER_NAME } else { "$VARIANT-run" }

# Respect HOST_UID/HOST_GID overrides else detect (Linux)
function Get-IdOrDefault([string]$switch, [string]$fallback) {
  try {
    $out = (& id $switch) 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { return $out.Trim() }
  } catch {}
  return $fallback
}
$HOST_UID = if ($env:HOST_UID) { $env:HOST_UID } else { Get-IdOrDefault '-u' '1000' }
$HOST_GID = if ($env:HOST_GID) { $env:HOST_GID } else { Get-IdOrDefault '-g' '1000' }

# ---------- Flags & collections ----------
$DAEMON   = $false
$DO_PULL  = $false
$RUN_ARGS = @()
$CMDS     = @()

# ---------- Help ----------
function Show-Help {
@"
Starting a workspace container.

Usage:
  $(Split-Path -Leaf $PSCommandPath) [OPTIONS] [RUN_ARGS]                 # interactive shell
  $(Split-Path -Leaf $PSCommandPath) [OPTIONS] [RUN_ARGS] -- <command...> # run command then exit
  $(Split-Path -Leaf $PSCommandPath) [OPTIONS] [RUN_ARGS] --daemon        # run detached

Options:
  -d, --daemon            Run container detached (background)
      --pull              Pull/refresh the image from registry (also pulls if image missing)
      --variant <name>    Variant prefix        (default: $VARIANT_DEFAULT)
      --version <tag>     Version suffix        (default: $VERSION_DEFAULT)
      --name    <name>    Container name        (default: <variant>-run)
  -h, --help              Show this help message

Notes:
  • Bind: . -> $WORKSPACE; Working dir: $WORKSPACE
"@ | Write-Host
}

# ---------- Arg parsing (robust; handles PowerShell eating `--`) ----------
function Normalize-Dashes([string]$s) {
  if ($null -eq $s) { return $s }
  return ($s -replace "[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]", "-")
}

# ALWAYS an array, even when there are zero args
$normArgs = @($args | ForEach-Object { Normalize-Dashes ([string]$_) })

function Split-KeyEqualsValue([string]$tok) {
  if ($tok -like '--*=*') {
    $p = $tok.Split('=', 2)
    return @{ Key = $p[0]; Value = $p[1] }
  }
  return $null
}

# If literal "--" survives, split there; else detect CMDS at first bare word.
$sepIndex = if ($normArgs.Count -gt 0) { [Array]::IndexOf($normArgs, '--') } else { -1 }

$left = @()
if ($sepIndex -ge 0) {
  if ($sepIndex -gt 0) { $left = $normArgs[0..($sepIndex-1)] }
  if ($sepIndex + 1 -lt $normArgs.Count) { $CMDS += $normArgs[($sepIndex+1)..($normArgs.Count-1)] }
} else {
  $left = $normArgs
}
$foundCmdsStart = ($sepIndex -ge 0)

for ($i = 0; $i -lt $left.Count; $i++) {
  $tok = [string]$left[$i]
  if ([string]::IsNullOrWhiteSpace($tok)) { continue }

  # No literal "--" and we see a bare word? That starts CMDS; shovel remainder.
  if (-not $foundCmdsStart -and $tok[0] -ne '-') {
    $CMDS += $left[$i..($left.Count-1)]
    break
  }

  $kv = Split-KeyEqualsValue $tok
  if ($kv) {
    switch ($kv.Key) {
      '--variant' { $VARIANT = $kv.Value; continue }
      '--version' { $VERSION_TAG = $kv.Value; continue }
      '--name'    { $CONTAINER_NAME = $kv.Value; continue }
      default     { $RUN_ARGS += $tok; continue }
    }
  }

  switch ($tok) {
    '-d'       { $DAEMON = $true; continue }
    '--daemon' { $DAEMON = $true; continue }
    '--pull'   { $DO_PULL = $true; continue }

    '--variant' {
      if ($i + 1 -ge $left.Count) { throw "--variant requires a value" }
      $i++; $VARIANT = [string]$left[$i]; continue
    }
    '--version' {
      if ($i + 1 -ge $left.Count) { throw "--version requires a value" }
      $i++; $VERSION_TAG = [string]$left[$i]; continue
    }
    '--name' {
      if ($i + 1 -ge $left.Count) { throw "--name requires a value" }
      $i++; $CONTAINER_NAME = [string]$left[$i]; continue
    }

    '-h'     { Show-Help; exit 0 }
    '--help' { Show-Help; exit 0 }

    default {
      # Unknown before CMDS → RUN_ARGS (+ possible value)
      $RUN_ARGS += $tok
      if ($tok.StartsWith('-') -and $i + 1 -lt $left.Count) {
        $peek = [string]$left[$i+1]
        if ($peek.Length -gt 0 -and $peek[0] -ne '-') {
          $i++; $RUN_ARGS += $peek
        }
      }
    }
  }
}

# ---------- Variant validation (ported from Bash) ----------
if (@('container','notebook','codeserver') -notcontains $VARIANT) {
  Write-Error "Error: unknown --variant '$VARIANT' (expected: container|notebook|codeserver)"
  exit 1
}

# Recompute derived values after option parsing (mirrors Bash)
$IMAGE_TAG  = "$VARIANT-$VERSION_TAG"
$IMAGE_NAME = "${IMAGE_REPO}:$IMAGE_TAG"
if (-not $CONTAINER_NAME -or $CONTAINER_NAME -eq '') { $CONTAINER_NAME = "$VARIANT-run" }


# # --- Optional: debug prints (uncomment to verify) ---
# Write-Host "DAEMON         = $DAEMON"
# Write-Host "DO_PULL        = $DO_PULL"
# Write-Host "VARIANT        = $VARIANT"
# Write-Host "VERSION_TAG    = $VERSION_TAG"
# Write-Host "CONTAINER_NAME = $CONTAINER_NAME"
# Write-Host "RUN_ARGS       = $($RUN_ARGS -join ' | ')"
# Write-Host "CMDS           = $($CMDS -join ' | ')"
# Write-Host "IMAGE_NAME     = $IMAGE_NAME"


# ---------- Docker helpers ----------
function Test-DockerImageExists([string]$name) {
  $null = & docker image inspect $name 2>$null
  return ($LASTEXITCODE -eq 0)
}
function Invoke-Docker([string[]]$argv) {
  & docker @argv
  exit $LASTEXITCODE
}

# ---------- Pull if requested or missing ----------
if ($DO_PULL -or -not (Test-DockerImageExists $IMAGE_NAME)) {
  Write-Host "Pulling image: $IMAGE_NAME"
  & docker pull $IMAGE_NAME
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: failed to pull '$IMAGE_NAME'."
    exit 1
  }
}

# Final availability check
if (-not (Test-DockerImageExists $IMAGE_NAME)) {
  Write-Error "Error: image '$IMAGE_NAME' not available locally. Try '--pull'."
  exit 1
}

# Clean up any previous container with the same name
$null = (& docker rm -f $CONTAINER_NAME) 2>$null

# TTY args like bash: default '-i', upgrade to '-it' if stdout is a TTY
$TTY_ARGS = @('-i')
if (-not [Console]::IsOutputRedirected) { $TTY_ARGS = @('-it') }

# Common docker run args
$PWD_PATH = (Get-Location).Path
$COMMON_ARGS = @(
  '--name', $CONTAINER_NAME
  '-e', "HOST_UID=$HOST_UID"
  '-e', "HOST_GID=$HOST_GID"
  "-e", "CHOWN_RECURSIVE=1"
  '-v', "${PWD_PATH}:$WORKSPACE"
  '-w', $WORKSPACE
)

if ($VARIANT -eq "notebook") {
    $COMMON_ARGS += @('-p', '8888:8888')
}
if ($VARIANT -eq "codeserver") {
    $COMMON_ARGS += @('-p', '8888:8888')
    $COMMON_ARGS += @('-p', '8080:8080')
}

# ---------- Run modes ----------
if ($DAEMON) {
  $SHELL_CMD = if ($VARIANT -eq "container") { 
      @($SHELL_NAME, '-lc', 'while true; do sleep 3600; done') 
  } else { 
      @() 
  }

  $argv = @('run', '-d') + $COMMON_ARGS + $RUN_ARGS + @($IMAGE_NAME) + $SHELL_CMD
  Invoke-Docker $argv
}
elseif ($CMDS.Count -eq 0) {
  $argv = @('run','--rm') + $TTY_ARGS + $COMMON_ARGS + $RUN_ARGS + @($IMAGE_NAME)
  Invoke-Docker $argv
}
else {
  $USER_CMD = ($CMDS -join ' ')
  $argv = @('run','--rm') + $TTY_ARGS + $COMMON_ARGS + $RUN_ARGS + @($IMAGE_NAME, $SHELL_NAME, '-lc', $USER_CMD)
  Invoke-Docker $argv
}
