param(
    [ValidateSet('Release','Debug')][string]$Configuration='Release',
    [string]$Runtime='win-x64'
)
& (Join-Path $PSScriptRoot 'OneClick-Win11.ps1') -Configuration $Configuration -Runtime $Runtime -NoLaunch
exit $LASTEXITCODE
