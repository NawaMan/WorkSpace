#!/usr/bin/env pwsh
$HOST_UID = 1000
$HOST_GID = 1000
$PWD_PATH = (Get-Location).Path

$EXPECT = @(
  "docker run --rm -it",
  "--name basic",
  "-e 'HOST_UID=$HOST_UID'",
  "-e 'HOST_GID=$HOST_GID'",
  "-v ${PWD_PATH}:/home/coder/workspace",
  "-w /home/coder/workspace",
  "-p 10000:10000",
  "nawaman/workspace:container-latest",
  "bash -lc 'tree -C'"
) -join " "

$ACTUAL = ../../workspace.ps1 --dryrun -- tree -C

if ($ACTUAL -eq $EXPECT) {
  Write-Host "✅ Match"
} else {
  Write-Host "❌ Differ"
  Write-Host "EXPECT:`n$EXPECT"
  Write-Host "ACTUAL:`n$ACTUAL"
  exit 1
}
