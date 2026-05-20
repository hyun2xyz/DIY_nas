[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$TaskName = 'NasCloudflareFilesTunnel'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$script = Join-Path $ProjectRoot 'scripts\cloudflare\start-files-gateway-tunnel.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    throw "Startup script not found: $script"
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Write-Host "Registered current-user scheduled task: $TaskName"
