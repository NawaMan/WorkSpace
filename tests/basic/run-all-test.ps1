$ErrorActionPreference = 'Stop'

Get-ChildItem -Path . -Filter 'test0*.ps1' -File |
    Sort-Object Name |
    ForEach-Object {
        Write-Host $_.Name
        & $_.FullName
        Write-Host
    }