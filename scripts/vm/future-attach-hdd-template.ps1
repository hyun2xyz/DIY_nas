param(
    [Parameter(Mandatory = $true)] [int[]] $DiskNumbers,
    [string] $VmName = "nas-linux-pilot",
    [Parameter(Mandatory = $true)] [string[]] $ExpectedSerials,
    [switch] $ConfirmDataLoss
)

$ErrorActionPreference = "Stop"

$principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an Administrator PowerShell."
}

Write-Output "This template is for the future 8TB disks only, after all data is backed up."
Write-Output "It sets selected disks offline in Windows and attaches them to the VM."
Write-Output "Review disk numbers carefully before using."

if (-not $ConfirmDataLoss) {
    throw "Refusing to continue without -ConfirmDataLoss. This operation detaches disks from Windows and can lead to data loss if the wrong disk is selected."
}

if ($DiskNumbers.Count -ne $ExpectedSerials.Count) {
    throw "DiskNumbers and ExpectedSerials must have the same count."
}

for ($index = 0; $index -lt $DiskNumbers.Count; $index++) {
    $diskNumber = $DiskNumbers[$index]
    $disk = Get-Disk -Number $diskNumber
    if ($disk.IsBoot -or $disk.IsSystem) {
        throw "Refusing to attach boot/system disk: $diskNumber"
    }

    $expectedSerial = $ExpectedSerials[$index]
    if ($disk.SerialNumber -ne $expectedSerial) {
        throw "Disk $diskNumber serial mismatch. Expected '$expectedSerial', got '$($disk.SerialNumber)'."
    }

    Set-Disk -Number $diskNumber -IsOffline $true
    Set-Disk -Number $diskNumber -IsReadOnly $false
    Add-VMHardDiskDrive -VMName $VmName -DiskNumber $diskNumber
    Write-Output "Attached physical disk $diskNumber to $VmName"
}
