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
$assessment = Test-NasCloudSsdPilotPlan -Plan $plan

Write-Output "# SSD Pilot Plan"
Write-Output ""
Write-Output "| Field | Value |"
Write-Output "| --- | --- |"
Write-Output "| Mode | $($plan.Mode) |"
Write-Output "| Windows remains host OS | $($plan.HostKeepsWindows) |"
Write-Output "| Pilot storage path | $($plan.PilotStoragePath) |"
Write-Output "| VM/container memory | $($plan.VmMemoryGB) GB |"
Write-Output "| VM/container disk | $($plan.VmDiskGB) GB |"
Write-Output "| VM/container vCPU | $($plan.VmCpuCount) |"
Write-Output "| Access mode | $($plan.AccessMode) |"
Write-Output "| Public internet exposure | $($plan.ExposePublicInternet) |"
Write-Output "| Production migration | $($plan.ProductionMigration) |"
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
Write-Output "## Recommended Path"
Write-Output ""
Write-Output "Use Hyper-V Ubuntu VM when you want Linux to run in a normal window while keeping Windows as the host OS. Use Docker Desktop WSL2 only when you want the fastest disposable container pilot."
Write-Output ""
Write-Output "## Windowed Ubuntu VM Checklist"
Write-Output ""
Write-Output "1. Enable Hyper-V from Windows Features and reboot."
Write-Output "2. Open Hyper-V Manager and create an Ubuntu VM."
Write-Output "3. Allocate $($plan.VmMemoryGB) GB RAM, $($plan.VmCpuCount) vCPU, and a $($plan.VmDiskGB) GB virtual disk on SSD."
Write-Output "4. Install Ubuntu in the VM window."
Write-Output "5. Install Docker Engine inside Ubuntu."
Write-Output "6. Run the Nextcloud AIO plan check before starting the mastercontainer."
Write-Output "7. Keep access LAN-only or VPN-only; do not port-forward this pilot."
