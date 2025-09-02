#!/usr/bin/env pwsh
#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- paths (resolve alongside this script) ---
$ScriptDir     = Split-Path -Parent $PSCommandPath
$HostFile      = Join-Path $ScriptDir 'in-host.txt'
$WorkspaceFile = Join-Path $ScriptDir 'in-container.txt'

function Cleanup {
  foreach ($f in @($HostFile, $WorkspaceFile)) {
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
  }
}

# Run cleanup on any exit (success or error)
try {
  # initial cleanup (like calling cleanup once at start)
  Cleanup

  # same value used in both places
  $DATE = (Get-Date).ToString()   # use any format you like; both sides use the same string

  # write to file on host
  $DATE | Out-File -FilePath in-host.txt -Encoding UTF8

  # Write to file on container
  ./run.ps1 -- echo $DATE '>' in-container.txt

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
