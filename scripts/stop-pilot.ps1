$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$pidPath = Join-Path $root "nas-pilot-server.pid"

if (-not (Test-Path -LiteralPath $pidPath)) {
    Write-Output "No PID file found. Nothing stopped."
    exit 0
}

$serverPid = [int](Get-Content -LiteralPath $pidPath -Raw)
$process = Get-Process -Id $serverPid -ErrorAction SilentlyContinue

if ($process) {
    Stop-Process -Id $serverPid -Force
    Write-Output "Stopped NAS pilot cloud. PID=$serverPid"
} else {
    Write-Output "PID file existed, but process was not running. PID=$serverPid"
}

Remove-Item -LiteralPath $pidPath -Force
