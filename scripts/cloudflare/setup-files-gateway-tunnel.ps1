[CmdletBinding()]
param(
    [string]$TunnelName = 'nas-drive-gateway',
    [string]$Hostname = 'api-drive.example.com',
    [string]$OriginUrl = 'http://localhost:8791',
    [string]$CloudflaredConfigDir = "$env:USERPROFILE\.cloudflared",
    [string]$TunnelToken,
    [switch]$InstallService
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CloudflaredPath {
    $command = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidate = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter cloudflared.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($candidate) {
        return $candidate.FullName
    }

    throw 'cloudflared is not installed. Install it with: winget install --id Cloudflare.cloudflared'
}

function Read-TunnelList {
    param([string]$Cloudflared)

    $json = & $Cloudflared tunnel list --name $TunnelName --output json 2>$null
    if (-not $json) {
        return @()
    }
    return @($json | ConvertFrom-Json)
}

New-Item -ItemType Directory -Force -Path $CloudflaredConfigDir | Out-Null

$cloudflared = Get-CloudflaredPath

if ($TunnelToken) {
    if (-not $InstallService) {
        throw 'TunnelToken mode requires -InstallService because the token is used by the Windows service.'
    }

    Write-Host "Installing cloudflared Windows service for dashboard-managed tunnel '$TunnelName'."
    & $cloudflared service install $TunnelToken
    Start-Service cloudflared
    Write-Host "Gateway public URL: https://$Hostname"
    Write-Host "Confirm in Cloudflare Zero Trust that the public hostname points to $OriginUrl."
    exit 0
}

$originCert = Join-Path $CloudflaredConfigDir 'cert.pem'
if (-not (Test-Path -LiteralPath $originCert)) {
    throw "Cloudflare login is required first. Run: `"$cloudflared`" tunnel login"
}

$tunnels = Read-TunnelList -Cloudflared $cloudflared
$tunnel = $tunnels | Where-Object { $_.name -eq $TunnelName } | Select-Object -First 1
if (-not $tunnel) {
    Write-Host "Creating Cloudflare tunnel '$TunnelName'."
    & $cloudflared tunnel create $TunnelName
    $tunnels = Read-TunnelList -Cloudflared $cloudflared
    $tunnel = $tunnels | Where-Object { $_.name -eq $TunnelName } | Select-Object -First 1
}
if (-not $tunnel) {
    throw "Could not resolve tunnel '$TunnelName' after creation."
}

$tunnelId = [string]$tunnel.id
$credentialsFile = Join-Path $CloudflaredConfigDir "$tunnelId.json"
if (-not (Test-Path -LiteralPath $credentialsFile)) {
    throw "Tunnel credentials file was not found: $credentialsFile"
}

$configPath = Join-Path $CloudflaredConfigDir 'config.yml'
@"
tunnel: $tunnelId
credentials-file: $credentialsFile

ingress:
  - hostname: $Hostname
    service: $OriginUrl
  - service: http_status:404
"@ | Set-Content -LiteralPath $configPath -Encoding UTF8

Write-Host "Routing DNS: $Hostname -> $TunnelName"
& $cloudflared tunnel route dns --overwrite-dns $TunnelName $Hostname

if ($InstallService) {
    Write-Host 'Installing cloudflared Windows service.'
    & $cloudflared service install
    Start-Service cloudflared
} else {
    Write-Host "Config written: $configPath"
    Write-Host "Run tunnel in foreground with:"
    Write-Host "`"$cloudflared`" tunnel --config `"$configPath`" run $TunnelName"
}

Write-Host "Gateway public URL: https://$Hostname"
