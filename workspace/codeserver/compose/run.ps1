param(
    [switch]$h,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

# Set error action preference to stop on errors
$ErrorActionPreference = "Stop"

# ---------- Constants ----------
$SERVICE_NAME = "workspace"
$SHELL_NAME   = "bash"

function Show-Help {
    @"
Usage:
 run.ps1 [OPTIONS]                    # interactive shell (bash)
 run.ps1 [OPTIONS] -- <command...>    # run a command then exit

Options:
 -h, -Help    Show this help message

Note: Use '--' to separate Docker Compose run arguments from the command to execute.
      Everything before '--' goes to 'docker compose run', everything after goes to the command.
"@
}

# --------- Parse CLI ---------
if ($Help -or $h) {
    Show-Help
    exit 0
}

# Parse arguments: flags go to docker compose run, non-flags become the command
$RunArgsList = @()
$CMD = @()
$FoundNonFlag = $false

foreach ($arg in $Arguments) {
    if ($arg.StartsWith("-") -and -not $FoundNonFlag) {
        # This is a docker compose run argument (flag)
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

# --------- Run container ---------
if ($CMD.Length -eq 0) {
    # No command -> open a shell
    $DockerArgs = @("compose", "run", "--rm", "-p", "8888:8888", "-p", "8080:8080") + $RunArgsList + @($SERVICE_NAME)
    # Write-Host "DEBUG: Docker command: docker $($DockerArgs -join ' ')" -ForegroundColor Green
    & docker @DockerArgs
} else {
    # Command provided -> run it inside the shell
    $USER_CMD = $CMD -join " "
    $DockerArgs = @("compose", "run", "--rm", "-p", "8888:8888", "-p", "8080:8080") + $RunArgsList + @($SERVICE_NAME, $SHELL_NAME, "-lc", $USER_CMD)
    # Write-Host "DEBUG: Docker command: docker $($DockerArgs -join ' ')" -ForegroundColor Green
    & docker @DockerArgs
}

# Exit with the same code as docker
exit $LASTEXITCODE