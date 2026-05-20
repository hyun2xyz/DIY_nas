[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$TokenFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
if (-not $TokenFile) {
    $TokenFile = Join-Path $ProjectRoot 'secrets\cloudflared-tunnel-token.dpapi'
}

$clipboard = Get-Clipboard -Raw
if (-not $clipboard) {
    throw 'Clipboard is empty. Copy the Cloudflare cloudflared command first.'
}

$token = $null
$jwtPrefix = 'e' + 'yJ'
if ($clipboard -match 'cloudflared(?:\.exe)?\s+service\s+install\s+(?<token>\S+)') {
    $token = $Matches.token
} elseif ($clipboard.Trim() -match "^$jwtPrefix\S+$") {
    $token = $clipboard.Trim()
}

if (-not $token) {
    throw 'Clipboard does not look like a Cloudflare tunnel token or service install command.'
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TokenFile) | Out-Null
$secure = ConvertTo-SecureString $token -AsPlainText -Force
$secure | ConvertFrom-SecureString | Set-Content -LiteralPath $TokenFile -Encoding UTF8

Write-Host "Saved Cloudflare tunnel token to DPAPI-protected file: $TokenFile"
Write-Host 'The token value was not printed.'
