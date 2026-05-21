$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$pidPath = Join-Path $root "nas-pilot-server.pid"
$port = 8790

$existing = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) {
    Write-Output "NAS pilot already appears to be listening on port $port."
    exit 0
}

$process = Start-Process `
    -FilePath node `
    -ArgumentList "src/server.mjs" `
    -WorkingDirectory $root `
    -WindowStyle Hidden `
    -PassThru

$process.Id | Set-Content -Path $pidPath -Encoding ASCII
Start-Sleep -Seconds 2

$health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health"
Write-Output "Started NAS pilot cloud."
Write-Output "PID=$($process.Id)"
Write-Output "URL=http://127.0.0.1:$port"
Write-Output "DataDir=$($health.dataDir)"
