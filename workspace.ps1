#requires -Version 7.0
# Rough equivalents of: set -euo pipefail
$ErrorActionPreference = 'Stop'                      # like `set -e`
Set-StrictMode -Version Latest                       # like `-u`
$PSNativeCommandUseErrorActionPreference = $true     # native commands respect EA

#========== CONSTANTS ============
# basename "$0"
$SCRIPT_NAME   = if ($PSCommandPath) { Split-Path -Leaf $PSCommandPath } else { 'interactive' }
$PREBUILD_REPO = 'nawaman/workspace'
$FILE_NOT_USED = 'none'

#========== HELPERS ============
# Bash-style truthy check: "true", "1", "yes", "on" → $true
function _is_true([object]$v) {
  if ($null -eq $v) { return $false }
  if ($v -is [bool]) { return $v }
  $s = "$v".Trim().ToLowerInvariant()
  return $s -in @('1','true','yes','y','on')
}

function abs_path([Parameter(Mandatory)][string]$Path) {
  try {
    # Resolve-Path handles symlinks when the target exists
    (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
  } catch {
    # Fallback similar to: (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd)" "$(basename "$1")")
    $dir  = Split-Path -Parent $Path
    if ([string]::IsNullOrEmpty($dir)) { $dir = '.' }
    $base = Split-Path -Leaf   $Path
    $fullDir = [System.IO.Path]::GetFullPath($dir)
    [System.IO.Path]::Combine($fullDir, $base)
  }
}

function print_cmd {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
  $out = foreach ($a in $Args) {
    if ($a -match '^[A-Za-z0-9_./:-]+$') { "$a " }
    else {
      # POSIX-ish single-quote escaping for display parity
      $q = $a -replace "'", "'\''"
      "'$q' "
    }
  }
  ($out -join '').TrimEnd()
}

function print_args {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
  ($Args | ForEach-Object { ' "' + $_ + '"' }) -join '' | Write-Output
}

function project_name([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { $Path = $PWD.Path }
  $WS_PATH = abs_path $Path
  $name = Split-Path -Leaf $WS_PATH
  # to lower; spaces → dashes; strip invalid → '-'; trim leading/trailing dashes
  $name = $name.ToLowerInvariant() -replace ' ', '-' -replace '[^a-z0-9_.-]+','-'
  $name = $name -replace '^-+','' -replace '-+$',''
  if ([string]::IsNullOrEmpty($name)) { $name = 'workspace' }
  $name
}

function docker_build {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
  if (_is_true $script:DRYRUN -or _is_true $script:VERBOSE) {
    print_cmd docker build @Args | Write-Output
  }
  if (-not (_is_true $script:DRYRUN)) {
    & docker build @Args
    return $LASTEXITCODE  # propagate native exit code
  }
}

function docker_run {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
  if (_is_true $script:DRYRUN -or _is_true $script:VERBOSE) {
    print_cmd docker run @Args | Write-Output
    Write-Host ''
  }
  if (-not (_is_true $script:DRYRUN)) {
    & docker run @Args
    return $LASTEXITCODE  # propagate native exit code
  }
}

#=========== DEFAULTS ============
# Respect pre-set vars first (if you dot-source), then env, else hard defaults
if (-not (Get-Variable DRYRUN  -Scope Script -ErrorAction SilentlyContinue)) { $script:DRYRUN  = $env:DRYRUN  }
if ($null -eq $script:DRYRUN  -or $script:DRYRUN  -eq '') { $script:DRYRUN  = $false }

if (-not (Get-Variable VERBOSE -Scope Script -ErrorAction SilentlyContinue)) { $script:VERBOSE = $env:VERBOSE }
if ($null -eq $script:VERBOSE -or $script:VERBOSE -eq '') { $script:VERBOSE = $false }

$script:CONFIG_FILE = if ($env:CONFIG_FILE) { $env:CONFIG_FILE } else { './ws-config.env' }

# UID/GID best-effort (Linux/mac). If `id` is missing (Windows), they may be $null.
$script:HOST_UID = if ($env:HOST_UID) { $env:HOST_UID } else { try { (& id -u 2>$null) } catch { $null } }
$script:HOST_GID = if ($env:HOST_GID) { $env:HOST_GID } else { try { (& id -g 2>$null) } catch { $null } }

$script:WORKSPACE_PATH = if ($env:WORKSPACE_PATH) { $env:WORKSPACE_PATH } else { $PWD.Path }
$script:PROJECT_NAME   = project_name $script:WORKSPACE_PATH

$script:DOCKER_FILE = $env:DOCKER_FILE
$script:IMAGE_NAME  = $env:IMAGE_NAME
$script:VARIANT     = if ($env:VARIANT) { $env:VARIANT } else { 'container' }
$script:VERSION     = if ($env:VERSION) { $env:VERSION } else { 'latest' }

$script:DO_PULL = if ($env:DO_PULL) { $env:DO_PULL } else { $false }

$script:CONTAINER_NAME = if ($env:CONTAINER_NAME) { $env:CONTAINER_NAME } else { $script:PROJECT_NAME }
$script:DAEMON         = if ($env:DAEMON) { $env:DAEMON } else { $false }
$script:WORKSPACE_PORT = if ($env:WORKSPACE_PORT) { [int]$env:WORKSPACE_PORT } else { 10000 }

$script:DOCKER_BUILD_ARGS_FILE = $env:DOCKER_BUILD_ARGS_FILE
$script:DOCKER_RUN_ARGS_FILE   = $env:DOCKER_RUN_ARGS_FILE

$script:CONTAINER_ENV_FILE = $env:CONTAINER_ENV_FILE

$script:BUILD_ARGS = @()
$script:RUN_ARGS   = @()
$script:CMDS       = @()

#============ CONFIGS =============

# helper: import simple KEY=VALUE .env files (supports optional leading "export ")
function Import-EnvFile {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Config file not found: '$Path'"
  }
  $lines = Get-Content -LiteralPath $Path
  foreach ($line in $lines) {
    if ($line -match '^\s*(#|$)') { continue } # skip comments/blank
    $m = [regex]::Match($line, '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$')
    if (-not $m.Success) { continue }
    $key = $m.Groups[1].Value
    $val = $m.Groups[2].Value.Trim()

    # Strip surrounding single or double quotes if present
    if ($val.Length -ge 2 -and
        (($val.StartsWith('"') -and $val.EndsWith('"')) -or
         ($val.StartsWith("'") -and $val.EndsWith("'")))) {
      $val = $val.Substring(1, $val.Length - 2)
    }

    # ✅ Set env var with a dynamic name
    Set-Item -Path ("Env:{0}" -f $key) -Value $val

    # Also mirror into script scope (≈ `set -a` + `source`)
    try { Set-Variable -Scope Script -Name $key -Value $val -Force } catch { }
  }
}

# Capture raw args like bash's ARGS=("$@")
$script:ARGS = @($args)

# --- NEW: Robustly split user command after `--` like bash ---
$dd = [Array]::IndexOf($script:ARGS, '--')
if ($dd -ge 0) {
  if ($dd + 1 -lt $script:ARGS.Count) {
    $script:CMDS = @($script:ARGS[($dd + 1)..($script:ARGS.Count - 1)])
  } else {
    $script:CMDS = @()
  }
  if ($dd -gt 0) {
    $script:ARGS = @($script:ARGS[0..($dd - 1)])
  } else {
    $script:ARGS = @()
  }
}

function Require-Arg {
  param(
    [Parameter(Mandatory)] [string] $Opt,
    [string] $Val
  )
  if ([string]::IsNullOrEmpty($Val) -or ($Val -match '^--')) {
    Write-Error "Error: $Opt requires a value"
    exit 1
  }
}

$SET_CONFIG_FILE = $false

# Iterate like the bash loop and skip consumed values by bumping $i
for ($i = 0; $i -lt $script:ARGS.Count; $i++) {
  $arg = $script:ARGS[$i]
  switch ($arg) {
    '--verbose' {
      $script:VERBOSE = $true
      continue
    }

    '--config' {
      $next = if ($i + 1 -lt $script:ARGS.Count) { $script:ARGS[$i + 1] } else { $null }
      Require-Arg -Opt '--config' -Val $next
      $script:CONFIG_FILE = $next
      $SET_CONFIG_FILE = $true
      $i++  # consume the value
      continue
    }

    '--workspace' {
      $next = if ($i + 1 -lt $script:ARGS.Count) { $script:ARGS[$i + 1] } else { $null }
      Require-Arg -Opt '--workspace' -Val $next
      $script:WORKSPACE_PATH = $next
      $i++  # consume the value
      continue
    }

    '--dockerfile' {
      $next = if ($i + 1 -lt $script:ARGS.Count) { $script:ARGS[$i + 1] } else { $null }
      Require-Arg -Opt '--dockerfile' -Val $next
      $script:DOCKER_FILE = $next
      $i++  # consume the value
      continue
    }
  }
}

# Handle the config file logic (≈ `set -a` + `source`)
if ($SET_CONFIG_FILE -or (Test-Path -LiteralPath $script:CONFIG_FILE -PathType Leaf)) {
  if (-not (Test-Path -LiteralPath $script:CONFIG_FILE -PathType Leaf)) {
    Write-Error "Error: --config requires a file path"
    Write-Error "     : '$($script:CONFIG_FILE)' not found."
    exit 1
  }
  if ($script:VERBOSE) {
    Write-Host "Sourcing config file: '$($script:CONFIG_FILE)'"
  }
  # Import env assignments from the file (≈ `set -a` + `source`)
  Import-EnvFile -Path $script:CONFIG_FILE
}

#-- Determine the IMAGE_NAME --------------------
$script:LOCAL_BUILD = $false
$script:IMAGE_MODE  = 'PRE-BUILD'

if ([string]::IsNullOrEmpty($script:IMAGE_NAME)) {
  # Normalize the path to file ...
  if ($script:DOCKER_FILE -and
      (Test-Path -LiteralPath $script:DOCKER_FILE -PathType Container) -and
      (Test-Path -LiteralPath (Join-Path $script:DOCKER_FILE 'Dockerfile') -PathType Leaf)) {
    $script:DOCKER_FILE = Join-Path $script:DOCKER_FILE 'Dockerfile'
  }
  elseif (([string]::IsNullOrEmpty($script:DOCKER_FILE)) -and
          (Test-Path -LiteralPath (Join-Path $script:WORKSPACE_PATH 'Dockerfile') -PathType Leaf)) {
    $script:DOCKER_FILE = Join-Path $script:WORKSPACE_PATH 'Dockerfile'
  }

  # If DOCKER_FILE is given at this point, it is expected to be a file.
  if (-not [string]::IsNullOrEmpty($script:DOCKER_FILE)) {
    if (-not (Test-Path -LiteralPath $script:DOCKER_FILE -PathType Leaf)) {
      Write-Error "DOCKER_FILE ($script:DOCKER_FILE) is not a file."
      exit 1
    }
    $script:LOCAL_BUILD = $true
    $script:IMAGE_MODE  = 'LOCAL-BUILD'
  }
}
else {
  $script:IMAGE_MODE = 'CUSTOM-BUILD'
}

#========== ARGUMENTS ============

# Split one line like bash word-splitting with quotes preserved
function Split-ArgsLine([Parameter(Mandatory)][string]$Line) {
  $pattern = '("([^"\\]|\\.)*"|' + "'([^'\\]|\\.)*'" + '|[^ \t]+)'
  $matches = [regex]::Matches($Line, $pattern)
  $out = @()
  foreach ($m in $matches) {
    $tok = $m.Value
    if ($tok.StartsWith('"') -and $tok.EndsWith('"')) {
      $tok = $tok.Substring(1, $tok.Length - 2)
      # unescape \" and \\ inside double quotes
      $tok = $tok -replace '\\(["\\])', '$1'
    }
    elseif ($tok.StartsWith("'") -and $tok.EndsWith("'")) {
      # single quotes: take literal contents
      $tok = $tok.Substring(1, $tok.Length - 2)
    }
    else {
      # basic backslash unescape for \", \\
      $tok = $tok -replace '\\(["\\])', '$1'
    }
    $out += $tok
  }
  ,$out
}

# Usage:
#   Load-ArgsFile path/to/file       RUN_ARGS
#   Load-ArgsFile path/to/other_file BUILD_ARGS
function Load-ArgsFile {
  param(
    [string]$Path,  # not Mandatory
    [Parameter(Mandatory)][ValidateSet('BUILD_ARGS','RUN_ARGS')][string]$Target
  )
  if ([string]::IsNullOrEmpty($Path) -or $Path -eq $script:FILE_NOT_USED) { return }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Error: '$Path' is not a file"
  }

  $lines = Get-Content -LiteralPath $Path
  foreach ($raw in $lines) {
    $line = $raw.TrimEnd("`r")
    if ($line -match '^\s*$') { continue }   # blank
    if ($line -match '^\s*#') { continue }   # comment
    $tokens = Split-ArgsLine -Line $line
    if (-not $tokens) { continue }

    $arr = Get-Variable -Scope Script -Name $Target -ValueOnly
    $arr += $tokens
    Set-Variable -Scope Script -Name $Target -Value $arr -Force
  }
}

# If VAR has no value and default file exists, use the default.
if ([string]::IsNullOrEmpty($script:DOCKER_BUILD_ARGS_FILE) -and
    (Test-Path -LiteralPath (Join-Path $script:WORKSPACE_PATH 'ws-docker-build.args') -PathType Leaf)) {
  $script:DOCKER_BUILD_ARGS_FILE = Join-Path $script:WORKSPACE_PATH 'ws-docker-build.args'
}
if ([string]::IsNullOrEmpty($script:DOCKER_RUN_ARGS_FILE) -and
    (Test-Path -LiteralPath (Join-Path $script:WORKSPACE_PATH 'ws-docker-run.args') -PathType Leaf)) {
  $script:DOCKER_RUN_ARGS_FILE = Join-Path $script:WORKSPACE_PATH 'ws-docker-run.args'
}

Load-ArgsFile -Path $script:DOCKER_BUILD_ARGS_FILE -Target 'BUILD_ARGS'
Load-ArgsFile -Path $script:DOCKER_RUN_ARGS_FILE   -Target 'RUN_ARGS'

#========== PARAMETERS ============

$parsing_cmds = $false
$i = 0
while ($i -lt $script:ARGS.Count) {
  if ($parsing_cmds) {
    $script:CMDS += $script:ARGS[$i]
    $i++
    continue
  }

  $arg = $script:ARGS[$i]
  switch ($arg) {
    '--dryrun'  { $script:DRYRUN  = $true;  $i++; continue }
    '--verbose' { $script:VERBOSE = $true;  $i++; continue }
    '--pull'    { $script:DO_PULL = $true;  $i++; continue }
    '--daemon'  { $script:DAEMON  = $true;  $i++; continue }
    '--help'    {
      if (Get-Command Show-Help -ErrorAction SilentlyContinue) { Show-Help } else { Write-Host 'Help not implemented.' }
      exit 0
    }

    # General
    '--config' {
      if ($i + 1 -lt $script:ARGS.Count -and -not [string]::IsNullOrEmpty($script:ARGS[$i+1])) {
        $script:CONFIG_FILE = $script:ARGS[$i+1]; $i += 2; continue
      } else {
        Write-Error 'Error: --config requires a path'; exit 1
      }
    }
    '--workspace' {
      if ($i + 1 -lt $script:ARGS.Count -and -not [string]::IsNullOrEmpty($script:ARGS[$i+1])) {
        $script:WORKSPACE_PATH = $script:ARGS[$i+1]; $i += 2; continue
      } else {
        Write-Error 'Error: --workspace requires a path'; exit 1
      }
    }

    # Image selection
    '--image' {
      if ($i + 1 -lt $script:ARGS.Count -and -not [string]::IsNullOrEmpty($script:ARGS[$i+1])) {
        $script:IMAGE_NAME = $script:ARGS[$i+1]; $i += 2; continue
      } else {
        Write-Error 'Error: --image requires a path'; exit 1
      }
    }
    '--variant' {
      if ($i + 1 -lt $script:ARGS.Count -and -not [string]::IsNullOrEmpty($script:ARGS[$i+1])) {
        $script:VARIANT = $script:ARGS[$i+1]; $i += 2; continue
      } else {
        Write-Error 'Error: --variant requires a value'; exit 1
      }
    }
    '--version' {
      if ($i + 1 -lt $script:ARGS.Count -and -not [string]::IsNullOrEmpty($script:ARGS[$i+1])) {
        $script:VERSION = $script:ARGS[$i+1]; $i += 2; continue
      } else {
        Write-Error 'Error: --version requires a value'; exit 1
      }
    }
    '--dockerfile' {
      if ($i + 1 -lt $script:ARGS.Count -and -not [string]::IsNullOrEmpty($script:ARGS[$i+1])) {
        $script:DOCKER_FILE = $script:ARGS[$i+1]; $i += 2; continue
      } else {
        Write-Error 'Error: --dockerfile requires a path'; exit 1
      }
    }

    # Build
    '--build-args-file' {
      if ($i + 1 -lt $script:ARGS.Count -and -not [string]::IsNullOrEmpty($script:ARGS[$i+1])) {
        $script:DOCKER_BUILD_ARGS_FILE = $script:ARGS[$i+1]; $i += 2; continue
      } else {
        Write-Error 'Error: --build-args requires a path'; exit 1
      }
    }

    # Run
    '--name' {
      if ($i + 1 -lt $script:ARGS.Count -and -not [string]::IsNullOrEmpty($script:ARGS[$i+1])) {
        $script:CONTAINER_NAME = $script:ARGS[$i+1]; $i += 2; continue
      } else {
        Write-Error 'Error: --name requires a value'; exit 1
      }
    }
    '--run-args-file' {
      if ($i + 1 -lt $script:ARGS.Count -and -not [string]::IsNullOrEmpty($script:ARGS[$i+1])) {
        $script:DOCKER_RUN_ARGS_FILE = $script:ARGS[$i+1]; $i += 2; continue
      } else {
        Write-Error 'Error: --run-args requires a path'; exit 1
      }
    }
    '--env-file' {
      if ($i + 1 -lt $script:ARGS.Count -and -not [string]::IsNullOrEmpty($script:ARGS[$i+1])) {
        $script:CONTAINER_ENV_FILE = $script:ARGS[$i+1]; $i += 2; continue
      } else {
        Write-Error 'Error: --env-file requires a path'; exit 1
      }
    }

    # Note: The literal `--` was already split out above, so we won't see it here.
    Default {
      # If it looks like a docker run arg (starts with -), treat it as RUN_ARGS.
      # Otherwise: we've reached the command; send the rest to CMDS and exit the loop.
      if ($arg -like '-*') {
        $script:RUN_ARGS += $arg
        $i++
      } else {
        if ($i -lt $script:ARGS.Count) {
          $script:CMDS = @($script:ARGS[$i..($script:ARGS.Count - 1)])
        } else {
          $script:CMDS = @()
        }
        # exit the WHILE loop by jumping index to the end
        $i = $script:ARGS.Count
      }
      continue
    }
  }
}

#========== IMAGE ============

function Test-DockerImage {
  param([Parameter(Mandatory)][string]$Name)
  & docker image inspect $Name *> $null
  return ($LASTEXITCODE -eq 0)
}

if ([string]::IsNullOrEmpty($script:IMAGE_NAME)) {
  if (_is_true $script:LOCAL_BUILD) {
    $script:IMAGE_NAME = "workspace-local:$($script:PROJECT_NAME)"
    if (_is_true $script:VERBOSE) {
      Write-Host ""
      Write-Host "Build local image: $script:IMAGE_NAME"
    }

    $buildArgs = @(
      '-f', $script:DOCKER_FILE
      '-t', $script:IMAGE_NAME
      '--build-arg', "VARIANT_TAG=$($script:VARIANT)"
      '--build-arg', "VERSION_TAG=$($script:VERSION)"
      $script:WORKSPACE_PATH
    )
    docker_build @buildArgs
  }
  else {
    # -- Prebuild --
    if ($script:VARIANT -notin @('container','notebook','codeserver')) {
      Write-Error "Error: unknown --variant '$script:VARIANT' (expected: container|notebook|codeserver)"
      exit 1
    }

    # Construct the full image name.
    $script:IMAGE_NAME = "$($script:PREBUILD_REPO):$($script:VARIANT)-$($script:VERSION)"

    # Pull if not dry-run, or explicitly requested, or not present locally
    if ((-not (_is_true $script:DRYRUN)) -or (_is_true $script:DO_PULL) -or (-not (Test-DockerImage $script:IMAGE_NAME))) {
      if (_is_true $script:VERBOSE) {
        Write-Host "Pulling image: $script:IMAGE_NAME"
      }
      $output = (& docker pull $script:IMAGE_NAME 2>&1 | Out-String)
      if ($LASTEXITCODE -ne 0) {
        Write-Error ("Error: failed to pull '{0}':" -f $script:IMAGE_NAME)
        # mirror bash: print docker's output to stderr
        [Console]::Error.WriteLine($output)
        exit 1
      }
      if (_is_true $script:VERBOSE) {
        Write-Host $output
        Write-Host ""
      }
    }
  }
} # else => Custom image

# Ensure the image exists.
if (-not (Test-DockerImage $script:IMAGE_NAME)) {
  Write-Error "Error: image '$script:IMAGE_NAME' not available locally. Try '--pull'."
  exit 1
}

#========== ENV FILE ============

$var = Get-Variable -Name COMMON_ARGS -Scope Script -ErrorAction SilentlyContinue
if (-not $var -or $null -eq $var.Value) {
  $script:COMMON_ARGS = @()
}

# If VAR has no value and default file exists, use the default.
if ([string]::IsNullOrEmpty($script:CONTAINER_ENV_FILE) -and
    (Test-Path -LiteralPath (Join-Path $script:WORKSPACE_PATH '.env') -PathType Leaf)) {
  $script:CONTAINER_ENV_FILE = Join-Path $script:WORKSPACE_PATH '.env'
}

if (-not [string]::IsNullOrEmpty($script:CONTAINER_ENV_FILE) -and
    $script:CONTAINER_ENV_FILE -ne $script:FILE_NOT_USED) {

  if (-not (Test-Path -LiteralPath $script:CONTAINER_ENV_FILE -PathType Leaf)) {
    # mirror original behavior: print error but continue
    [Console]::Error.WriteLine("Container ENV file most be a file: $($script:CONTAINER_ENV_FILE)")
  }

  $script:COMMON_ARGS += @('--env-file', $script:CONTAINER_ENV_FILE)
}

#=========== RUN (verbose dump) =============

if (_is_true $script:VERBOSE) {
  Write-Host ""
  Write-Host "CONTAINER_NAME: $script:CONTAINER_NAME"
  Write-Host "DAEMON:         $script:DAEMON"
  Write-Host "DOCKER_FILE:    $script:DOCKER_FILE"
  Write-Host "DRYRUN:         $script:DRYRUN"
  Write-Host "HOST_UID:       $script:HOST_UID"
  Write-Host "HOST_GID:       $script:HOST_GID"
  Write-Host "IMAGE_NAME:     $script:IMAGE_NAME"
  Write-Host "IMAGE_MODE:     $script:IMAGE_MODE"
  Write-Host "WORKSPACE_PATH: $script:WORKSPACE_PATH"
  Write-Host "WORKSPACE_PORT: $script:WORKSPACE_PORT"
  Write-Host ""
  Write-Host "CONTAINER_ENV_FILE: $script:CONTAINER_ENV_FILE"
  Write-Host ""
  Write-Host "DOCKER_BUILD_ARGS_FILE: $script:DOCKER_BUILD_ARGS_FILE"
  Write-Host "DOCKER_RUN_ARGS_FILE:   $script:DOCKER_RUN_ARGS_FILE"
  Write-Host ""
  Write-Host ("BUILD_ARGS: " + (print_args @script:BUILD_ARGS))
  Write-Host ("RUN_ARGS:   " + (print_args @script:RUN_ARGS))
  Write-Host ""
  Write-Host ("CMDS: " + (print_args @script:CMDS))
  Write-Host ""

  if ($script:BUILD_ARGS.Count -gt 0 -and -not (_is_true $script:LOCAL_BUILD) -and (_is_true $script:VERBOSE)) {
    Write-Warning "⚠️  Warning: BUILD_ARGS provided, but no build is being performed (using prebuilt image)."
    Write-Host ""
  }
}
# --------- Execute ---------

# Clean up any previous container with the same name
if (-not (_is_true $script:DRYRUN)) {
  & docker rm -f $script:CONTAINER_NAME *> $null
  # ignore errors
}

# Build COMMON_ARGS
$script:COMMON_ARGS += @(
  '--name', $script:CONTAINER_NAME
  '-e', "HOST_UID=$($script:HOST_UID)"
  '-e', "HOST_GID=$($script:HOST_GID)"
  '-v', "$($script:WORKSPACE_PATH):/home/coder/workspace"
  '-w', '/home/coder/workspace'
  '-p', "$($script:WORKSPACE_PORT):10000"

  # Metadata
  '-e', "WS_DAEMON=$($script:DAEMON)"
  '-e', "WS_IMAGE_NAME=$($script:IMAGE_NAME)"
  '-e', "WS_CONTAINER_NAME=$($script:CONTAINER_NAME)"
  '-e', "WS_WORKSPACE_PATH=$($script:WORKSPACE_PATH)"
  '-e', "WS_WORKSPACE_PORT=$($script:WORKSPACE_PORT)"
)

# TTY handling: like `[ -t 0 ] && [ -t 1 ]`
$TTY_ARGS = '-i'
if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) { $TTY_ARGS = '-it' }

if (_is_true $script:DAEMON) {
  if ($script:CMDS.Count -ne 0) {
    [Console]::Error.WriteLine("Running command in daemon mode is not allowed: " + (print_args @script:CMDS))
    exit 1
  }

  # Detached: no TTY args
  Write-Host "📦 Running workspace in daemon mode."
  Write-Host "👉 Stop with '$script:SCRIPT_NAME -- exit'. The container will be removed (--rm) when stop."
  Write-Host "👉 Visit 'http://localhost:$($script:WORKSPACE_PORT)'"
  Write-Host "👉 To open an interactive shell instead: $script:SCRIPT_NAME -- bash"
  Write-Host -NoNewline "👉 Container ID: "
  if (_is_true $script:DRYRUN) {
    Write-Host "<--dryrun-->"; Write-Host ""
  } else {
    docker_run -d @script:COMMON_ARGS @script:RUN_ARGS $script:IMAGE_NAME
    Write-Host ""
  }

} elseif ($script:CMDS.Count -eq 0) {
  Write-Host "📦 Running workspace in foreground."
  Write-Host "👉 Stop with Ctrl+C. The container will be removed (--rm) when stop."
  Write-Host "👉 To open an interactive shell instead: '$script:SCRIPT_NAME -- bash'"
  Write-Host ""
  docker_run --rm $TTY_ARGS @script:COMMON_ARGS @script:RUN_ARGS $script:IMAGE_NAME

} else {
  # Foreground with explicit command
  $USER_CMDS = ($script:CMDS -join ' ')
  docker_run --rm $TTY_ARGS @script:COMMON_ARGS @script:RUN_ARGS $script:IMAGE_NAME bash -lc $USER_CMDS
}
