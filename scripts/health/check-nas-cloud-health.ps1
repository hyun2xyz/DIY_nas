param(
    [string] $VmHost = "nas-linux-pilot.local",
    [string] $VmUser = "ubuntu",
    [string] $SshKeyPath = "$env:USERPROFILE\.ssh\nas_linux_pilot_ed25519",
    [string] $NextcloudStatusUrl = "http://nas-linux-pilot.local:8080/status.php",
    [string] $GatewayHealthUrl = "http://127.0.0.1:8791/health",
    [string] $DriveUrl = "http://127.0.0.1:8791/drive",
    [string] $PublicGatewayHealthUrl = "",
    [string] $LocalBackupRoot = "$env:USERPROFILE\nas-cloud-backups",
    [string] $MirrorBackupRoot = "N:\nextcloud-cold",
    [string] $TaskName = "NasCloudDailyNextcloudBackup"
)

$ErrorActionPreference = "Stop"
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string] $Check,
        [string] $Status,
        [string] $Detail
    )

    $results.Add([pscustomobject]@{
        Check = $Check
        Status = $Status
        Detail = $Detail
    })
}

function Test-BackupChecksum {
    param([System.IO.FileInfo] $Backup)

    $checksumPath = "$($Backup.FullName).sha256"
    if (-not (Test-Path -LiteralPath $checksumPath)) {
        throw "Missing checksum file: $checksumPath"
    }

    $expected = (Get-Content -LiteralPath $checksumPath -Raw).Trim().Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)[0].ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Backup.FullName).Hash.ToLowerInvariant()

    if ($actual -ne $expected) {
        throw "Checksum mismatch for $($Backup.FullName)"
    }

    return $actual
}

try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $NextcloudStatusUrl -TimeoutSec 10
    $status = $response.Content | ConvertFrom-Json
    if ($response.StatusCode -eq 200 -and $status.installed -eq $true -and $status.maintenance -eq $false) {
        Add-Result "Nextcloud HTTP" "OK" "HTTP 200, version $($status.versionstring), maintenance=false"
    } else {
        Add-Result "Nextcloud HTTP" "FAIL" "Unexpected status: HTTP $($response.StatusCode), content=$($response.Content)"
    }
} catch {
    Add-Result "Nextcloud HTTP" "FAIL" $_.Exception.Message
}

try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $GatewayHealthUrl -TimeoutSec 10
    $status = $response.Content | ConvertFrom-Json
    if ($response.StatusCode -eq 200 -and $status.ok -eq $true) {
        Add-Result "Gateway API" "OK" "HTTP 200, integrations=$($status.integrations.Count)"
    } else {
        Add-Result "Gateway API" "FAIL" "Unexpected status: HTTP $($response.StatusCode), content=$($response.Content)"
    }
} catch {
    Add-Result "Gateway API" "FAIL" $_.Exception.Message
}

try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $DriveUrl -TimeoutSec 10
    if ($response.StatusCode -eq 200 -and $response.Content -match 'Drive password') {
        Add-Result "Gateway Drive UI" "OK" "HTTP 200, password login page served"
    } else {
        Add-Result "Gateway Drive UI" "FAIL" "Unexpected Drive UI response: HTTP $($response.StatusCode)"
    }
} catch {
    Add-Result "Gateway Drive UI" "FAIL" $_.Exception.Message
}

if (-not [string]::IsNullOrWhiteSpace($PublicGatewayHealthUrl)) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $PublicGatewayHealthUrl -TimeoutSec 10
        $status = $response.Content | ConvertFrom-Json
        if ($response.StatusCode -eq 200 -and $status.ok -eq $true) {
            Add-Result "Public Gateway HTTPS" "OK" "HTTP 200"
        } else {
            Add-Result "Public Gateway HTTPS" "FAIL" "Unexpected status: HTTP $($response.StatusCode), content=$($response.Content)"
        }
    } catch {
        Add-Result "Public Gateway HTTPS" "FAIL" $_.Exception.Message
    }
}

try {
    $pool = Get-StoragePool -FriendlyName NasBackupPool
    $vdisk = Get-VirtualDisk -FriendlyName NasBackupMirror
    $volume = Get-Volume -DriveLetter N
    if ($pool.HealthStatus -eq "Healthy" -and $vdisk.HealthStatus -eq "Healthy" -and $volume.HealthStatus -eq "Healthy") {
        Add-Result "Windows backup mirror" "OK" "Pool=$($pool.OperationalStatus); VDisk=$($vdisk.OperationalStatus); Volume=N: $([math]::Round($volume.SizeRemaining / 1TB, 2)) TiB free"
    } else {
        Add-Result "Windows backup mirror" "FAIL" "Pool=$($pool.HealthStatus); VDisk=$($vdisk.HealthStatus); Volume=$($volume.HealthStatus)"
    }
} catch {
    Add-Result "Windows backup mirror" "FAIL" $_.Exception.Message
}

try {
    $task = Get-ScheduledTask -TaskName $TaskName
    $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
    if ($task.State -in @("Ready", "Running") -and $taskInfo.LastTaskResult -eq 0) {
        Add-Result "Scheduled backup task" "OK" "State=$($task.State); LastRun=$($taskInfo.LastRunTime); NextRun=$($taskInfo.NextRunTime)"
    } else {
        Add-Result "Scheduled backup task" "WARN" "State=$($task.State); LastTaskResult=$($taskInfo.LastTaskResult); NextRun=$($taskInfo.NextRunTime)"
    }
} catch {
    Add-Result "Scheduled backup task" "FAIL" $_.Exception.Message
}

foreach ($backupRoot in @($LocalBackupRoot, $MirrorBackupRoot)) {
    try {
        $backup = Get-ChildItem -Path $backupRoot -Filter "nextcloud-cold-*.tar.gz" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if (-not $backup) {
            Add-Result "Latest backup $backupRoot" "FAIL" "No nextcloud-cold-*.tar.gz backup found."
            continue
        }

        $hash = Test-BackupChecksum -Backup $backup
        Add-Result "Latest backup $backupRoot" "OK" "$($backup.Name), $([math]::Round($backup.Length / 1MB, 1)) MiB, SHA256=$($hash.Substring(0, 12))..."
    } catch {
        Add-Result "Latest backup $backupRoot" "FAIL" $_.Exception.Message
    }
}

try {
    if (-not (Test-Path -LiteralPath $SshKeyPath)) {
        throw "SSH key not found: $SshKeyPath"
    }

    $remote = "$VmUser@$VmHost"
    $sshOutput = & ssh -i $SshKeyPath -o BatchMode=yes -o StrictHostKeyChecking=accept-new $remote "zpool status -x livepool; zfs list -H -o name,avail,mountpoint livepool/nextcloud-data; findmnt -n /srv/nas/live/nextcloud-data"
    if ($LASTEXITCODE -ne 0) {
        throw ($sshOutput -join "`n")
    }

    $joined = $sshOutput -join " | "
    if ($joined -match "pool 'livepool' is healthy" -or $joined -match "all pools are healthy") {
        Add-Result "Ubuntu ZFS livepool" "OK" $joined
    } else {
        Add-Result "Ubuntu ZFS livepool" "WARN" $joined
    }
} catch {
    Add-Result "Ubuntu ZFS livepool" "FAIL" $_.Exception.Message
}

$results | Format-Table -AutoSize

if ($results.Status -contains "FAIL") {
    exit 1
}
