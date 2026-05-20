param(
    [string] $InputJson
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

function Get-CurrentWindowsHostInfo {
    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $memoryGb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 0)

        return [pscustomobject]@{
            Name = $env:COMPUTERNAME
            OsName = $os.Caption
            TotalMemoryGB = $memoryGb
            HasSsdForApps = $false
            NetworkGbps = 1
            SupportsVirtualization = [bool]$computer.HypervisorPresent
            IsDedicatedHost = $false
            HasUps = $false
        }
    } catch {
        $osDescription = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription

        return [pscustomobject]@{
            Name = $env:COMPUTERNAME
            OsName = $osDescription
            TotalMemoryGB = 0
            HasSsdForApps = $false
            NetworkGbps = 1
            SupportsVirtualization = $false
            IsDedicatedHost = $false
            HasUps = $false
        }
    }
}

if ($InputJson) {
    if (-not (Test-Path -LiteralPath $InputJson)) {
        throw "Input JSON file not found: $InputJson"
    }

    $hostInfo = Get-Content -LiteralPath $InputJson -Raw | ConvertFrom-Json
} else {
    $hostInfo = Get-CurrentWindowsHostInfo
}

$assessment = Test-NasCloudHostCandidate -HostInfo $hostInfo
$memoryDisplay = if ([decimal]$hostInfo.TotalMemoryGB -le 0) { "Unknown" } else { "$($hostInfo.TotalMemoryGB) GB" }

Write-Output "# NAS Cloud Host Readiness Report"
Write-Output ""
Write-Output "| Field | Value |"
Write-Output "| --- | --- |"
Write-Output "| Name | $($hostInfo.Name) |"
Write-Output "| OS | $($hostInfo.OsName) |"
Write-Output "| RAM | $memoryDisplay |"
Write-Output "| SSD/NVMe for apps | $($hostInfo.HasSsdForApps) |"
Write-Output "| Network | $($hostInfo.NetworkGbps) GbE |"
Write-Output "| Virtualization | $($hostInfo.SupportsVirtualization) |"
Write-Output "| Dedicated host | $($hostInfo.IsDedicatedHost) |"
Write-Output "| UPS | $($hostInfo.HasUps) |"
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
