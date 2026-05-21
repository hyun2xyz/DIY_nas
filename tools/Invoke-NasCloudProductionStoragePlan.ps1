param(
    [string] $InputJson
)

$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "NasCloudTools.psm1"
Import-Module $modulePath -Force

function ConvertTo-TB {
    param([UInt64] $Bytes)
    [math]::Round($Bytes / 1TB, 2)
}

if ($InputJson) {
    $plan = Get-Content -Path $InputJson -Raw | ConvertFrom-Json
} else {
    $diskRows = Get-Disk |
        Where-Object { $_.Size -ge 7TB -and -not $_.IsBoot -and -not $_.IsSystem } |
        Sort-Object Number |
        ForEach-Object {
            $disk = $_
            $partition = Get-Partition -DiskNumber $disk.Number |
                Where-Object DriveLetter |
                Select-Object -First 1
            $volume = if ($partition) {
                Get-Volume -DriveLetter $partition.DriveLetter
            } else {
                $null
            }

            $role = if ($disk.Number -in @(1, 2)) {
                "LiveMirror"
            } elseif ($disk.Number -in @(3, 4)) {
                "BackupMirror"
            } else {
                "Review"
            }

            [pscustomobject]@{
                Label = if ($volume -and $volume.FileSystemLabel) { $volume.FileSystemLabel } else { "disk-$($disk.Number)" }
                Role = $role
                DiskNumber = $disk.Number
                Model = $disk.FriendlyName
                Serial = $disk.SerialNumber
                BusType = $disk.BusType
                CapacityTB = ConvertTo-TB $disk.Size
                FileSystem = if ($volume) { $volume.FileSystem } else { "" }
                DriveLetter = if ($partition) { "$($partition.DriveLetter):" } else { "" }
                IsBoot = $disk.IsBoot
                IsSystem = $disk.IsSystem
            }
        }

    $plan = [pscustomobject]@{
        Name = "current-windows-4x8tb"
        Disks = @($diskRows)
    }
}

$assessment = Test-NasCloudProductionStoragePlan -Plan $plan

"# NAS Cloud Production Storage Plan"
""
"| Field | Value |"
"| --- | --- |"
"| Name | $($assessment.Name) |"
"| Status | $($assessment.Status) |"
"| Recommended layout | $($assessment.RecommendedLayout) |"
"| Live usable | $($assessment.Capacity.LiveUsableTB) TB |"
"| Backup usable | $($assessment.Capacity.BackupUsableTB) TB |"
"| Live fault tolerance | $($assessment.Capacity.LiveFaultToleranceDisks) disk |"
"| Backup fault tolerance | $($assessment.Capacity.BackupFaultToleranceDisks) disk |"
""
"## Disks"
""
"| Role | Disk | Label | Model | Serial | Bus | Size | Filesystem | Drive |"
"| --- | ---: | --- | --- | --- | --- | ---: | --- | --- |"
foreach ($disk in @($plan.Disks)) {
    "| $($disk.Role) | $($disk.DiskNumber) | $($disk.Label) | $($disk.Model) | $($disk.Serial) | $($disk.BusType) | $($disk.CapacityTB) TB | $($disk.FileSystem) | $($disk.DriveLetter) |"
}
""
"## Blockers"
if ($assessment.Blockers.Count -eq 0) {
    "- None"
} else {
    $assessment.Blockers | ForEach-Object { "- $_" }
}
""
"## Warnings"
if ($assessment.Warnings.Count -eq 0) {
    "- None"
} else {
    $assessment.Warnings | ForEach-Object { "- $_" }
}
""
"## Strengths"
if ($assessment.Strengths.Count -eq 0) {
    "- None"
} else {
    $assessment.Strengths | ForEach-Object { "- $_" }
}
