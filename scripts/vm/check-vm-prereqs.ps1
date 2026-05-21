$ErrorActionPreference = "Stop"

$principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Output "IsAdministrator=$isAdmin"
Write-Output ""
Write-Output "PowerShell Hyper-V commands:"
Get-Command New-VM,New-VHD,Get-VM,Set-VMProcessor,Add-VMHardDiskDrive -ErrorAction SilentlyContinue |
    Select-Object Name,Source |
    Format-Table -AutoSize

Write-Output ""
Write-Output "C: capacity:"
Get-Volume -DriveLetter C | Select-Object DriveLetter,SizeRemaining,Size | Format-List

Write-Output ""
Write-Output "Hyper-V optional feature state requires administrator PowerShell:"
try {
    Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All |
        Select-Object FeatureName,State |
        Format-Table -AutoSize
} catch {
    Write-Output "Hyper-V feature check failed: $($_.Exception.Message)"
}
