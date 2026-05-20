[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
if (-not $LogPath) {
    $LogPath = Join-Path $ProjectRoot 'logs\cloudflared-service-install.log'
}

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$stamp] $Message"
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
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

$setupScript = Join-Path $ProjectRoot 'scripts\cloudflare\setup-files-gateway-tunnel.ps1'
if (-not (Test-Path -LiteralPath $setupScript)) {
    throw "Setup script not found: $setupScript"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
if (Test-Path -LiteralPath $LogPath) {
    Remove-Item -LiteralPath $LogPath -Force
}

$clipboard = Get-Clipboard -Raw
if (-not $clipboard) {
    throw 'Clipboard is empty. Copy the Cloudflare cloudflared service install command first.'
}

$token = $null
$jwtPrefix = 'e' + 'yJ'
if ($clipboard -match 'cloudflared(?:\.exe)?\s+service\s+install\s+(?<token>\S+)') {
    $token = $Matches.token
} elseif ($clipboard.Trim() -match "^$jwtPrefix\S+$") {
    $token = $clipboard.Trim()
}

if (-not $token) {
    throw 'Clipboard does not look like a Cloudflare tunnel token or service install command.'
}

$cloudflared = Get-CloudflaredPath
Write-Log "cloudflared path: $cloudflared"
Write-Log 'Installing cloudflared service using the copied tunnel token. The token will not be printed.'

$installOutput = & $cloudflared service install $token 2>&1
$installExitCode = $LASTEXITCODE
foreach ($line in $installOutput) {
    $safeLine = ([string]$line).Replace($token, '<redacted>')
    Write-Log "cloudflared: $safeLine"
}
Write-Log "cloudflared service install exit code: $installExitCode"
if ($installExitCode -ne 0) {
    throw "cloudflared service install failed with exit code $installExitCode"
}

Start-Service cloudflared

Write-Log 'cloudflared service status:'
$service = Get-Service cloudflared
Write-Log "Name=$($service.Name); Status=$($service.Status); StartType=$($service.StartType)"
