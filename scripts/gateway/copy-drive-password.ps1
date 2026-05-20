[CmdletBinding()]
param(
    [string]$EnvPath = (Join-Path (Get-Location) '.env')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $EnvPath)) {
    throw "Env file not found: $EnvPath"
}

$line = Get-Content -LiteralPath $EnvPath |
    Where-Object { $_ -match '^NAS_DRIVE_PASSWORD=' } |
    Select-Object -First 1

if (-not $line) {
    throw "NAS_DRIVE_PASSWORD is not configured in $EnvPath"
}

$password = $line.Substring('NAS_DRIVE_PASSWORD='.Length)
if ([string]::IsNullOrWhiteSpace($password) -or $password -eq 'change-this-before-use') {
    throw "NAS_DRIVE_PASSWORD is not set to a usable value in $EnvPath"
}

Set-Clipboard -Value $password
Write-Host 'Copied Drive web login password to clipboard.'
Write-Host 'Paste it into the /drive login screen. Do not commit or share it.'
