param(
    [Parameter(Mandatory = $true)] [string] $InputJson
)

$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "NasCloudTools.psm1"
Import-Module $modulePath -Force

if (-not (Test-Path -LiteralPath $InputJson)) {
    throw "Input JSON file not found: $InputJson"
}

$raw = Get-Content -LiteralPath $InputJson -Raw
$parsed = $raw | ConvertFrom-Json
if ($parsed -is [array]) {
    $disks = $parsed
} else {
    $disks = @($parsed)
}

if ($disks.Count -eq 0) {
    throw "Input JSON must contain at least one disk."
}

$diskSize = [decimal]$disks[0].CapacityTB
$capacity = Get-RaidZ2CapacityEstimate -DiskCount $disks.Count -DiskSizeTB $diskSize

Write-Output "# NAS Cloud Disk Inventory Report"
Write-Output ""
Write-Output "## RAIDZ2 Capacity Estimate"
Write-Output ""
Write-Output "| Disk count | Disk size | Usable TB | Usable TiB | Fault tolerance |"
Write-Output "| --- | --- | --- | --- | --- |"
Write-Output "| $($capacity.DiskCount) | $($capacity.DiskSizeTB) TB | $($capacity.UsableTB) TB | $($capacity.UsableTiB) TiB | $($capacity.FaultToleranceDisks) disks |"
Write-Output ""
Write-Output "## Disk Assessment"
Write-Output ""
Write-Output "| Label | Severity | Approved | Reasons |"
Write-Output "| --- | --- | --- | --- |"

foreach ($disk in $disks) {
    $assessment = Test-NasCloudDiskCandidate -Disk $disk
    $approved = if ($assessment.Approved) { "Yes" } else { "No" }
    $reasons = $assessment.Reasons -join "; "
    Write-Output "| $($assessment.Label) | $($assessment.Severity) | $approved | $reasons |"
}

Write-Output ""
Write-Output "## Markdown Rows For docs/disk-inventory.md"
Write-Output ""
foreach ($disk in $disks) {
    Write-Output (ConvertTo-NasCloudDiskMarkdownRow -Disk $disk)
}
