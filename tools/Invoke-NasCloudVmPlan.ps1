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
$assessment = Test-NasCloudVmPlan -Plan $plan

Write-Output "# Linux VM Plan"
Write-Output ""
Write-Output "| Field | Value |"
Write-Output "| --- | --- |"
Write-Output "| Name | $($plan.Name) |"
Write-Output "| VHDX path | $($plan.VhdPath) |"
Write-Output "| VHDX size | $($plan.VhdSizeGB) GB |"
Write-Output "| Memory | $($plan.MemoryGB) GB |"
Write-Output "| vCPU | $($plan.CpuCount) |"
Write-Output "| Switch | $($plan.SwitchName) |"
Write-Output "| Generation | $($plan.Generation) |"
Write-Output "| Remote access | $($plan.RemoteAccess) |"
Write-Output "| Future HDD mode | $($plan.FutureHddMode) |"
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
