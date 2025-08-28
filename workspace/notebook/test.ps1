#!/usr/bin/env pwsh
#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- paths (resolve alongside this script) ---
$ScriptDir      = Split-Path -Parent $PSCommandPath
$HostFile       = Join-Path $ScriptDir 'in-host.txt'
$WorkspaceFile  = Join-Path $ScriptDir 'in-workspace.txt'

function Cleanup {
  foreach ($f in @($HostFile, $WorkspaceFile, $StderrFile)) {
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
  }
}

# Run cleanup on any exit (success or error)
try {
  # initial cleanup
  Cleanup

  # same value used in both places, but shell-safe
  $DATE = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffffffK"

  # write to file on host
  $DATE | Out-File -FilePath in-host.txt -Encoding UTF8

  # Write to file on workspace
  ./run.ps1 -- echo $DATE '>' in-workspace.txt

  # diff (prefer external 'diff -u' when available; otherwise fallback)
  $diffCmd = Get-Command diff -ErrorAction SilentlyContinue
  if ($diffCmd) {
    & $diffCmd.Source '-u' $WorkspaceFile $HostFile
    $exit = $LASTEXITCODE
    if ($exit -eq 0) {
      Write-Host "✅ Files match"
    } elseif ($exit -eq 1) {
      Write-Host "❌ Files differ"
      exit 1
    } else {
      Write-Error "diff failed (exit $exit)"
    }
  } else {
    # PowerShell fallback compare
    $a = Get-Content -LiteralPath $WorkspaceFile -Raw
    $b = Get-Content -LiteralPath $HostFile -Raw
    if ($a -ceq $b) {
      Write-Host "✅ Files match"
    } else {
      Write-Host "❌ Files differ"
      # show a quick unified-ish hint
      Write-Host "--- $WorkspaceFile"
      Write-Host "+++ $HostFile"
      $al = $a -split "`r?`n"
      $bl = $b -split "`r?`n"
      $cmp = Compare-Object -ReferenceObject $al -DifferenceObject $bl -IncludeEqual:$false
      $cmp | ForEach-Object {
        if ($_.SideIndicator -eq '<=') { Write-Host "- $($_.InputObject)" }
        elseif ($_.SideIndicator -eq '=>') { Write-Host "+ $($_.InputObject)" }
      }
      exit 1
    }
  }
}
finally {
  Cleanup
}
