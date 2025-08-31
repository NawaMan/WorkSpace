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

# Derived (initial; will recompute after parsing too)
$IMAGE_TAG      = if ($env:IMAGE_TAG)      { $env:IMAGE_TAG }      else { "$VARIANT-$VERSION_TAG" }
$IMAGE_NAME     = "${IMAGE_REPO}:$IMAGE_TAG"
$CONTAINER_NAME = if ($env:CONTAINER_NAME) { $env:CONTAINER_NAME } else { '' }

# IMG* envs (align with Bash semantics)
$IMGREPO = if ($env:IMGREPO) { $env:IMGREPO } else { $IMAGE_REPO }
$IMG_TAG = if ($env:IMG_TAG) { $env:IMG_TAG } else { "$VARIANT-$VERSION_TAG" }
$IMGNAME = if ($env:IMGNAME) { $env:IMGNAME } else { '' }

# Container env-file support
$CONTAINER_ENV_FILE = if ($env:CONTAINER_ENV_FILE) { $env:CONTAINER_ENV_FILE } else { '.env' }
$EXPLICIT_ENV_FILE  = $false   # set to $true when provided via CLI

# NEW: initialize ports to avoid strict-mode errors; config/CLI may set these later
$NOTEBOOK_PORT  = $null
$CODESERVER_PORT = $null

# NEW: workspace config file (launcher config) — default ./workspace.cfg or env
$WORKSPACE_CONFIG_FILE = if ($env:WORKSPACE_CONFIG_FILE) { $env:WORKSPACE_CONFIG_FILE } else { './workspace.cfg' }

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
$DRYRUN   = $false
$RUN_ARGS = @()
$CMDS     = @()

# Track CLI overrides so we can reapply after sourcing a file (preserve precedence)
$CLI_VARIANT = ''
$CLI_VERSION = ''
$CLI_CONTAINER = ''
$CLI_CONFIG_FILE = ''
$CLI_ENV_FILE = ''
$CLI_ENV_FILE_EXPLICIT = $false

# ---------- Config loader (CRLF tolerant; # comments; KEY=VALUE) ----------
function Import-WorkspaceConfig([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  # Read file as raw string, strip CR, split into lines
  $lines = (Get-Content -LiteralPath $path -Raw) -replace "`r", '' -split "`n"
  foreach ($line in $lines) {
    $trim = $line.Trim()
    if ($trim -eq '' -or $trim.StartsWith('#')) { continue }
    if ($trim -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') { continue }
    $key = $matches[1]
    $val = $matches[2].Trim()
    # strip surrounding single/double quotes if present
    if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
      $val = $val.Substring(1, $val.Length - 2)
    }
    switch ($key) {
      'IMGNAME'              { $script:IMGNAME = $val; continue }
      'IMGREPO'              { $script:IMGREPO = $val; continue }
      'IMG_TAG'              { $script:IMG_TAG = $val; continue }
      'VARIANT'              { $script:VARIANT = $val; continue }
      'VERSION'              { $script:VERSION_TAG = $val; continue }
      'CONTAINER'            { $script:CONTAINER_NAME = $val; continue }
      'HOST_UID'             { $script:HOST_UID = $val; continue }
      'HOST_GID'             { $script:HOST_GID = $val; continue }
      'NOTEBOOK_PORT'        { $script:NOTEBOOK_PORT = $val; continue }
      'CODESERVER_PORT'      { $script:CODESERVER_PORT = $val; continue }
      'CONTAINER_ENV_FILE'   { $script:CONTAINER_ENV_FILE = $val; continue }
      default { } # ignore unknown keys
    }
  }
}

# --------- Load default workspace config BEFORE parsing so CLI can override later ---------
if ($WORKSPACE_CONFIG_FILE -and (Test-Path -LiteralPath $WORKSPACE_CONFIG_FILE)) {
  Import-WorkspaceConfig -path $WORKSPACE_CONFIG_FILE
}

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
      --name    <name>    Container name        (default: <project-folder>)
      --config <path>     Launcher config to source (default: ./workspace.cfg or \$WORKSPACE_CONFIG_FILE)
      --env-file <path>   Pass file to 'docker run --env-file' (default: ./.env or \$CONTAINER_ENV_FILE)
      --dryrun            Print the docker run command and exit (no side effects)
  -h, --help              Show this help message

Notes:
  • Bind: . -> $WORKSPACE; Working dir: $WORKSPACE

Configuration keys (workspace.cfg):
  IMGNAME, IMGREPO, IMG_TAG, VARIANT, VERSION, CONTAINER,
  HOST_UID, HOST_GID, NOTEBOOK_PORT, CODESERVER_PORT, CONTAINER_ENV_FILE

Precedence (most → least):
  CLI > workspace.cfg > environment > built-in defaults
"@ | Write-Host
}

# ---------- Arg parsing ----------
function Normalize-Dashes([string]$s) {
  if ($null -eq $s) { return $s }
  return ($s -replace "[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]", "-")
}

$normArgs = @($args | ForEach-Object { Normalize-Dashes ([string]$_) })

function Split-KeyEqualsValue([string]$tok) {
  if ($tok -like '--*=*') {
    $p = $tok.Split('=', 2)
    return @{ Key = $p[0]; Value = $p[1] }
  }
  return $null
}

$sepIndex = if ($normArgs.Count -gt 0) { [Array]::IndexOf($normArgs, '--') } else { -1 }
$left = @()
if ($sepIndex -ge 0) {
  if ($sepIndex -gt 0) { $left = $normArgs[0..($sepIndex-1)] }
  if ($sepIndex + 1 -lt $normArgs.Count) { $CMDS += $normArgs[($sepIndex+1)..($normArgs.Count-1)] }
} else {
  $left = $normArgs
}
$foundCmdsStart = ($sepIndex -ge 0)

# Track CLI overrides for precedence
for ($i = 0; $i -lt $left.Count; $i++) {
  $tok = [string]$left[$i]
  if ([string]::IsNullOrWhiteSpace($tok)) { continue }

  if (-not $foundCmdsStart -and $tok[0] -ne '-') {
    $CMDS += $left[$i..($left.Count-1)]
    break
  }

  $kv = Split-KeyEqualsValue $tok
  if ($kv) {
    switch ($kv.Key) {
      '--variant'      { $VARIANT = $kv.Value; $CLI_VARIANT = $kv.Value; continue }
      '--version'      { $VERSION_TAG = $kv.Value; $CLI_VERSION = $kv.Value; continue }
      '--name'         { $CONTAINER_NAME = $kv.Value; $CLI_CONTAINER = $kv.Value; continue }
      '--config'       { $WORKSPACE_CONFIG_FILE = $kv.Value; $CLI_CONFIG_FILE = $kv.Value; continue }
      '--env-file'     { $CONTAINER_ENV_FILE = $kv.Value; $CLI_ENV_FILE = $kv.Value; $CLI_ENV_FILE_EXPLICIT = $true; $EXPLICIT_ENV_FILE = $true; continue }
      default          { $RUN_ARGS += $tok; continue }
    }
  }

  switch ($tok) {
    '-d'       { $DAEMON = $true; continue }
    '--daemon' { $DAEMON = $true; continue }
    '--pull'   { $DO_PULL = $true; continue }
    '--dryrun' { $DRYRUN  = $true; continue }

    '--variant' {
      if ($i + 1 -ge $left.Count) { throw "--variant requires a value" }
      $i++; $VARIANT = [string]$left[$i]; $CLI_VARIANT = $VARIANT; continue
    }
    '--version' {
      if ($i + 1 -ge $left.Count) { throw "--version requires a value" }
      $i++; $VERSION_TAG = [string]$left[$i]; $CLI_VERSION = $VERSION_TAG; continue
    }
    '--name' {
      if ($i + 1 -ge $left.Count) { throw "--name requires a value" }
      $i++; $CONTAINER_NAME = [string]$left[$i]; $CLI_CONTAINER = $CONTAINER_NAME; continue
    }
    '--config' {
      if ($i + 1 -ge $left.Count) { throw "--config requires a path" }
      $i++; $WORKSPACE_CONFIG_FILE = [string]$left[$i]; $CLI_CONFIG_FILE = $WORKSPACE_CONFIG_FILE; continue
    }
    '--env-file' {
      if ($i + 1 -ge $left.Count) { throw "--env-file requires a path" }
      $i++; $CONTAINER_ENV_FILE = [string]$left[$i]; $CLI_ENV_FILE = $CONTAINER_ENV_FILE; $CLI_ENV_FILE_EXPLICIT = $true; $EXPLICIT_ENV_FILE = $true; continue
    }

    '-h'     { Show-Help; exit 0 }
    '--help' { Show-Help; exit 0 }

    default {
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

# ---------- If --config specified, source that file and then reapply CLI overrides ----------
if ($CLI_CONFIG_FILE -and (Test-Path -LiteralPath $CLI_CONFIG_FILE)) {
  Import-WorkspaceConfig -path $CLI_CONFIG_FILE
  # Re-apply CLI overrides to preserve precedence
  if ($CLI_VARIANT)   { $VARIANT = $CLI_VARIANT }
  if ($CLI_VERSION)   { $VERSION_TAG = $CLI_VERSION }
  if ($CLI_CONTAINER) { $CONTAINER_NAME = $CLI_CONTAINER }
  if ($CLI_ENV_FILE_EXPLICIT) { $CONTAINER_ENV_FILE = $CLI_ENV_FILE; $EXPLICIT_ENV_FILE = $true }
}
elseif ($CLI_CONFIG_FILE -and -not (Test-Path -LiteralPath $CLI_CONFIG_FILE)) {
  Write-Warning "Warning: --config '$CLI_CONFIG_FILE' not found; continuing without it."
}

# ---------- Variant validation ----------
if (@('container','notebook','codeserver') -notcontains $VARIANT) {
  Write-Error "Error: unknown --variant '$VARIANT' (expected: container|notebook|codeserver)"
  exit 1
}

# ---------- Default container name ----------
function Get-DefaultContainerName {
  $proj = Split-Path -Leaf (Get-Location).Path
  if ([string]::IsNullOrWhiteSpace($proj)) { $proj = 'workspace' }
  $s = $proj.ToLowerInvariant()
  $s = ($s -replace '\s+', '-')           
  $s = ($s -replace '[^a-z0-9_.-]+', '-') 
  $s = $s.Trim('-')                        
  if ([string]::IsNullOrWhiteSpace($s)) { $s = 'workspace' }
  return $s
}

# ---------- Recompute derived values after parsing (align with Bash IMG* precedence) ----------
$IMG_TAG = if ($env:IMG_TAG) { $env:IMG_TAG } else { "$VARIANT-$VERSION_TAG" }
$IMGREPO = if ($env:IMGREPO) { $env:IMGREPO } else { $IMAGE_REPO }
if ($env:IMGNAME) { $IMGNAME = $env:IMGNAME } elseif (-not $IMGNAME) { $IMGNAME = '' }

if ($IMGNAME -and $IMGNAME.Trim().Length -gt 0) {
  if ($IMGNAME -match '\s') {
    Write-Error "Error: invalid image reference IMGNAME='$IMGNAME' (contains whitespace)."
    exit 1
  }
  $IMAGE_NAME = $IMGNAME
} else {
  $IMAGE_TAG  = $IMG_TAG
  $IMAGE_NAME = "${IMGREPO}:$IMG_TAG"
}

if (-not $CONTAINER_NAME -or $CONTAINER_NAME -eq '') {
  $CONTAINER_NAME = Get-DefaultContainerName
}

# ---------- Ports (config > env > default) ----------
if (-not $NOTEBOOK_PORT)   { $NOTEBOOK_PORT   = if ($env:NOTEBOOK_PORT)   { $env:NOTEBOOK_PORT }   else { '8888' } }
if (-not $CODESERVER_PORT) { $CODESERVER_PORT = if ($env:CODESERVER_PORT) { $env:CODESERVER_PORT } else { '8080' } }

# ---------- TTY & common docker args ----------
$TTY_ARGS = @('-i')
if (-not [Console]::IsOutputRedirected) { $TTY_ARGS = @('-it') }

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
    $COMMON_ARGS += @('-p', "$NOTEBOOK_PORT:8888")
}
if ($VARIANT -eq "codeserver") {
    $COMMON_ARGS += @('-p', "$NOTEBOOK_PORT:8888")
    $COMMON_ARGS += @('-p', "$CODESERVER_PORT:8080")
}

# Honor --env-file (exists or explicitly provided)
if ($CONTAINER_ENV_FILE -and $CONTAINER_ENV_FILE -ne '') {
  if (Test-Path -LiteralPath $CONTAINER_ENV_FILE) {
    $COMMON_ARGS += @('--env-file', $CONTAINER_ENV_FILE)
  }
  elseif ($EXPLICIT_ENV_FILE) {
    $COMMON_ARGS += @('--env-file', $CONTAINER_ENV_FILE)
  }
}

# ---------- Helper for dryrun ----------
function Print-Cmd([string[]]$argv) {
  $quoted = $argv | ForEach-Object {
    if ($_ -match '^[A-Za-z0-9_./:-]+$') { $_ } else { "'$($_ -replace "'", "''")'" }
  }
  Write-Output ("docker " + ($quoted -join ' '))
}

# ---------- Run modes ----------
if ($DAEMON) {
  $SHELL_CMD = if ($VARIANT -eq "container") { 
      @($SHELL_NAME, '-lc', 'while true; do sleep 3600; done') 
  } else { @() }

  $argv = @('run', '-d') + $COMMON_ARGS + $RUN_ARGS + @($IMAGE_NAME) + $SHELL_CMD
  if ($DRYRUN) { Print-Cmd $argv; exit 0 }
  & docker @argv; exit $LASTEXITCODE
}
elseif ($CMDS.Count -eq 0) {
  $argv = @('run','--rm') + $TTY_ARGS + $COMMON_ARGS + $RUN_ARGS + @($IMAGE_NAME)
  if ($DRYRUN) { Print-Cmd $argv; exit 0 }
  & docker @argv; exit $LASTEXITCODE
}
else {
  $USER_CMD = ($CMDS -join ' ')
  $argv = @('run','--rm') + $TTY_ARGS + $COMMON_ARGS + $RUN_ARGS + @($IMAGE_NAME, $SHELL_NAME, '-lc', $USER_CMD)
  if ($DRYRUN) { Print-Cmd $argv; exit 0 }
  & docker @argv; exit $LASTEXITCODE
}
