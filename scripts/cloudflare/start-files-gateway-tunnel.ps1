[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$TokenFile,
    [switch]$Foreground
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
if (-not $TokenFile) {
    $TokenFile = Join-Path $ProjectRoot 'secrets\cloudflared-tunnel-token.dpapi'
}

function Get-CloudflaredPath {
    $command = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidate = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter cloudflared.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($candidate) {
        return $candidate.FullName
    }

    $programFilesCandidate = Get-ChildItem "$env:ProgramFiles" -Recurse -Filter cloudflared.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($programFilesCandidate) {
        return $programFilesCandidate.FullName
    }

    throw 'cloudflared.exe was not found.'
}

if (-not (Test-Path -LiteralPath $TokenFile)) {
    throw "Token file not found: $TokenFile. Run save-copied-tunnel-token.ps1 first."
}

$secureText = (Get-Content -LiteralPath $TokenFile -Raw).Trim()
$secure = ConvertTo-SecureString $secureText
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

$cloudflared = Get-CloudflaredPath
$logDir = Join-Path $ProjectRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stdout = Join-Path $logDir 'cloudflared-tunnel.out.log'
$stderr = Join-Path $logDir 'cloudflared-tunnel.err.log'

$existingTokenTunnel = Get-CimInstance Win32_Process -Filter "Name = 'cloudflared.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match '\btunnel\b' -and $_.CommandLine -match '\brun\b' -and $_.CommandLine -notmatch '\b--url\b' } |
    Select-Object -First 1
if ($existingTokenTunnel) {
    Write-Host "cloudflared tunnel is already running: PID=$($existingTokenTunnel.ProcessId)"
    exit 0
}

$arguments = @('tunnel', '--no-autoupdate', 'run')

if ($Foreground) {
    $env:TUNNEL_TOKEN = $token
    & $cloudflared @arguments
    exit $LASTEXITCODE
}

Set-Content -LiteralPath $stdout -Value '' -Encoding UTF8
Set-Content -LiteralPath $stderr -Value '' -Encoding UTF8

$self = $PSCommandPath
$process = Start-Process -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$self`"", '-Foreground') `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

Write-Host "Started cloudflared tunnel process: PID=$($process.Id)"
Write-Host "stdout: $stdout"
Write-Host "stderr: $stderr"
