#!/usr/bin/env pwsh
#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- paths (resolve alongside this script) ---
$ScriptDir     = Split-Path -Parent $PSCommandPath
$HostFile      = Join-Path $ScriptDir 'in-host.txt'
$WorkspaceFile = Join-Path $ScriptDir 'in-workspace.txt'

function Cleanup {
  foreach ($f in @($HostFile, $WorkspaceFile)) {
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
  }
}

try {
  Cleanup

  $DATE = (Get-Date).ToString()

  # write to host file
  $DATE | Out-File -FilePath $HostFile -Encoding UTF8

  # write inside container (forward Variant same as sh)
  ../../workspace.ps1 -- echo $DATE '>' in-workspace.txt

  # diff logic unchanged …
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
    $a = Get-Content -LiteralPath $WorkspaceFile -Raw
    $b = Get-Content -LiteralPath $HostFile -Raw
    if ($a -ceq $b) {
      Write-Host "✅ Files match"
    } else {
      Write-Host "❌ Files differ"
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
