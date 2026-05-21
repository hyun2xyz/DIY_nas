$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "..\NasCloudTools.psm1"
Import-Module $modulePath -Force

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)] $Actual,
        [Parameter(Mandatory = $true)] $Expected,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

function Assert-ContainsText {
    param(
        [Parameter(Mandatory = $true)] [string[]] $Actual,
        [Parameter(Mandatory = $true)] [string] $ExpectedText,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    $joined = $Actual -join "`n"
    if ($joined -notlike "*$ExpectedText*") {
        throw "$Message. Missing '$ExpectedText' in: $joined"
    }
}

function New-TestDisk {
    param(
        [string] $Label = "POOL-01",
        [string] $Model = "WD80EFZZ",
        [string] $RecordingTechnology = "CMR",
        [string] $SmartOverall = "Healthy",
        [string] $SmartLongTest = "Passed",
        [int] $ReallocatedSectors = 0,
        [int] $CurrentPendingSectors = 0,
        [int] $OfflineUncorrectableSectors = 0
    )

    [pscustomobject]@{
        Label = $Label
        IntendedRole = "RAIDZ2 pool"
        Manufacturer = "Test"
        Model = $Model
        Serial = "SERIAL-$Label"
        CapacityTB = 8
        RecordingTechnology = $RecordingTechnology
        SmartOverall = $SmartOverall
        SmartLongTest = $SmartLongTest
        ReallocatedSectors = $ReallocatedSectors
        CurrentPendingSectors = $CurrentPendingSectors
        OfflineUncorrectableSectors = $OfflineUncorrectableSectors
    }
}

$healthy = Test-NasCloudDiskCandidate -Disk (New-TestDisk)
Assert-Equal $healthy.Approved $true "A healthy CMR disk should be approved"
Assert-Equal $healthy.Severity "OK" "A healthy CMR disk should have OK severity"

$pending = Test-NasCloudDiskCandidate -Disk (New-TestDisk -CurrentPendingSectors 1)
Assert-Equal $pending.Approved $false "A disk with pending sectors should be rejected"
Assert-Equal $pending.Severity "Reject" "A disk with pending sectors should be a rejection"
Assert-ContainsText $pending.Reasons "Current pending sectors > 0" "Pending-sector reason should be reported"

$smr = Test-NasCloudDiskCandidate -Disk (New-TestDisk -RecordingTechnology "SMR")
Assert-Equal $smr.Approved $false "An SMR disk should be rejected by default"
Assert-ContainsText $smr.Reasons "SMR" "SMR risk should be reported"

$unknown = Test-NasCloudDiskCandidate -Disk (New-TestDisk -RecordingTechnology "")
Assert-Equal $unknown.Approved $false "Unknown recording technology should require manual review"
Assert-Equal $unknown.Severity "Review" "Unknown recording technology should be a review item"

$capacity = Get-RaidZ2CapacityEstimate -DiskCount 4 -DiskSizeTB 8
Assert-Equal $capacity.UsableTB 16 "Four 8 TB disks in RAIDZ2 should produce 16 TB decimal usable"
Assert-Equal $capacity.FaultToleranceDisks 2 "RAIDZ2 should tolerate two disk failures"

$mirrorCapacity = Get-MirrorBackupCapacityEstimate -LiveDiskSizeTB 8 -BackupDiskSizeTB 8
Assert-Equal $mirrorCapacity.LiveUsableTB 8 "Two live mirror disks should provide one disk of usable live capacity"
Assert-Equal $mirrorCapacity.BackupUsableTB 8 "Two backup mirror disks should provide one disk of usable backup capacity"
Assert-Equal $mirrorCapacity.LiveFaultToleranceDisks 1 "A live mirror should tolerate one disk failure"

$productionStoragePlan = Test-NasCloudProductionStoragePlan -Plan ([pscustomobject]@{
    Name = "current-windows-4x8tb"
    Disks = @(
        [pscustomobject]@{ Label = "1"; Role = "LiveMirror"; DiskNumber = 1; Model = "ST8000VN 004-2M2101"; Serial = "LIVE-DISK-1"; BusType = "USB"; CapacityTB = 7.28; FileSystem = "exFAT"; DriveLetter = "E:"; IsBoot = $false; IsSystem = $false },
        [pscustomobject]@{ Label = "2"; Role = "LiveMirror"; DiskNumber = 2; Model = "ST8000VN 004-2M2101"; Serial = "LIVE-DISK-2"; BusType = "USB"; CapacityTB = 7.28; FileSystem = "exFAT"; DriveLetter = "F:"; IsBoot = $false; IsSystem = $false },
        [pscustomobject]@{ Label = "3"; Role = "BackupMirror"; DiskNumber = 3; Model = "WDC WD80 EAAZ-00BXBB0"; Serial = "BACKUP-DISK-1"; BusType = "USB"; CapacityTB = 7.28; FileSystem = "exFAT"; DriveLetter = "D:"; IsBoot = $false; IsSystem = $false },
        [pscustomobject]@{ Label = "4"; Role = "BackupMirror"; DiskNumber = 4; Model = "WDC WD80 EAAZ-00BXBB0"; Serial = "BACKUP-DISK-2"; BusType = "USB"; CapacityTB = 7.28; FileSystem = "exFAT"; DriveLetter = "G:"; IsBoot = $false; IsSystem = $false }
    )
})
Assert-Equal $productionStoragePlan.Status "Review" "USB/exFAT production storage should require review before destructive pool creation"
Assert-ContainsText $productionStoragePlan.Warnings "USB" "USB production disk warning should be reported"
Assert-ContainsText $productionStoragePlan.Warnings "exFAT" "Existing filesystem warning should be reported"
Assert-ContainsText $productionStoragePlan.Strengths "LiveMirror uses the NAS-class ST8000VN disks" "NAS-class live mirror disks should be detected"

$badProductionStoragePlan = Test-NasCloudProductionStoragePlan -Plan ([pscustomobject]@{
    Name = "bad-production-layout"
    Disks = @(
        [pscustomobject]@{ Label = "boot"; Role = "LiveMirror"; DiskNumber = 0; Model = "SSD"; Serial = "BOOT"; BusType = "NVMe"; CapacityTB = 1; FileSystem = "NTFS"; DriveLetter = "C:"; IsBoot = $true; IsSystem = $true },
        [pscustomobject]@{ Label = "2"; Role = "LiveMirror"; DiskNumber = 2; Model = "ST8000VN"; Serial = "DUP"; BusType = "USB"; CapacityTB = 7.28; FileSystem = "exFAT"; DriveLetter = "F:"; IsBoot = $false; IsSystem = $false },
        [pscustomobject]@{ Label = "3"; Role = "BackupMirror"; DiskNumber = 2; Model = "WDC"; Serial = "DUP"; BusType = "USB"; CapacityTB = 7.28; FileSystem = "exFAT"; DriveLetter = "D:"; IsBoot = $false; IsSystem = $false }
    )
})
Assert-Equal $badProductionStoragePlan.Status "Blocked" "Unsafe production storage plan should be blocked"
Assert-ContainsText $badProductionStoragePlan.Blockers "Exactly four 8 TB disks" "Disk count blocker should be reported"
Assert-ContainsText $badProductionStoragePlan.Blockers "boot/system" "Boot disk blocker should be reported"

$readyHost = Test-NasCloudHostCandidate -HostInfo ([pscustomobject]@{
    Name = "nas-candidate"
    OsName = "Ubuntu Server 24.04 LTS"
    TotalMemoryGB = 64
    HasSsdForApps = $true
    NetworkGbps = 2.5
    SupportsVirtualization = $true
    IsDedicatedHost = $true
    HasUps = $true
})
Assert-Equal $readyHost.Status "Ready" "A dedicated Linux host with 64 GB RAM, SSD, 2.5 GbE, virtualization, and UPS should be ready"
Assert-Equal $readyHost.Blockers.Count 0 "A ready host should have no blockers"

$pilotOnlyHost = Test-NasCloudHostCandidate -HostInfo ([pscustomobject]@{
    Name = "windows-desktop"
    OsName = "Microsoft Windows 11 Pro"
    TotalMemoryGB = 32
    HasSsdForApps = $true
    NetworkGbps = 1
    SupportsVirtualization = $true
    IsDedicatedHost = $false
    HasUps = $false
})
Assert-Equal $pilotOnlyHost.Status "PilotOnly" "A Windows desktop host should be marked pilot-only for production NAS use"
Assert-ContainsText $pilotOnlyHost.Warnings "Dedicated NAS/server OS is recommended for production" "Windows desktop warning should be reported"

$blockedHost = Test-NasCloudHostCandidate -HostInfo ([pscustomobject]@{
    Name = "underpowered"
    OsName = "Ubuntu Server 24.04 LTS"
    TotalMemoryGB = 16
    HasSsdForApps = $false
    NetworkGbps = 1
    SupportsVirtualization = $false
    IsDedicatedHost = $true
    HasUps = $false
})
Assert-Equal $blockedHost.Status "Blocked" "A host without enough RAM, SSD, or virtualization should be blocked"
Assert-ContainsText $blockedHost.Blockers "At least 32 GB RAM is required for the planned first production slice" "RAM blocker should be reported"
Assert-ContainsText $blockedHost.Blockers "SSD or NVMe app storage is required before adding real users" "SSD blocker should be reported"

$unknownMemoryHost = Test-NasCloudHostCandidate -HostInfo ([pscustomobject]@{
    Name = "limited-windows-check"
    OsName = "Microsoft Windows"
    TotalMemoryGB = 0
    HasSsdForApps = $false
    NetworkGbps = 1
    SupportsVirtualization = $false
    IsDedicatedHost = $false
    HasUps = $false
})
Assert-Equal $unknownMemoryHost.Status "Blocked" "Unknown memory plus missing SSD and virtualization should remain blocked"
Assert-ContainsText $unknownMemoryHost.Warnings "RAM could not be detected; confirm at least 32 GB before production use" "Unknown RAM warning should be reported"

$nextcloudPlan = Test-NasCloudNextcloudPlan -Plan ([pscustomobject]@{
    Domain = "cloud.home.arpa"
    DataDir = "/mnt/tank/nextcloud-data"
    BackupDir = "/mnt/tank/nextcloud-db-backups"
    ApachePort = 11000
    AioInterfacePort = 8080
    UseReverseProxy = $true
    UseVpnOnly = $true
    ExposePublicInternet = $false
    EnableOffice = $false
    EnableClamAv = $false
    EnableFullTextSearch = $false
})
Assert-Equal $nextcloudPlan.Status "Ready" "A VPN-only reverse-proxy plan with absolute data directories should be ready"
Assert-Equal $nextcloudPlan.Blockers.Count 0 "A ready Nextcloud plan should have no blockers"

$unsafeNextcloudPlan = Test-NasCloudNextcloudPlan -Plan ([pscustomobject]@{
    Domain = "cloud.local"
    DataDir = "tank/nextcloud-data"
    BackupDir = ""
    ApachePort = 443
    AioInterfacePort = 8080
    UseReverseProxy = $true
    UseVpnOnly = $false
    ExposePublicInternet = $true
    EnableOffice = $true
    EnableClamAv = $true
    EnableFullTextSearch = $true
})
Assert-Equal $unsafeNextcloudPlan.Status "Blocked" "Unsafe Nextcloud plan should be blocked"
Assert-ContainsText $unsafeNextcloudPlan.Blockers "NEXTCLOUD_DATADIR must be an absolute Linux path that starts with /" "Relative data dir should be blocked"
Assert-ContainsText $unsafeNextcloudPlan.Blockers "Do not use .local for the Nextcloud domain" ".local domain should be blocked"

$ssdPilotPlan = Test-NasCloudSsdPilotPlan -Plan ([pscustomobject]@{
    Mode = "HyperVUbuntuVM"
    HostKeepsWindows = $true
    PilotStoragePath = "C:\NasPilot"
    VmMemoryGB = 8
    VmDiskGB = 160
    VmCpuCount = 6
    HostHasSsd = $true
    AccessMode = "VPN"
    ExposePublicInternet = $false
    ProductionMigration = "RebuildOrAioRestore"
})
Assert-Equal $ssdPilotPlan.Status "Ready" "A Hyper-V Ubuntu VM pilot on SSD with VPN access should be ready"
Assert-Equal $ssdPilotPlan.Blockers.Count 0 "A ready SSD pilot plan should have no blockers"
Assert-ContainsText $ssdPilotPlan.Strengths "Windows remains the host OS" "Windows host preservation should be reported"

$unsafePilotPlan = Test-NasCloudSsdPilotPlan -Plan ([pscustomobject]@{
    Mode = "DockerDesktopWSL2"
    HostKeepsWindows = $true
    PilotStoragePath = "C:\NasPilot"
    VmMemoryGB = 4
    VmDiskGB = 40
    VmCpuCount = 2
    HostHasSsd = $false
    AccessMode = "PublicInternet"
    ExposePublicInternet = $true
    ProductionMigration = "MoveDatadirInPlace"
})
Assert-Equal $unsafePilotPlan.Status "Blocked" "An undersized public SSD pilot should be blocked"
Assert-ContainsText $unsafePilotPlan.Blockers "Do not expose the SSD pilot directly to the public internet" "Public pilot exposure should be blocked"
Assert-ContainsText $unsafePilotPlan.Blockers "Do not plan an in-place datadir move from SSD pilot to RAIDZ2 production" "Unsafe migration should be blocked"

$vmPlan = Test-NasCloudVmPlan -Plan ([pscustomobject]@{
    Name = "nas-linux-pilot"
    VhdPath = "C:\NasVm\nas-linux-pilot.vhdx"
    VhdSizeGB = 128
    MemoryGB = 12
    CpuCount = 8
    SwitchName = "Default Switch"
    Generation = 2
    EnableSecureBoot = $false
    RemoteAccess = "TailscaleAndSsh"
    FutureHddMode = "OfflinePhysicalDiskAttach"
})
Assert-Equal $vmPlan.Status "Ready" "A 128GB Hyper-V Ubuntu VM plan should be ready"
Assert-ContainsText $vmPlan.Strengths "VHDX virtual disk avoids resizing the Windows OS partition" "VHDX isolation should be reported"

$badVmPlan = Test-NasCloudVmPlan -Plan ([pscustomobject]@{
    Name = "bad vm"
    VhdPath = "C:\"
    VhdSizeGB = 30
    MemoryGB = 4
    CpuCount = 2
    SwitchName = ""
    Generation = 1
    EnableSecureBoot = $true
    RemoteAccess = "PublicInternet"
    FutureHddMode = "WindowsManagedDisks"
})
Assert-Equal $badVmPlan.Status "Blocked" "Unsafe VM plan should be blocked"
Assert-ContainsText $badVmPlan.Blockers "VHD size must be at least 80 GB for an Ubuntu/Docker/Nextcloud pilot" "Small VHD should be blocked"
Assert-ContainsText $badVmPlan.Blockers "Do not expose VM management or cloud services directly to the public internet" "Public remote access should be blocked"

$row = ConvertTo-NasCloudDiskMarkdownRow -Disk (New-TestDisk -Label "POOL-02")
Assert-Equal $row "| POOL-02 | RAIDZ2 pool | Test | WD80EFZZ | SERIAL-POOL-02 | 8 TB | CMR | Healthy | Passed | Yes |" "Markdown row should match the inventory table format"

$jsonPath = Join-Path $PSScriptRoot "tmp-disk-inventory.json"
$jsonDisks = @()
$jsonDisks += New-TestDisk -Label "POOL-01"
$jsonDisks += New-TestDisk -Label "POOL-02" -CurrentPendingSectors 1
$jsonDisks += New-TestDisk -Label "POOL-03"
$jsonDisks += New-TestDisk -Label "POOL-04"
$jsonDisks | ConvertTo-Json | Set-Content -Path $jsonPath -Encoding UTF8

try {
    $report = & (Join-Path $PSScriptRoot "..\Invoke-NasCloudInventory.ps1") -InputJson $jsonPath
    $reportText = $report -join "`n"

    if ($reportText -notlike "*RAIDZ2 Capacity Estimate*") {
        throw "Inventory CLI should print the RAIDZ2 capacity estimate."
    }

    if ($reportText -notlike "*POOL-02*Reject*") {
        throw "Inventory CLI should report rejected disk candidates."
    }

    $hostJsonPath = Join-Path $PSScriptRoot "tmp-host-readiness.json"
    [pscustomobject]@{
        Name = "windows-desktop"
        OsName = "Microsoft Windows 11 Pro"
        TotalMemoryGB = 32
        HasSsdForApps = $true
        NetworkGbps = 1
        SupportsVirtualization = $true
        IsDedicatedHost = $false
        HasUps = $false
    } | ConvertTo-Json | Set-Content -Path $hostJsonPath -Encoding UTF8

    $hostReport = & (Join-Path $PSScriptRoot "..\Invoke-NasCloudHostReadiness.ps1") -InputJson $hostJsonPath
    $hostReportText = $hostReport -join "`n"

    if ($hostReportText -notlike "*NAS Cloud Host Readiness Report*") {
        throw "Host readiness CLI should print a report heading."
    }

    if ($hostReportText -notlike "*PilotOnly*") {
        throw "Host readiness CLI should report pilot-only status for a Windows desktop host."
    }

    $nextcloudJsonPath = Join-Path $PSScriptRoot "tmp-nextcloud-plan.json"
    [pscustomobject]@{
        Domain = "cloud.home.arpa"
        DataDir = "/mnt/tank/nextcloud-data"
        BackupDir = "/mnt/tank/nextcloud-db-backups"
        ApachePort = 11000
        AioInterfacePort = 8080
        UseReverseProxy = $true
        UseVpnOnly = $true
        ExposePublicInternet = $false
        EnableOffice = $false
        EnableClamAv = $false
        EnableFullTextSearch = $false
    } | ConvertTo-Json | Set-Content -Path $nextcloudJsonPath -Encoding UTF8

    $nextcloudReport = & (Join-Path $PSScriptRoot "..\Invoke-NasCloudNextcloudPlan.ps1") -InputJson $nextcloudJsonPath
    $nextcloudReportText = $nextcloudReport -join "`n"

    if ($nextcloudReportText -notlike "*Nextcloud AIO Deployment Plan*") {
        throw "Nextcloud plan CLI should print a report heading."
    }

    if ($nextcloudReportText -notlike "*NEXTCLOUD_DATADIR*") {
        throw "Nextcloud plan CLI should include the NEXTCLOUD_DATADIR setting."
    }

    $ssdPilotJsonPath = Join-Path $PSScriptRoot "tmp-ssd-pilot-plan.json"
    [pscustomobject]@{
        Mode = "HyperVUbuntuVM"
        HostKeepsWindows = $true
        PilotStoragePath = "C:\NasPilot"
        VmMemoryGB = 8
        VmDiskGB = 160
        VmCpuCount = 6
        HostHasSsd = $true
        AccessMode = "VPN"
        ExposePublicInternet = $false
        ProductionMigration = "RebuildOrAioRestore"
    } | ConvertTo-Json | Set-Content -Path $ssdPilotJsonPath -Encoding UTF8

    $ssdPilotReport = & (Join-Path $PSScriptRoot "..\Invoke-NasCloudSsdPilotPlan.ps1") -InputJson $ssdPilotJsonPath
    $ssdPilotReportText = $ssdPilotReport -join "`n"

    if ($ssdPilotReportText -notlike "*SSD Pilot Plan*") {
        throw "SSD pilot CLI should print a report heading."
    }

    if ($ssdPilotReportText -notlike "*Hyper-V Ubuntu VM*") {
        throw "SSD pilot CLI should describe the windowed Ubuntu VM path."
    }

    $vmPlanJsonPath = Join-Path $PSScriptRoot "tmp-vm-plan.json"
    [pscustomobject]@{
        Name = "nas-linux-pilot"
        VhdPath = "C:\NasVm\nas-linux-pilot.vhdx"
        VhdSizeGB = 128
        MemoryGB = 12
        CpuCount = 8
        SwitchName = "Default Switch"
        Generation = 2
        EnableSecureBoot = $false
        RemoteAccess = "TailscaleAndSsh"
        FutureHddMode = "OfflinePhysicalDiskAttach"
    } | ConvertTo-Json | Set-Content -Path $vmPlanJsonPath -Encoding UTF8

    $vmReport = & (Join-Path $PSScriptRoot "..\Invoke-NasCloudVmPlan.ps1") -InputJson $vmPlanJsonPath
    $vmReportText = $vmReport -join "`n"

    if ($vmReportText -notlike "*Linux VM Plan*") {
        throw "VM plan CLI should print a report heading."
    }

    if ($vmReportText -notlike "*128 GB*") {
        throw "VM plan CLI should include the 128GB VHD size."
    }

    $productionStorageJsonPath = Join-Path $PSScriptRoot "tmp-production-storage-plan.json"
    [pscustomobject]@{
        Name = "current-windows-4x8tb"
        Disks = @(
            [pscustomobject]@{ Label = "1"; Role = "LiveMirror"; DiskNumber = 1; Model = "ST8000VN 004-2M2101"; Serial = "LIVE-DISK-1"; BusType = "USB"; CapacityTB = 7.28; FileSystem = "exFAT"; DriveLetter = "E:"; IsBoot = $false; IsSystem = $false },
            [pscustomobject]@{ Label = "2"; Role = "LiveMirror"; DiskNumber = 2; Model = "ST8000VN 004-2M2101"; Serial = "LIVE-DISK-2"; BusType = "USB"; CapacityTB = 7.28; FileSystem = "exFAT"; DriveLetter = "F:"; IsBoot = $false; IsSystem = $false },
            [pscustomobject]@{ Label = "3"; Role = "BackupMirror"; DiskNumber = 3; Model = "WDC WD80 EAAZ-00BXBB0"; Serial = "BACKUP-DISK-1"; BusType = "USB"; CapacityTB = 7.28; FileSystem = "exFAT"; DriveLetter = "D:"; IsBoot = $false; IsSystem = $false },
            [pscustomobject]@{ Label = "4"; Role = "BackupMirror"; DiskNumber = 4; Model = "WDC WD80 EAAZ-00BXBB0"; Serial = "BACKUP-DISK-2"; BusType = "USB"; CapacityTB = 7.28; FileSystem = "exFAT"; DriveLetter = "G:"; IsBoot = $false; IsSystem = $false }
        )
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $productionStorageJsonPath -Encoding UTF8

    $productionStorageReport = & (Join-Path $PSScriptRoot "..\Invoke-NasCloudProductionStoragePlan.ps1") -InputJson $productionStorageJsonPath
    $productionStorageReportText = $productionStorageReport -join "`n"

    if ($productionStorageReportText -notlike "*Production Storage Plan*") {
        throw "Production storage plan CLI should print a report heading."
    }

    if ($productionStorageReportText -notlike "*LiveMirror*BackupMirror*") {
        throw "Production storage plan CLI should include live and backup mirror roles."
    }
}
finally {
    if (Test-Path $jsonPath) {
        Remove-Item $jsonPath
    }
    if (Test-Path $hostJsonPath) {
        Remove-Item $hostJsonPath
    }
    if (Test-Path $nextcloudJsonPath) {
        Remove-Item $nextcloudJsonPath
    }
    if (Test-Path $ssdPilotJsonPath) {
        Remove-Item $ssdPilotJsonPath
    }
    if (Test-Path $vmPlanJsonPath) {
        Remove-Item $vmPlanJsonPath
    }
    if (Test-Path $productionStorageJsonPath) {
        Remove-Item $productionStorageJsonPath
    }
}

Write-Host "All NasCloudTools tests passed."

