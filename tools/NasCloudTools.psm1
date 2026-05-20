function Test-NasCloudDiskCandidate {
    param(
        [Parameter(Mandatory = $true)] [pscustomobject] $Disk,
        [switch] $AllowSmr
    )

    $rejectReasons = New-Object System.Collections.Generic.List[string]
    $reviewReasons = New-Object System.Collections.Generic.List[string]

    if ([int]$Disk.ReallocatedSectors -gt 0) {
        $rejectReasons.Add("Reallocated sectors > 0")
    }

    if ([int]$Disk.CurrentPendingSectors -gt 0) {
        $rejectReasons.Add("Current pending sectors > 0")
    }

    if ([int]$Disk.OfflineUncorrectableSectors -gt 0) {
        $rejectReasons.Add("Offline uncorrectable sectors > 0")
    }

    $smartOverall = Normalize-NasCloudText $Disk.SmartOverall
    if ($smartOverall -and $smartOverall -notin @("healthy", "ok", "passed", "pass")) {
        $rejectReasons.Add("SMART overall status is not healthy")
    }

    $smartLongTest = Normalize-NasCloudText $Disk.SmartLongTest
    if ($smartLongTest -and $smartLongTest -notin @("passed", "pass", "completed without error", "ok")) {
        $rejectReasons.Add("SMART long test did not pass")
    }

    $recordingTechnology = Normalize-NasCloudText $Disk.RecordingTechnology
    if ($recordingTechnology -eq "smr" -and -not $AllowSmr) {
        $rejectReasons.Add("SMR disk rejected unless rebuild-performance risk is explicitly accepted")
    } elseif (-not $recordingTechnology -or $recordingTechnology -eq "unknown") {
        $reviewReasons.Add("Recording technology is unknown; confirm CMR/SMR before pool creation")
    }

    if ($rejectReasons.Count -gt 0) {
        return [pscustomobject]@{
            Label = $Disk.Label
            Approved = $false
            Severity = "Reject"
            Reasons = [string[]]$rejectReasons
        }
    }

    if ($reviewReasons.Count -gt 0) {
        return [pscustomobject]@{
            Label = $Disk.Label
            Approved = $false
            Severity = "Review"
            Reasons = [string[]]$reviewReasons
        }
    }

    [pscustomobject]@{
        Label = $Disk.Label
        Approved = $true
        Severity = "OK"
        Reasons = @("Disk candidate meets the current RAIDZ2 screening rules")
    }
}

function Get-RaidZ2CapacityEstimate {
    param(
        [Parameter(Mandatory = $true)] [int] $DiskCount,
        [Parameter(Mandatory = $true)] [decimal] $DiskSizeTB
    )

    if ($DiskCount -lt 4) {
        throw "RAIDZ2 requires at least 4 disks."
    }

    $usableTB = ($DiskCount - 2) * $DiskSizeTB
    $usableTiB = [math]::Round(($usableTB * 1000000000000) / [math]::Pow(1024, 4), 2)

    [pscustomobject]@{
        DiskCount = $DiskCount
        DiskSizeTB = $DiskSizeTB
        UsableTB = $usableTB
        UsableTiB = $usableTiB
        FaultToleranceDisks = 2
    }
}

function Get-MirrorBackupCapacityEstimate {
    param(
        [Parameter(Mandatory = $true)] [decimal] $LiveDiskSizeTB,
        [Parameter(Mandatory = $true)] [decimal] $BackupDiskSizeTB
    )

    [pscustomobject]@{
        LiveDiskCount = 2
        BackupDiskCount = 2
        LiveUsableTB = $LiveDiskSizeTB
        BackupUsableTB = $BackupDiskSizeTB
        LiveFaultToleranceDisks = 1
        BackupFaultToleranceDisks = 1
        Layout = "live mirror plus backup mirror"
    }
}

function Test-NasCloudProductionStoragePlan {
    param(
        [Parameter(Mandatory = $true)] [pscustomobject] $Plan
    )

    $blockers = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $strengths = New-Object System.Collections.Generic.List[string]

    $disks = @($Plan.Disks)
    if ($disks.Count -ne 4) {
        $blockers.Add("Exactly four 8 TB disks are expected for this production plan")
    }

    $liveDisks = @($disks | Where-Object { $_.Role -eq "LiveMirror" })
    $backupDisks = @($disks | Where-Object { $_.Role -eq "BackupMirror" })

    if ($liveDisks.Count -ne 2) {
        $blockers.Add("LiveMirror must contain exactly two disks")
    } else {
        $strengths.Add("LiveMirror has two disks for one-disk fault tolerance")
    }

    if ($backupDisks.Count -ne 2) {
        $blockers.Add("BackupMirror must contain exactly two disks")
    } else {
        $strengths.Add("BackupMirror has two disks for one-disk fault tolerance")
    }

    $diskNumbers = @($disks | ForEach-Object { [int]$_.DiskNumber })
    if (($diskNumbers | Select-Object -Unique).Count -ne $diskNumbers.Count) {
        $blockers.Add("Disk numbers must be unique")
    }

    $serials = @($disks | ForEach-Object { Normalize-NasCloudText $_.Serial })
    if (($serials | Where-Object { $_ }).Count -ne $disks.Count) {
        $blockers.Add("Every disk must have a serial number before passthrough or pool creation")
    } elseif (($serials | Select-Object -Unique).Count -ne $serials.Count) {
        $blockers.Add("Disk serial numbers must be unique")
    }

    foreach ($disk in $disks) {
        if ([bool]$disk.IsBoot -or [bool]$disk.IsSystem) {
            $blockers.Add("Refusing to use boot/system disk number $($disk.DiskNumber)")
        }

        if ([decimal]$disk.CapacityTB -lt 7.0) {
            $blockers.Add("Disk $($disk.DiskNumber) is smaller than the expected 8 TB class")
        }

        $busType = Normalize-NasCloudText $disk.BusType
        if ($busType -eq "usb") {
            $warnings.Add("Disk $($disk.DiskNumber) is connected over USB; production use is safer on direct SATA/HBA")
        }

        $fileSystem = Normalize-NasCloudText $disk.FileSystem
        if ($fileSystem -and $fileSystem -notin @("raw", "unknown")) {
            $warnings.Add("Disk $($disk.DiskNumber) currently has a $($disk.FileSystem) filesystem; pool creation will erase it")
        }
    }

    $liveModels = @($liveDisks | ForEach-Object { $_.Model })
    if (($liveModels -join " ") -like "*ST8000VN*") {
        $strengths.Add("LiveMirror uses the NAS-class ST8000VN disks")
    }

    $status = if ($blockers.Count -gt 0) {
        "Blocked"
    } elseif ($warnings.Count -gt 0) {
        "Review"
    } else {
        "Ready"
    }

    [pscustomobject]@{
        Name = $Plan.Name
        Status = $status
        RecommendedLayout = "POOL-A: disks 1/2 live mirror; POOL-B: disks 3/4 backup mirror"
        Blockers = [string[]]$blockers
        Warnings = [string[]]$warnings
        Strengths = [string[]]$strengths
        Capacity = Get-MirrorBackupCapacityEstimate -LiveDiskSizeTB 8 -BackupDiskSizeTB 8
    }
}

function ConvertTo-NasCloudDiskMarkdownRow {
    param(
        [Parameter(Mandatory = $true)] [pscustomobject] $Disk
    )

    $assessment = Test-NasCloudDiskCandidate -Disk $Disk
    $approved = if ($assessment.Approved) { "Yes" } else { $assessment.Severity }

    "| $($Disk.Label) | $($Disk.IntendedRole) | $($Disk.Manufacturer) | $($Disk.Model) | $($Disk.Serial) | $($Disk.CapacityTB) TB | $($Disk.RecordingTechnology) | $($Disk.SmartOverall) | $($Disk.SmartLongTest) | $approved |"
}

function Test-NasCloudHostCandidate {
    param(
        [Parameter(Mandatory = $true)] [pscustomobject] $HostInfo
    )

    $blockers = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $strengths = New-Object System.Collections.Generic.List[string]

    $memory = [decimal]$HostInfo.TotalMemoryGB
    if ($memory -le 0) {
        $warnings.Add("RAM could not be detected; confirm at least 32 GB before production use")
    } elseif ($memory -lt 32) {
        $blockers.Add("At least 32 GB RAM is required for the planned first production slice")
    } elseif ($memory -lt 64) {
        $warnings.Add("32 GB RAM is acceptable for a pilot, but 64 GB is preferred before scaling toward 100 users")
    } else {
        $strengths.Add("64 GB or more RAM is suitable for the planned first production slice")
    }

    if (-not [bool]$HostInfo.HasSsdForApps) {
        $blockers.Add("SSD or NVMe app storage is required before adding real users")
    } else {
        $strengths.Add("SSD or NVMe app storage is available")
    }

    if (-not [bool]$HostInfo.SupportsVirtualization) {
        $blockers.Add("Virtualization support should be enabled for VM or container-based testing")
    } else {
        $strengths.Add("Virtualization support is available")
    }

    $network = [decimal]$HostInfo.NetworkGbps
    if ($network -lt 1) {
        $blockers.Add("At least 1 GbE networking is required")
    } elseif ($network -lt 2.5) {
        $warnings.Add("1 GbE is acceptable for pilot use; 2.5 GbE or faster is preferred for many active users")
    } else {
        $strengths.Add("2.5 GbE or faster networking is available")
    }

    $osName = Normalize-NasCloudText $HostInfo.OsName
    if ($osName -like "*windows*" -and -not [bool]$HostInfo.IsDedicatedHost) {
        $warnings.Add("Dedicated NAS/server OS is recommended for production")
    } elseif ([bool]$HostInfo.IsDedicatedHost) {
        $strengths.Add("Host is dedicated to NAS/server duties")
    }

    if (-not [bool]$HostInfo.HasUps) {
        $warnings.Add("UPS is recommended before running the RAIDZ2 pool as production storage")
    } else {
        $strengths.Add("UPS is available for clean shutdown during power loss")
    }

    $status = if ($blockers.Count -gt 0) {
        "Blocked"
    } elseif ($warnings.Count -gt 0) {
        "PilotOnly"
    } else {
        "Ready"
    }

    [pscustomobject]@{
        Name = $HostInfo.Name
        Status = $status
        Blockers = [string[]]$blockers
        Warnings = [string[]]$warnings
        Strengths = [string[]]$strengths
    }
}

function Test-NasCloudNextcloudPlan {
    param(
        [Parameter(Mandatory = $true)] [pscustomobject] $Plan
    )

    $blockers = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $strengths = New-Object System.Collections.Generic.List[string]

    $domain = Normalize-NasCloudText $Plan.Domain
    if (-not $domain) {
        $blockers.Add("Nextcloud domain is required")
    } elseif ($domain.EndsWith(".local")) {
        $blockers.Add("Do not use .local for the Nextcloud domain")
    } elseif ($domain -match "^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$") {
        $strengths.Add("Domain format is suitable for internal DNS")
    } else {
        $warnings.Add("Domain contains unusual characters; verify DNS and certificate behavior before deployment")
    }

    if (-not (Test-AbsoluteLinuxPath $Plan.DataDir)) {
        $blockers.Add("NEXTCLOUD_DATADIR must be an absolute Linux path that starts with /")
    } elseif ($Plan.DataDir -eq "/") {
        $blockers.Add("NEXTCLOUD_DATADIR must not be the filesystem root")
    } else {
        $strengths.Add("NEXTCLOUD_DATADIR is an absolute Linux path")
    }

    if (-not (Test-AbsoluteLinuxPath $Plan.BackupDir)) {
        $warnings.Add("Backup directory is missing or not an absolute Linux path; choose a target outside the app path before production")
    } elseif ($Plan.BackupDir -eq $Plan.DataDir) {
        $blockers.Add("Backup directory must not be the same as NEXTCLOUD_DATADIR")
    } else {
        $strengths.Add("Backup directory is explicit")
    }

    if ([int]$Plan.AioInterfacePort -le 0) {
        $blockers.Add("AIO interface port must be a positive TCP port")
    } elseif ([int]$Plan.AioInterfacePort -ne 8080) {
        $warnings.Add("AIO interface port differs from 8080; document the custom host mapping")
    }

    if ([bool]$Plan.UseReverseProxy) {
        if ([int]$Plan.ApachePort -le 0) {
            $blockers.Add("APACHE_PORT must be a positive TCP port when using a reverse proxy")
        } elseif ([int]$Plan.ApachePort -in @(80, 443, 8080)) {
            $blockers.Add("APACHE_PORT should not collide with standard HTTP/HTTPS or AIO interface ports")
        } else {
            $strengths.Add("Reverse-proxy Apache port is separated from public HTTPS")
        }
    }

    if ([bool]$Plan.ExposePublicInternet -and -not [bool]$Plan.UseVpnOnly) {
        $warnings.Add("Public exposure requires tested backups, HTTPS, 2FA, log review, and rate-limit planning")
    } elseif ([bool]$Plan.UseVpnOnly) {
        $strengths.Add("VPN-only access is suitable for the first production slice")
    }

    if ([bool]$Plan.EnableClamAv) {
        $warnings.Add("ClamAV can consume significant RAM and CPU; enable after the base service is stable")
    }

    if ([bool]$Plan.EnableFullTextSearch) {
        $warnings.Add("Full-text search increases CPU, RAM, and disk workload; enable after pilot testing")
    }

    if ([bool]$Plan.EnableOffice) {
        $warnings.Add("Nextcloud Office adds useful collaboration features but increases memory and CPU load")
    }

    $status = if ($blockers.Count -gt 0) {
        "Blocked"
    } elseif ($warnings.Count -gt 0) {
        "Review"
    } else {
        "Ready"
    }

    [pscustomobject]@{
        Domain = $Plan.Domain
        Status = $status
        Blockers = [string[]]$blockers
        Warnings = [string[]]$warnings
        Strengths = [string[]]$strengths
    }
}

function Test-NasCloudSsdPilotPlan {
    param(
        [Parameter(Mandatory = $true)] [pscustomobject] $Plan
    )

    $blockers = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $strengths = New-Object System.Collections.Generic.List[string]

    $mode = Normalize-NasCloudText $Plan.Mode
    if ($mode -eq "hypervubuntuvm") {
        $strengths.Add("Hyper-V Ubuntu VM gives a windowed Linux pilot while Windows remains the host OS")
    } elseif ($mode -eq "dockerdesktopwsl2") {
        $warnings.Add("Docker Desktop WSL2 is faster to start, but it is less like the final dedicated NAS host")
    } else {
        $blockers.Add("Mode must be HyperVUbuntuVM or DockerDesktopWSL2")
    }

    if ([bool]$Plan.HostKeepsWindows) {
        $strengths.Add("Windows remains the host OS")
    } else {
        $warnings.Add("This pilot plan assumes Windows remains installed; confirm if converting the host OS instead")
    }

    if (-not [bool]$Plan.HostHasSsd) {
        $blockers.Add("SSD or NVMe storage is required for the pilot VM/container data")
    } else {
        $strengths.Add("Pilot storage is planned on SSD/NVMe")
    }

    if (-not $Plan.PilotStoragePath) {
        $blockers.Add("Pilot storage path is required")
    }

    $memory = [decimal]$Plan.VmMemoryGB
    if ($memory -lt 6) {
        $blockers.Add("Allocate at least 6 GB RAM to the pilot environment")
    } elseif ($memory -lt 8) {
        $warnings.Add("6 GB RAM can work for a small pilot, but 8 GB is preferred")
    } else {
        $strengths.Add("Pilot memory allocation is suitable")
    }

    $disk = [decimal]$Plan.VmDiskGB
    if ($disk -lt 100) {
        $blockers.Add("Allocate at least 100 GB virtual disk for a disposable Nextcloud pilot")
    } else {
        $strengths.Add("Pilot virtual disk size is suitable")
    }

    $cpu = [int]$Plan.VmCpuCount
    if ($cpu -lt 4) {
        $warnings.Add("Allocate at least 4 vCPU if possible for smoother Nextcloud background jobs")
    } else {
        $strengths.Add("Pilot vCPU allocation is suitable")
    }

    $accessMode = Normalize-NasCloudText $Plan.AccessMode
    if ([bool]$Plan.ExposePublicInternet -or $accessMode -eq "publicinternet") {
        $blockers.Add("Do not expose the SSD pilot directly to the public internet")
    } elseif ($accessMode -eq "vpn") {
        $strengths.Add("VPN access is the recommended remote access method for the pilot")
    } elseif ($accessMode -eq "lan") {
        $strengths.Add("LAN-only access is safe for the first pilot")
    } else {
        $warnings.Add("AccessMode should be LAN or VPN for the SSD pilot")
    }

    $migration = Normalize-NasCloudText $Plan.ProductionMigration
    if ($migration -eq "movedatadirinplace") {
        $blockers.Add("Do not plan an in-place datadir move from SSD pilot to RAIDZ2 production")
    } elseif ($migration -eq "rebuildoraiorestore") {
        $strengths.Add("Production migration uses rebuild or AIO backup/restore instead of moving datadir in place")
    } else {
        $warnings.Add("Production migration should be RebuildOrAioRestore")
    }

    $status = if ($blockers.Count -gt 0) {
        "Blocked"
    } elseif ($warnings.Count -gt 0) {
        "Review"
    } else {
        "Ready"
    }

    [pscustomobject]@{
        Mode = $Plan.Mode
        Status = $status
        Blockers = [string[]]$blockers
        Warnings = [string[]]$warnings
        Strengths = [string[]]$strengths
    }
}

function Test-NasCloudVmPlan {
    param(
        [Parameter(Mandatory = $true)] [pscustomobject] $Plan
    )

    $blockers = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $strengths = New-Object System.Collections.Generic.List[string]

    if (-not ($Plan.Name -match '^[A-Za-z0-9][A-Za-z0-9_-]{2,63}$')) {
        $blockers.Add("VM name must use letters, numbers, underscores, or hyphens only")
    }

    $vhdPath = [string]$Plan.VhdPath
    if (-not $vhdPath.EndsWith(".vhdx", [StringComparison]::OrdinalIgnoreCase)) {
        $blockers.Add("VHD path must point to a .vhdx file")
    } elseif ([IO.Path]::IsPathRooted($vhdPath) -and $vhdPath -match '^[A-Za-z]:') {
        $strengths.Add("VHDX virtual disk avoids resizing the Windows OS partition")
    } else {
        $blockers.Add("VHD path must be an absolute Windows path")
    }

    if ([decimal]$Plan.VhdSizeGB -lt 80) {
        $blockers.Add("VHD size must be at least 80 GB for an Ubuntu/Docker/Nextcloud pilot")
    } elseif ([decimal]$Plan.VhdSizeGB -lt 128) {
        $warnings.Add("VHD size below 128 GB is acceptable only for a small pilot")
    } else {
        $strengths.Add("VHD size is suitable for the Linux pilot")
    }

    if ([decimal]$Plan.MemoryGB -lt 8) {
        $blockers.Add("VM memory must be at least 8 GB")
    } elseif ([decimal]$Plan.MemoryGB -lt 12) {
        $warnings.Add("8 GB memory can work; 12 GB is preferred for Nextcloud testing")
    } else {
        $strengths.Add("VM memory allocation is suitable")
    }

    if ([int]$Plan.CpuCount -lt 4) {
        $warnings.Add("Allocate at least 4 vCPU for smoother updates and container workloads")
    } else {
        $strengths.Add("VM CPU allocation is suitable")
    }

    if (-not $Plan.SwitchName) {
        $blockers.Add("Hyper-V switch name is required")
    }

    if ([int]$Plan.Generation -ne 2) {
        $warnings.Add("Generation 2 VM is preferred for Ubuntu Server")
    } else {
        $strengths.Add("Generation 2 VM is selected")
    }

    $remoteAccess = Normalize-NasCloudText $Plan.RemoteAccess
    if ($remoteAccess -eq "publicinternet") {
        $blockers.Add("Do not expose VM management or cloud services directly to the public internet")
    } elseif ($remoteAccess -in @("tailscaleandssh", "wireguardandssh", "lanandssh")) {
        $strengths.Add("Remote management avoids direct public exposure")
    } else {
        $warnings.Add("Remote access should be TailscaleAndSsh, WireGuardAndSsh, or LanAndSsh")
    }

    $futureHddMode = Normalize-NasCloudText $Plan.FutureHddMode
    if ($futureHddMode -eq "windowsmanageddisks") {
        $blockers.Add("Future NAS HDDs must not be managed by Windows if the VM will own ZFS/RAIDZ2")
    } elseif ($futureHddMode -eq "offlinephysicaldiskattach") {
        $strengths.Add("Future HDD plan keeps disks offline in Windows before VM attachment")
    } else {
        $warnings.Add("FutureHddMode should be OfflinePhysicalDiskAttach for VM-owned RAIDZ2")
    }

    $status = if ($blockers.Count -gt 0) {
        "Blocked"
    } elseif ($warnings.Count -gt 0) {
        "Review"
    } else {
        "Ready"
    }

    [pscustomobject]@{
        Name = $Plan.Name
        Status = $status
        Blockers = [string[]]$blockers
        Warnings = [string[]]$warnings
        Strengths = [string[]]$strengths
    }
}

function Test-AbsoluteLinuxPath {
    param($Value)

    if ($null -eq $Value) {
        return $false
    }

    $text = $Value.ToString().Trim()
    $text.StartsWith("/") -and $text.Length -gt 1
}

function Normalize-NasCloudText {
    param($Value)

    if ($null -eq $Value) {
        return ""
    }

    $Value.ToString().Trim().ToLowerInvariant()
}

Export-ModuleMember -Function Test-NasCloudDiskCandidate, Get-RaidZ2CapacityEstimate, Get-MirrorBackupCapacityEstimate, Test-NasCloudProductionStoragePlan, ConvertTo-NasCloudDiskMarkdownRow, Test-NasCloudHostCandidate, Test-NasCloudNextcloudPlan, Test-NasCloudSsdPilotPlan, Test-NasCloudVmPlan
