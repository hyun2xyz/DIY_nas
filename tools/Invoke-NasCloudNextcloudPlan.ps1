param(
    [Parameter(Mandatory = $true)] [string] $InputJson
)

$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "NasCloudTools.psm1"
Import-Module $modulePath -Force

function Write-ListOrNone {
    param([string[]] $Items)

    if (-not $Items -or $Items.Count -eq 0) {
        Write-Output "- None"
        return
    }

    foreach ($item in $Items) {
        Write-Output "- $item"
    }
}

if (-not (Test-Path -LiteralPath $InputJson)) {
    throw "Input JSON file not found: $InputJson"
}

$plan = Get-Content -LiteralPath $InputJson -Raw | ConvertFrom-Json
$assessment = Test-NasCloudNextcloudPlan -Plan $plan

Write-Output "# Nextcloud AIO Deployment Plan"
Write-Output ""
Write-Output "| Field | Value |"
Write-Output "| --- | --- |"
Write-Output "| Domain | $($plan.Domain) |"
Write-Output "| NEXTCLOUD_DATADIR | $($plan.DataDir) |"
Write-Output "| Backup directory | $($plan.BackupDir) |"
Write-Output "| Reverse proxy | $($plan.UseReverseProxy) |"
Write-Output "| AIO interface port | $($plan.AioInterfacePort) |"
Write-Output "| APACHE_PORT | $($plan.ApachePort) |"
Write-Output "| VPN-only first access | $($plan.UseVpnOnly) |"
Write-Output "| Public internet exposure | $($plan.ExposePublicInternet) |"
Write-Output "| Status | $($assessment.Status) |"
Write-Output ""
Write-Output "## Blockers"
Write-Output ""
Write-ListOrNone $assessment.Blockers
Write-Output ""
Write-Output "## Warnings"
Write-Output ""
Write-ListOrNone $assessment.Warnings
Write-Output ""
Write-Output "## Strengths"
Write-Output ""
Write-ListOrNone $assessment.Strengths
Write-Output ""
Write-Output "## Mastercontainer Command Template"
Write-Output ""
Write-Output "Review the official Nextcloud AIO README before running this. This template is for a Linux Docker host and does not execute anything."
Write-Output ""
Write-Output '```bash'
Write-Output "sudo docker run \"
Write-Output "  --init \"
Write-Output "  --sig-proxy=false \"
Write-Output "  --name nextcloud-aio-mastercontainer \"
Write-Output "  --restart always \"
Write-Output "  --publish $($plan.AioInterfacePort):8080 \"
if ([bool]$plan.UseReverseProxy) {
    Write-Output "  --env APACHE_PORT=$($plan.ApachePort) \"
    Write-Output "  --env APACHE_IP_BINDING=0.0.0.0 \"
} else {
    Write-Output "  --publish 80:80 \"
    Write-Output "  --publish 8443:8443 \"
}
Write-Output "  --env NEXTCLOUD_DATADIR=`"$($plan.DataDir)`" \"
Write-Output "  --volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config \"
Write-Output "  --volume /var/run/docker.sock:/var/run/docker.sock:ro \"
Write-Output "  ghcr.io/nextcloud-releases/all-in-one:latest"
Write-Output '```'
