param(
    [string] $TaskName = "NasCloudDailyNextcloudBackup",
    [string] $PipelineScript = "$PSScriptRoot\invoke-nextcloud-backup-pipeline.ps1",
    [string] $At = "04:15"
)

$ErrorActionPreference = "Stop"

$scriptPath = (Resolve-Path $PipelineScript).Path
$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$argument = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

$action = New-ScheduledTaskAction -Execute $powershell -Argument $argument
$trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact($At, "HH:mm", $null))
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Create a Nextcloud cold backup in the Ubuntu VM and copy it to the Windows backup mirror." `
    -Force | Out-Null

Write-Output "Scheduled task registered:"
Get-ScheduledTask -TaskName $TaskName | Format-List TaskName,State,Description
