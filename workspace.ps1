#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
  PowerShell port of "workspace.sh" (matches --daemon + foreground behavior).

  Behavior:
    • No command → rely on image CMD
        - Foreground: prints tips, uses --rm; allocates -it only if both stdin & stdout are TTY
        - Daemon (--daemon / -d): prints tips & container id; uses -d (no TTY)
    • With command (after --): run that command and exit
    • --dryrun: print the docker command and exit (no side effects)

  Files:
    - workspace.env           (launcher config; key=value)
    - .env                    (container env; passed as --env-file)
    - workspace-docker.args   (extra docker run args; one line = tokens, quotes supported)

  Precedence: CLI > workspace.env > environment variables > defaults
#>

# ---------- Strict mode ----------
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------- Defaults ----------
$IMGREPO_DEFAULT = 'nawaman/workspace'
$VARIANT_DEFAULT = 'container'
$VERSION_DEFAULT = 'latest'
$WORKSPACE       = '/home/coder/workspace'
$SHELL_NAME      = 'bash'

# ---------- Base from env (pre-config; CLI & config may override) ----------
$IMGREPO  = if ($env:IMGREPO)  { $env:IMGREPO }  else { $IMGREPO_DEFAULT }
$VARIANT  = if ($env:VARIANT)  { $env:VARIANT }  else { $VARIANT_DEFAULT }
$VERSION  = if ($env:VERSION)  { $env:VERSION }  else { $VERSION_DEFAULT }
$IMG_TAG  = if ($env:IMG_TAG)  { $env:IMG_TAG }  else { "$VARIANT-$VERSION" }
$IMGNAME  = if ($env:IMGNAME)  { $env:IMGNAME }  else { "${IMGREPO}:${IMG_TAG}" }
$CONTAINER = if ($env:CONTAINER) { $env:CONTAINER } else { "" }

# Host uid/gid (Linux/WSL)
function Get-IdOrDefault([string]$switch, [string]$fallback) {
  try { $out = (& id $switch) 2>$null; if ($LASTEXITCODE -eq 0 -and $out) { return $out.Trim() } } catch {}
  return $fallback
}
$HOST_UID = if ($env:HOST_UID) { $env:HOST_UID } else { Get-IdOrDefault '-u' '1000' }
$HOST_GID = if ($env:HOST_GID) { $env:HOST_GID } else { Get-IdOrDefault '-g' '1000' }

# ---------- Flags & collections ----------
$DAEMON  = $false
$DO_PULL = $false
$DRYRUN  = $false
$RUN_ARGS = @()
$CMDS     = @()

# ---------- Files (with env defaults) ----------
$WORKSPACE_CONFIG_FILE = if ($env:WORKSPACE_CONFIG_FILE) { $env:WORKSPACE_CONFIG_FILE } else { './workspace.env' }  # launcher config (key=value)
$CONTAINER_ENV_FILE    = if ($env:CONTAINER_ENV_FILE)    { $env:CONTAINER_ENV_FILE }    else { '.env' }             # --env-file
$DOCKER_ARGS_FILE      = if ($env:DOCKER_ARGS_FILE)      { $env:DOCKER_ARGS_FILE }      else { './workspace-docker.args' }

# Track CLI overrides (to re-apply after sourcing config)
$CLI_VARIANT = ''
$CLI_VERSION = ''
$CLI_CONTAINER = ''
$CLI_CONFIG_FILE = ''
$CLI_ENV_FILE = ''
$CLI_ENV_FILE_EXPLICIT = $false
$CLI_DOCKER_ARGS_FILE = ''

# Ports (may come from config/env)
$WORKSPACE_PORT = $null

# For docker-args file
$RUN_ARGS_FROM_FILE = @()

# ---------- Help ----------
function Show-Help {
@"
Starting a workspace container.
More information: https://github.com/NawaMan/WorkSpace

Usage:
  $(Split-Path -Leaf $PSCommandPath) [OPTIONS] [RUN_ARGS]                 # run workspace (foreground)
  $(Split-Path -Leaf $PSCommandPath) [OPTIONS] [RUN_ARGS] -- <command...> # run a command then exit
  $(Split-Path -Leaf $PSCommandPath) [OPTIONS] [RUN_ARGS] --daemon        # run container detached

Options:
  -d, --daemon              Run container detached (background)
      --pull                Pull/refresh the image from registry (also pulls if image missing)
      --variant <name>      Variant prefix        (default: $VARIANT_DEFAULT)
      --version <tag>       Version suffix        (default: $VERSION_DEFAULT)
      --name <name>         Container name        (default: <project-folder>)
      --config <path>       Launcher config to read (default: ./workspace.env or `$WORKSPACE_CONFIG_FILE)
      --env-file <path>     Container env file passed to 'docker run --env-file' (default: ./.env or `$CONTAINER_ENV_FILE)
      --docker-args <path>  File of extra 'docker run' args (default: ./workspace-docker.args or `$DOCKER_ARGS_FILE)
      --dryrun              Print the docker run command and exit (no side effects)
  -h, --help                Show this help message

Notes:
  • Bind: . -> $WORKSPACE; Working dir: $WORKSPACE
  • workspace.env keys: IMGNAME, IMGREPO, IMG_TAG, VARIANT, VERSION, CONTAINER,
      HOST_UID, HOST_GID, WORKSPACE_PORT, CONTAINER_ENV_FILE
  • workspace-docker.args: one directive per line (quotes ok), e.g.:
      -p 127.0.0.1:9000:9000
      -v "/host/path:/container/path"
      --shm-size 2g
      --add-host "minio.local:127.0.0.1"

Precedence (most → least):
  CLI > workspace.env > environment variables > built-in defaults
"@ | Write-Host
}

# ---------- Config loader (key=value; CRLF tolerant; ignores comments) ----------
function Import-LauncherConfig([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  $lines = (Get-Content -LiteralPath $path -Raw) -replace "`r", '' -split "`n"
  foreach ($line in $lines) {
    $trim = $line.Trim()
    if ($trim -eq '' -or $trim.StartsWith('#')) { continue }
    if ($trim -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') { continue }
    $key = $matches[1]; $val = $matches[2].Trim()
    if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
      $val = $val.Substring(1, $val.Length - 2)
    }
    switch ($key) {
      'IMGNAME'            { $script:IMGNAME = $val; continue }
      'IMGREPO'            { $script:IMGREPO = $val; continue }
      'IMG_TAG'            { $script:IMG_TAG = $val; continue }
      'VARIANT'            { $script:VARIANT = $val; continue }
      'VERSION'            { $script:VERSION = $val; continue }
      'CONTAINER'          { $script:CONTAINER = $val; continue }
      'HOST_UID'           { $script:HOST_UID = $val; continue }
      'HOST_GID'           { $script:HOST_GID = $val; continue }
      'WORKSPACE_PORT'     { $script:WORKSPACE_PORT = $val; continue }
      'CONTAINER_ENV_FILE' { $script:CONTAINER_ENV_FILE = $val; continue }
      default { }
    }
  }
}

# --------- Load default workspace.env BEFORE CLI parse (so CLI can override later) ---------
if ($WORKSPACE_CONFIG_FILE -and (Test-Path -LiteralPath $WORKSPACE_CONFIG_FILE)) {
  Import-LauncherConfig $WORKSPACE_CONFIG_FILE
}

# ---------- Arg parsing ----------
function Normalize-Dashes([string]$s) { if ($null -eq $s) { return $s }; return ($s -replace "[\u2010-\u2015\u2212]", "-") }
$normArgs = @($args | ForEach-Object { Normalize-Dashes ([string]$_) })

$sepIndex = if ($normArgs.Count -gt 0) { [Array]::IndexOf($normArgs, '--') } else { -1 }
$left = @()
if ($sepIndex -ge 0) {
  if ($sepIndex -gt 0) { $left = $normArgs[0..($sepIndex-1)] }
  if ($sepIndex + 1 -lt $normArgs.Count) { $CMDS += $normArgs[($sepIndex+1)..($normArgs.Count-1)] }
} else { $left = $normArgs }
$foundCmdsStart = ($sepIndex -ge 0)

for ($i = 0; $i -lt $left.Count; $i++) {
  $tok = [string]$left[$i]
  if ([string]::IsNullOrWhiteSpace($tok)) { continue }
  if (-not $foundCmdsStart -and $tok[0] -ne '-') { $CMDS += $left[$i..($left.Count-1)]; break }

  switch ($tok) {
    '-d'           { $DAEMON = $true; continue }
    '--daemon'     { $DAEMON = $true; continue }
    '--pull'       { $DO_PULL = $true; continue }
    '--dryrun'     { $DRYRUN = $true; continue }

    '--variant'    { $i++; $CLI_VARIANT   = [string]$left[$i]; continue }
    '--version'    { $i++; $CLI_VERSION   = [string]$left[$i]; continue }
    '--name'       { $i++; $CLI_CONTAINER = [string]$left[$i]; continue }
    '--config'     { $i++; $CLI_CONFIG_FILE = [string]$left[$i]; continue }
    '--env-file'   { $i++; $CLI_ENV_FILE = [string]$left[$i]; $CLI_ENV_FILE_EXPLICIT = $true; continue }
    '--docker-args'{ $i++; $CLI_DOCKER_ARGS_FILE = [string]$left[$i]; continue }

    '-h'     { Show-Help; exit 0 }
    '--help' { Show-Help; exit 0 }

    default { $RUN_ARGS += $tok }
  }
}

# ---------- Apply config from --config (then reapply CLI overrides for precedence) ----------
if ($CLI_CONFIG_FILE -and (Test-Path -LiteralPath $CLI_CONFIG_FILE)) {
  Import-LauncherConfig $CLI_CONFIG_FILE
} elseif ($CLI_CONFIG_FILE -and -not (Test-Path -LiteralPath $CLI_CONFIG_FILE)) {
  Write-Warning "Warning: --config '$CLI_CONFIG_FILE' not found; continuing without it."
}

# Apply CLI overrides last
if ($CLI_VARIANT)   { $VARIANT   = $CLI_VARIANT }
if ($CLI_VERSION)   { $VERSION   = $CLI_VERSION }
if ($CLI_CONTAINER) { $CONTAINER = $CLI_CONTAINER }
if ($CLI_ENV_FILE_EXPLICIT) { $CONTAINER_ENV_FILE = $CLI_ENV_FILE }
if ($CLI_DOCKER_ARGS_FILE)  { $DOCKER_ARGS_FILE   = $CLI_DOCKER_ARGS_FILE }

# ---------- Validate ----------
if (@('container','notebook','codeserver') -notcontains $VARIANT) {
  Write-Error "Error: unknown --variant '$VARIANT' (expected: container|notebook|codeserver)"; exit 1
}

# ---------- Recompute image selection (after overrides) ----------
$IMG_TAG = if ($env:IMG_TAG) { $env:IMG_TAG } else { "$VARIANT-$VERSION" }
$IMGNAME = if ($env:IMGNAME) { $env:IMGNAME } else { "${IMGREPO}:${IMG_TAG}" }

# ---------- Default container name ----------
if (-not $CONTAINER -or $CONTAINER -eq '') {
  $proj = Split-Path -Leaf (Get-Location).Path
  $proj_sanitized = ($proj.ToLower() -replace '[^a-z0-9_.-]+','-').Trim('-')
  if (-not $proj_sanitized) { $proj_sanitized = 'workspace' }
  $CONTAINER = $proj_sanitized
}

# Ports: config/env or defaults
if (-not $WORKSPACE_PORT) { $WORKSPACE_PORT = if ($env:WORKSPACE_PORT) { $env:WORKSPACE_PORT } else { '10000' } }

# ---------- Docker-args file loader ----------
function Split-ArgsLine([string]$line) {
  if ([string]::IsNullOrWhiteSpace($line)) { return @() }
  $pattern = '(?<!\S)("([^"]*)"|''([^'']*)''|\S+)'
  $tokens = [System.Text.RegularExpressions.Regex]::Matches($line, $pattern) |
    ForEach-Object {
      $t = $_.Value
      if (($t.StartsWith('"') -and $t.EndsWith('"')) -or ($t.StartsWith("'") -and $t.EndsWith("'"))) { $t = $t.Substring(1, $t.Length - 2) }
      $t
    }
  return ,$tokens
}
function Import-DockerArgs([string]$path) {
  if (-not $path -or -not (Test-Path -LiteralPath $path)) { return }
  $lines = (Get-Content -LiteralPath $path -Raw) -replace "`r", '' -split "`n"
  foreach ($line in $lines) {
    $trim = $line.Trim()
    if ($trim -eq '' -or $trim.StartsWith('#')) { continue }
    $argsFromLine = Split-ArgsLine $trim
    if ($argsFromLine.Count -gt 0) { $script:RUN_ARGS_FROM_FILE += $argsFromLine }
  }
}
Import-DockerArgs $DOCKER_ARGS_FILE
if ($RUN_ARGS_FROM_FILE.Count -gt 0) { $RUN_ARGS = @($RUN_ARGS_FROM_FILE + $RUN_ARGS) }

# ---------- Docker helpers ----------
function Test-DockerImageExists([string]$name) { $null = & docker image inspect $name 2>$null; return ($LASTEXITCODE -eq 0) }
function Print-Cmd([string[]]$argv) {
  $quoted = $argv | ForEach-Object { if ($_ -match '^[A-Za-z0-9_./:-]+$') { $_ } else { "'$($_ -replace "'", "''")'" } }
  Write-Output ("docker " + ($quoted -join ' '))
}
function Invoke-Docker([string[]]$argv) {
  if ($DRYRUN) { Print-Cmd $argv; exit 0 } else { & docker @argv; exit $LASTEXITCODE }
}

# ---------- Skip docker checks/cleanup on --dryrun ----------
if (-not $DRYRUN) {
  if ($DO_PULL -or -not (Test-DockerImageExists $IMGNAME)) {
    Write-Host "Pulling image: $IMGNAME"
    & docker pull $IMGNAME
    if ($LASTEXITCODE -ne 0) { Write-Error "Error: failed to pull '$IMGNAME'."; exit 1 }
  }
  if (-not (Test-DockerImageExists $IMGNAME)) {
    Write-Error "Error: image '$IMGNAME' not available locally. Try '--pull'."; exit 1
  }
  # Clean up previous container
  $null = (& docker rm -f $CONTAINER) 2>$null
}

# ---------- Build common pieces ----------
# TTY: only if both stdin and stdout are TTY
$TTY_ARGS = @('-i')
if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) { $TTY_ARGS = @('-it') }

$PWD_PATH = (Get-Location).Path
$BASE_ARGS = @(
  '--name', $CONTAINER
  '-e', "HOST_UID=$HOST_UID"
  '-e', "HOST_GID=$HOST_GID"
  '-v', "${PWD_PATH}:$WORKSPACE"
  '-w', $WORKSPACE
  '-p', "${WORKSPACE_PORT}:10000"
)

# Container env-file: include if exists OR was explicitly provided
if ($CONTAINER_ENV_FILE) {
  if (Test-Path -LiteralPath $CONTAINER_ENV_FILE) {
    $BASE_ARGS += @('--env-file', $CONTAINER_ENV_FILE)
  } elseif ($CLI_ENV_FILE_EXPLICIT) {
    $BASE_ARGS += @('--env-file', $CONTAINER_ENV_FILE)
  }
}

# ---------- Run modes ----------
if ($DAEMON) {
  Write-Host "📦 Running workspace in daemon mode."
  Write-Host "👉 Stop with '$(Split-Path -Leaf $PSCommandPath) -- exit'. The container will be removed when stopped."
  Write-Host "👉 Visit 'http://localhost:$WORKSPACE_PORT'"
  Write-Host "👉 To open an interactive shell instead: $(Split-Path -Leaf $PSCommandPath) -- bash"
  # -d, no TTY
  $argv = @('run','-d') + $BASE_ARGS + $RUN_ARGS + @($IMGNAME)
  Invoke-Docker $argv
}
elseif ($CMDS.Count -eq 0) {
  Write-Host "📦 Running workspace in foreground."
  Write-Host "👉 Stop with Ctrl+C. The container will be removed (--rm) when it stops."
  Write-Host "👉 To open an interactive shell instead: '$(Split-Path -Leaf $PSCommandPath) -- bash'"
  # --rm + TTY (when appropriate), rely on image CMD
  $argv = @('run','--rm') + $TTY_ARGS + $BASE_ARGS + $RUN_ARGS + @($IMGNAME)
  Invoke-Docker $argv
}
else {
  # Foreground with explicit command
  $USER_CMD = ($CMDS -join ' ')
  $argv = @('run','--rm') + $TTY_ARGS + $BASE_ARGS + $RUN_ARGS + @($IMGNAME, $SHELL_NAME, '-lc', $USER_CMD)
  Invoke-Docker $argv
}
