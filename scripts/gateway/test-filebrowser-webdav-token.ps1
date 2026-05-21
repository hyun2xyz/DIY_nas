[CmdletBinding()]
param(
    [string] $EnvPath = ".\secrets\drive.env",
    [string] $TestPath,
    [switch] $ShowPermissions,
    [switch] $Overwrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-DriveEnv {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing env file: $Path"
    }

    $result = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) {
            continue
        }
        $parts = $line -split "=", 2
        if ($parts.Count -eq 2) {
            $result[$parts[0]] = $parts[1]
        }
    }
    return $result
}

function Join-UrlPath {
    param(
        [string] $Left,
        [string] $Right
    )

    return "$($Left.TrimEnd('/'))/$($Right.TrimStart('/'))"
}

$driveEnv = Read-DriveEnv -Path $EnvPath
$webDavUrl = [string] $driveEnv["DIY_NAS_DRIVE_WEBDAV_URL"]
$root = [string] $driveEnv["DIY_NAS_DRIVE_ROOT"]
$username = [string] $driveEnv["DIY_NAS_DRIVE_USERNAME"]
$token = [string] $driveEnv["DIY_NAS_DRIVE_PASSWORD_OR_TOKEN"]

if ([string]::IsNullOrWhiteSpace($webDavUrl)) {
    throw "DIY_NAS_DRIVE_WEBDAV_URL is missing in $EnvPath"
}
if ([string]::IsNullOrWhiteSpace($username)) {
    throw "DIY_NAS_DRIVE_USERNAME is missing in $EnvPath"
}
if ([string]::IsNullOrWhiteSpace($token)) {
    throw "DIY_NAS_DRIVE_PASSWORD_OR_TOKEN is missing in $EnvPath"
}
if ([string]::IsNullOrWhiteSpace($TestPath)) {
    if ([string]::IsNullOrWhiteSpace($root)) {
        $TestPath = "hi.txt"
    }
    else {
        $TestPath = "$($root.Trim('/'))/hi.txt"
    }
}

$auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$username`:$token"))
$headers = @{ Authorization = "Basic $auth" }
$uri = Join-UrlPath -Left $webDavUrl -Right $TestPath

if ($ShowPermissions) {
    $baseUrl = [string] $driveEnv["DIY_NAS_DRIVE_BASE_URL"]
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        throw "DIY_NAS_DRIVE_BASE_URL is missing in $EnvPath"
    }
    $selfUri = "$($baseUrl.TrimEnd('/'))/api/users?id=self"
    $selfResponse = Invoke-WebRequest -UseBasicParsing -Method GET -Uri $selfUri -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 30
    $self = $selfResponse.Content | ConvertFrom-Json
    Write-Host "FileBrowser user: $($self.username)"
    Write-Host "Permissions:"
    Write-Host "  download: $($self.permissions.download)"
    Write-Host "  create:   $($self.permissions.create)"
    Write-Host "  modify:   $($self.permissions.modify)"
    Write-Host "  api:      $($self.permissions.api)"
    Write-Host "  delete:   $($self.permissions.delete)"
    Write-Host "  admin:    $($self.permissions.admin)"
    Write-Host "  share:    $($self.permissions.share)"
    Write-Host "  realtime: $($self.permissions.realtime)"
    Write-Host "Scopes:"
    $self.scopes | ForEach-Object {
        Write-Host "  $($_.name): $($_.scope)"
    }
}

Write-Host "Testing WebDAV GET without printing token."
Write-Host "URL: $uri"
$getResponse = Invoke-WebRequest -UseBasicParsing -Method GET -Uri $uri -Headers $headers -TimeoutSec 30
Write-Host "GET OK: HTTP $([int] $getResponse.StatusCode), $($getResponse.RawContentLength) bytes"

if ($Overwrite) {
    $body = "webdav overwrite test $(Get-Date -Format o)`n"
    $putResponse = Invoke-WebRequest -UseBasicParsing -Method PUT -Uri $uri -Headers $headers -Body $body -ContentType "text/plain; charset=utf-8" -TimeoutSec 30
    Write-Host "PUT overwrite OK: HTTP $([int] $putResponse.StatusCode)"
}
