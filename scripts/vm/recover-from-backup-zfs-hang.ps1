param(
    [string]$VmName = "nas-linux-pilot",
    [int[]]$BackupDiskNumbers = @(3, 4),
    [string]$LogPath = "$PSScriptRoot\..\..\logs\recover-from-backup-zfs-hang.log"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -Path $LogPath -Value $line
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated PowerShell session."
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
Write-Log "Starting recovery for VM '$VmName'. Backup disks to detach: $($BackupDiskNumbers -join ', ')"
Assert-Administrator

$vm = Get-VM -Name $VmName
Write-Log "VM state before recovery: $($vm.State)"

if ($vm.State -ne "Off") {
    Write-Log "Forcing VM power off because guest shutdown is blocked by stuck storage I/O."
    Stop-VM -Name $VmName -TurnOff -Force
}

do {
    Start-Sleep -Seconds 2
    $vm = Get-VM -Name $VmName
    Write-Log "Waiting for VM to turn off. Current state: $($vm.State)"
} while ($vm.State -ne "Off")

$drives = Get-VMHardDiskDrive -VMName $VmName
Write-Log "Attached drives before detach:"
foreach ($drive in $drives) {
    Write-Log ("  Controller={0}:{1} DiskNumber={2} Path={3}" -f $drive.ControllerNumber, $drive.ControllerLocation, $drive.DiskNumber, $drive.Path)
}

$targets = $drives | Where-Object { $_.DiskNumber -in $BackupDiskNumbers }
if ($targets.Count -ne $BackupDiskNumbers.Count) {
    throw "Expected to find backup VM disk attachments for Windows disk numbers $($BackupDiskNumbers -join ', '), found $($targets.Count). Aborting."
}

foreach ($target in $targets) {
    Write-Log ("Detaching backup disk number {0} from VM controller {1}:{2}" -f $target.DiskNumber, $target.ControllerNumber, $target.ControllerLocation)
    Remove-VMHardDiskDrive -VMName $VmName -ControllerType $target.ControllerType -ControllerNumber $target.ControllerNumber -ControllerLocation $target.ControllerLocation
}

Write-Log "Leaving Windows disk numbers $($BackupDiskNumbers -join ', ') offline to avoid Windows mounting partially-created ZFS disks."
Write-Log "Starting VM '$VmName'."
Start-VM -Name $VmName

Start-Sleep -Seconds 5
$vm = Get-VM -Name $VmName
Write-Log "VM state after recovery: $($vm.State)"

$remaining = Get-VMHardDiskDrive -VMName $VmName
Write-Log "Attached drives after detach:"
foreach ($drive in $remaining) {
    Write-Log ("  Controller={0}:{1} DiskNumber={2} Path={3}" -f $drive.ControllerNumber, $drive.ControllerLocation, $drive.DiskNumber, $drive.Path)
}

Write-Log "Recovery script completed."
