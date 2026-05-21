[CmdletBinding()]
param(
    [string]$TaskName = 'NasCloudGateway',
    [string]$ProjectRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$scriptPath = Join-Path $ProjectRoot 'scripts\gateway\start-gateway.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing gateway start script: $scriptPath"
}

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ProjectRoot `"$ProjectRoot`""

$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description 'Starts the NAS Gateway API for Nextcloud file access.' `
    -Force | Out-Null

Write-Host "Registered scheduled task: $TaskName"
Get-ScheduledTask -TaskName $TaskName | Select-Object TaskName,State,TaskPath
