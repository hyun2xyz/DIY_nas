[CmdletBinding()]
param(
    [string]$VmNextcloudAddress = '192.168.100.10',
    [int]$NextcloudPort = 8080,
    [int]$GatewayPort = 8791
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated Administrator PowerShell.'
    }
}

function Get-TailscaleAddress {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Tailscale' -ErrorAction Stop |
        Where-Object { $_.IPAddress -like '100.*' } |
        Select-Object -First 1 -ExpandProperty IPAddress
    if (-not $ip) {
        throw 'Could not find a Windows Tailscale IPv4 address.'
    }
    return $ip
}

function Set-PortProxy {
    param(
        [string]$ListenAddress,
        [int]$ListenPort,
        [string]$ConnectAddress,
        [int]$ConnectPort
    )

    & netsh interface portproxy delete v4tov4 listenaddress=$ListenAddress listenport=$ListenPort | Out-Null
    & netsh interface portproxy add v4tov4 listenaddress=$ListenAddress listenport=$ListenPort connectaddress=$ConnectAddress connectport=$ConnectPort
}

function Set-FirewallRule {
    param(
        [string]$Name,
        [string]$DisplayName,
        [string]$LocalAddress,
        [int]$LocalPort
    )

    Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule `
        -Name $Name `
        -DisplayName $DisplayName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalAddress $LocalAddress `
        -LocalPort $LocalPort `
        -RemoteAddress '100.64.0.0/10' `
        -Profile Any | Out-Null
}

Assert-Administrator

$tailscaleAddress = Get-TailscaleAddress

Set-Service -Name iphlpsvc -StartupType Automatic
Start-Service -Name iphlpsvc

Write-Host "Windows Tailscale IP: $tailscaleAddress"
Write-Host "Forwarding $tailscaleAddress`:$NextcloudPort -> $VmNextcloudAddress`:$NextcloudPort"
Set-PortProxy -ListenAddress $tailscaleAddress -ListenPort $NextcloudPort -ConnectAddress $VmNextcloudAddress -ConnectPort $NextcloudPort
Set-FirewallRule -Name 'NAS-Nextcloud-Tailscale-8080' -DisplayName 'NAS Nextcloud via Tailscale 8080' -LocalAddress $tailscaleAddress -LocalPort $NextcloudPort

Write-Host "Forwarding $tailscaleAddress`:$GatewayPort -> 127.0.0.1:$GatewayPort"
Set-PortProxy -ListenAddress $tailscaleAddress -ListenPort $GatewayPort -ConnectAddress '127.0.0.1' -ConnectPort $GatewayPort
Set-FirewallRule -Name 'NAS-Gateway-Tailscale-8791' -DisplayName 'NAS Gateway via Tailscale 8791' -LocalAddress $tailscaleAddress -LocalPort $GatewayPort

Write-Host ''
Write-Host 'Portproxy table:'
& netsh interface portproxy show all

Write-Host ''
Write-Host 'Local verification:'
curl.exe -sS -m 8 "http://$tailscaleAddress`:$NextcloudPort/status.php"
Write-Host ''
curl.exe -sS -m 8 "http://$tailscaleAddress`:$GatewayPort/health"
Write-Host ''

Write-Host ''
Write-Host "Mac Nextcloud URL: http://$tailscaleAddress`:$NextcloudPort/remote.php/dav/files/wiki_storage/"
Write-Host "Mac Gateway URL:   http://$tailscaleAddress`:$GatewayPort"
