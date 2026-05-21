param(
    [string] $PlanPath = ".\samples\linux-vm-plan.sample.json",
    [string] $IsoPath = ""
)

$ErrorActionPreference = "Stop"

$principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an Administrator PowerShell."
}

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$planFullPath = if ([IO.Path]::IsPathRooted($PlanPath)) { $PlanPath } else { Join-Path $root $PlanPath }
$plan = Get-Content -LiteralPath $planFullPath -Raw | ConvertFrom-Json

Import-Module Hyper-V -ErrorAction Stop

$vmRoot = Split-Path -Parent $plan.VhdPath
New-Item -ItemType Directory -Path $vmRoot -Force | Out-Null

if (Get-VM -Name $plan.Name -ErrorAction SilentlyContinue) {
    throw "VM already exists: $($plan.Name)"
}

if (-not (Test-Path -LiteralPath $plan.VhdPath)) {
    New-VHD -Path $plan.VhdPath -SizeBytes ([int64]$plan.VhdSizeGB * 1GB) -Dynamic | Out-Null
}

New-VM `
    -Name $plan.Name `
    -Generation ([int]$plan.Generation) `
    -MemoryStartupBytes ([int64]$plan.MemoryGB * 1GB) `
    -VHDPath $plan.VhdPath `
    -SwitchName $plan.SwitchName |
    Out-Null

Set-VMProcessor -VMName $plan.Name -Count ([int]$plan.CpuCount)
Set-VMMemory -VMName $plan.Name -DynamicMemoryEnabled $true -MinimumBytes 4GB -StartupBytes ([int64]$plan.MemoryGB * 1GB) -MaximumBytes ([int64]$plan.MemoryGB * 1GB)

if ([int]$plan.Generation -eq 2) {
    Set-VMFirmware -VMName $plan.Name -EnableSecureBoot Off
}

if ($IsoPath) {
    $isoFullPath = if ([IO.Path]::IsPathRooted($IsoPath)) { $IsoPath } else { Join-Path $root $IsoPath }
    if (-not (Test-Path -LiteralPath $isoFullPath)) {
        throw "ISO not found: $isoFullPath"
    }
    Add-VMDvdDrive -VMName $plan.Name -Path $isoFullPath
    $dvd = Get-VMDvdDrive -VMName $plan.Name
    Set-VMFirmware -VMName $plan.Name -FirstBootDevice $dvd
}

Write-Output "Created VM: $($plan.Name)"
Write-Output "VHDX: $($plan.VhdPath)"
Write-Output "Start it from Hyper-V Manager or run:"
Write-Output "Start-VM -Name $($plan.Name)"
