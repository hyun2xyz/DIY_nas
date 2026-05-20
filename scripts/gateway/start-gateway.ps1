[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [int]$Port = 8791
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1

if ($listener) {
    Write-Host "Gateway already listening on 127.0.0.1:$Port"
    exit 0
}

$logs = Join-Path $ProjectRoot 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null

Start-Process `
    -WindowStyle Hidden `
    -FilePath 'npm.cmd' `
    -ArgumentList @('run', 'gateway') `
    -WorkingDirectory $ProjectRoot `
    -RedirectStandardOutput (Join-Path $logs 'gateway.out.log') `
    -RedirectStandardError (Join-Path $logs 'gateway.err.log')

Start-Sleep -Seconds 3

$listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $listener) {
    throw "Gateway did not start on 127.0.0.1:$Port. Check logs\gateway.err.log."
}

Write-Host "Gateway started on 127.0.0.1:$Port"
