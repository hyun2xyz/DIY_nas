[CmdletBinding()]
param(
    [string]$SecretsDirectory = (Join-Path $env:USERPROFILE 'nas-cloud-secrets'),
    [string]$EnvPath = (Join-Path (Get-Location) '.env'),
    [string]$NextcloudBaseUrl = 'http://<VM_HOST_OR_IP>:8080',
    [string]$NextcloudUsername = 'svc-gateway',
    [int]$GatewayPort = 8791
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-GatewayToken {
    $bytes = [byte[]]::new(32)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Set-EnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        "$Name=$Value" | Set-Content -LiteralPath $Path -Encoding UTF8
        return
    }

    $lines = Get-Content -LiteralPath $Path
    $prefix = "$Name="
    if ($lines | Where-Object { $_.StartsWith($prefix) }) {
        $lines = $lines | ForEach-Object {
            if ($_.StartsWith($prefix)) { "$Name=$Value" } else { $_ }
        }
        $lines | Set-Content -LiteralPath $Path -Encoding UTF8
    } else {
        Add-Content -LiteralPath $Path -Value "$Name=$Value"
    }
}

New-Item -ItemType Directory -Force -Path $SecretsDirectory | Out-Null

$tokensPath = Join-Path $SecretsDirectory 'gateway-tokens.json'
if (-not (Test-Path -LiteralPath $tokensPath)) {
    $tokens = [ordered]@{}
    $tokens[(New-GatewayToken)] = [ordered]@{
        name = 'Wiki or LMS integration'
        root = 'LMS'
        permissions = @('read', 'write')
    }
    $tokens[(New-GatewayToken)] = [ordered]@{
        name = 'Writing and GitHub Pages publishing'
        root = 'Publishing'
        permissions = @('read', 'write', 'delete')
    }
    $tokens[(New-GatewayToken)] = [ordered]@{
        name = 'Cafe24 app'
        root = 'Cafe24'
        permissions = @('read', 'write')
    }
    $tokens[(New-GatewayToken)] = [ordered]@{
        name = 'Wiki automation'
        root = 'Wiki'
        permissions = @('read', 'write')
    }

    $tokens | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tokensPath -Encoding UTF8
    Write-Host "Created gateway token file: $tokensPath"
} else {
    Write-Host "Gateway token file already exists: $tokensPath"
}

if (-not (Test-Path -LiteralPath $EnvPath)) {
    @"
NAS_GATEWAY_HOST=127.0.0.1
NAS_GATEWAY_PORT=$GatewayPort
NEXTCLOUD_BASE_URL=$NextcloudBaseUrl
NEXTCLOUD_USERNAME=$NextcloudUsername
NEXTCLOUD_APP_PASSWORD=replace-with-nextcloud-app-password
NAS_GATEWAY_TOKENS_FILE=$tokensPath
NAS_GATEWAY_MAX_UPLOAD_BYTES=1073741824
NAS_DRIVE_PASSWORD=$(New-GatewayToken)
NAS_DRIVE_SESSION_SECRET=$(New-GatewayToken)$(New-GatewayToken)
"@ | Set-Content -LiteralPath $EnvPath -Encoding UTF8
    Write-Host "Created env file: $EnvPath"
} else {
    Write-Host "Env file already exists, not overwritten: $EnvPath"
    $envText = Get-Content -LiteralPath $EnvPath -Raw
    if ($envText -notmatch '(?m)^NAS_DRIVE_PASSWORD=') {
        Set-EnvValue -Path $EnvPath -Name 'NAS_DRIVE_PASSWORD' -Value (New-GatewayToken)
        Write-Host 'Added NAS_DRIVE_PASSWORD to env file.'
    }
    if ($envText -notmatch '(?m)^NAS_DRIVE_SESSION_SECRET=') {
        Set-EnvValue -Path $EnvPath -Name 'NAS_DRIVE_SESSION_SECRET' -Value "$(New-GatewayToken)$(New-GatewayToken)"
        Write-Host 'Added NAS_DRIVE_SESSION_SECRET to env file.'
    }
}

Write-Host "Next step: set NEXTCLOUD_APP_PASSWORD in $EnvPath before starting npm.cmd run gateway."
