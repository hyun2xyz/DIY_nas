[CmdletBinding()]
param(
    [string] $BaseUrl = "https://drive.example.com",
    [string] $WebDavUrl = "https://drive.example.com/dav/main/",
    [string] $Root = "FILES",
    [string] $Username = "service_upload",
    [string] $TokenName = "service-upload",
    [int] $Days = 3650,
    [int] $MaxUploadBytes = 10485760,
    [string] $PublicShareHash = "<PUBLIC_SHARE_HASH>",
    [string] $OutputEnvPath = ".\secrets\drive.env",
    [switch] $UseCustomPermissionsToken,
    [switch] $SkipWebDavValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertFrom-SecureStringToPlainText {
    param([securestring] $SecureString)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Join-UrlPath {
    param(
        [string] $Left,
        [string] $Right
    )

    return "$($Left.TrimEnd('/'))/$($Right.TrimStart('/'))"
}

function Join-WebDavRootPath {
    param(
        [string] $Root,
        [string] $FileName
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        return $FileName
    }
    return "$($Root.Trim('/'))/$FileName"
}

function Invoke-FileBrowserRequest {
    param(
        [string] $Method,
        [string] $Uri,
        [hashtable] $Headers,
        [object] $Body,
        [Microsoft.PowerShell.Commands.WebRequestSession] $WebSession,
        [string] $ContentType
    )

    $params = @{
        Method = $Method
        Uri = $Uri
        UseBasicParsing = $true
        TimeoutSec = 30
    }
    if ($Headers) { $params.Headers = $Headers }
    if ($Body -ne $null) { $params.Body = $Body }
    if ($WebSession) { $params.WebSession = $WebSession }
    if ($ContentType) { $params.ContentType = $ContentType }

    try {
        return Invoke-WebRequest @params
    }
    catch {
        $response = $_.Exception.Response
        if ($response -and $response.StatusCode) {
            $statusCode = [int] $response.StatusCode
            $responseBody = ""
            try {
                $stream = $response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            }
            catch {
                $responseBody = ""
            }
            if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
                throw "HTTP $statusCode from $Uri`n$responseBody"
            }
            throw "HTTP $statusCode from $Uri"
        }
        throw
    }
}

function Invoke-FileBrowserLogin {
    param(
        [string] $LoginUri,
        [hashtable] $Headers,
        [Microsoft.PowerShell.Commands.WebRequestSession] $WebSession,
        [string] $Username
    )

    try {
        return Invoke-FileBrowserRequest -Method "POST" -Uri $LoginUri -Headers $Headers -WebSession $WebSession
    }
    catch {
        $message = [string] $_.Exception.Message
        if ($message -like "HTTP 401*") {
            throw @"
FileBrowser login failed for '$Username'.

This means FileBrowser rejected the normal login password for that account.
Check these first:
- The user '$Username' exists in FileBrowser.
- You entered the normal FileBrowser password for '$Username', not an API token.
- You did not paste a public share hash or old NAS_DRIVE_PASSWORD.
- If this is a new upload-only account, create it first and grant api/create/modify/download.

After login succeeds, this script will create the WebDAV API token and save it without printing it.
"@
        }
        throw
    }
}

function Invoke-WebDavValidationRequest {
    param(
        [string] $Method,
        [string] $Uri,
        [hashtable] $Headers,
        [object] $Body,
        [string] $ContentType,
        [string] $Username,
        [string] $Root
    )

    try {
        return Invoke-FileBrowserRequest -Method $Method -Uri $Uri -Headers $Headers -Body $Body -ContentType $ContentType
    }
    catch {
        $message = [string] $_.Exception.Message
        if ($message -like "HTTP 403*") {
            throw @"
FileBrowser WebDAV validation was forbidden for '$Username'.

The API token was created, but FileBrowser denied write/read access to:
$Uri

Check these settings:
- User '$Username' scope should be '/' when this script uses Root='$Root'.
- User '$Username' needs download/create/modify/api enabled.
- User '$Username' should have delete/admin/share/realtime disabled for upload-only use.
- Access Rules must allow '$Username' to access '/$Root'.
- The folder '/$Root' must exist in the 'main' WebDAV source.

If the user scope is '/$Root', do not also use Root='$Root'; that double-counts the path.
"@
        }
        throw
    }
}

function New-BasicAuthHeader {
    param(
        [string] $User,
        [string] $Secret
    )

    $pair = "$User`:$Secret"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    return @{ Authorization = "Basic $encoded" }
}

$BaseUrl = $BaseUrl.TrimEnd("/")
$WebDavUrl = $WebDavUrl.TrimEnd("/") + "/"
$Root = $Root.Trim("/")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tokenDisplayName = "$TokenName-$timestamp"

if ($UseCustomPermissionsToken) {
    Write-Host "Creating FileBrowser API token with explicit create/modify/download permissions for user '$Username'."
}
else {
    Write-Host "Creating FileBrowser minimal API token for user '$Username'."
}
Write-Host "Token value will be written to $OutputEnvPath and will not be printed."

$securePassword = Read-Host "FileBrowser password for $Username" -AsSecureString
$plainPassword = ConvertFrom-SecureStringToPlainText $securePassword
try {
    $loginUri = "$BaseUrl/api/auth/login?username=$([Uri]::EscapeDataString($Username))"
    $loginHeaders = @{
        "X-Password" = [Uri]::EscapeDataString($plainPassword)
        "X-Secret" = ""
    }

    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    Invoke-FileBrowserLogin -LoginUri $loginUri -Headers $loginHeaders -WebSession $session -Username $Username | Out-Null

    $selfUri = "$BaseUrl/api/users?id=self"
    $selfResponse = Invoke-FileBrowserRequest -Method "GET" -Uri $selfUri -WebSession $session
    $self = $selfResponse.Content | ConvertFrom-Json
    $permissions = $self.permissions
    foreach ($permissionName in @("api", "create", "modify", "download")) {
        if (-not $permissions.$permissionName) {
            throw "User '$Username' lacks required FileBrowser permission '$permissionName'."
        }
    }

    $tokenUri = "$BaseUrl/api/auth/token?name=$([Uri]::EscapeDataString($tokenDisplayName))&days=$Days"
    if ($UseCustomPermissionsToken) {
        $tokenUri += "&permissions=create,modify,download"
    }
    $tokenResponse = Invoke-FileBrowserRequest -Method "POST" -Uri $tokenUri -WebSession $session
    $tokenJson = $tokenResponse.Content | ConvertFrom-Json
    $token = [string] $tokenJson.token
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "FileBrowser did not return an API token."
    }

    if (-not $SkipWebDavValidation) {
        $authHeaders = New-BasicAuthHeader -User $Username -Secret $token
        $testName = "codex-webdav-token-check-$timestamp.txt"
        $testUri = Join-UrlPath -Left $WebDavUrl -Right (Join-WebDavRootPath -Root $Root -FileName $testName)
        $firstBody = [Text.Encoding]::UTF8.GetBytes("create check $timestamp`n")
        $secondBodyText = "modify/download check $timestamp`n"
        $secondBody = [Text.Encoding]::UTF8.GetBytes($secondBodyText)

        Invoke-WebDavValidationRequest -Method "PUT" -Uri $testUri -Headers $authHeaders -Body $firstBody -ContentType "text/plain" -Username $Username -Root $Root | Out-Null
        Invoke-WebDavValidationRequest -Method "PUT" -Uri $testUri -Headers $authHeaders -Body $secondBody -ContentType "text/plain" -Username $Username -Root $Root | Out-Null
        $download = Invoke-WebDavValidationRequest -Method "GET" -Uri $testUri -Headers $authHeaders -Username $Username -Root $Root
        if ($download.Content -ne $secondBodyText) {
            throw "WebDAV download validation returned unexpected content."
        }
    }

    $outputDir = Split-Path -Parent $OutputEnvPath
    if ($outputDir) {
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    }

    $envContent = @(
        "NAS_DRIVE_BASE_URL=$BaseUrl"
        "NAS_DRIVE_WEBDAV_URL=$WebDavUrl"
        "NAS_DRIVE_ROOT=$Root"
        "NAS_DRIVE_PUBLIC_SHARE_HASH=$PublicShareHash"
        "NAS_DRIVE_PUBLIC_FILE_PREFIX="
        "NAS_DRIVE_USERNAME=$Username"
        "NAS_DRIVE_PASSWORD_OR_TOKEN=$token"
        "NAS_DRIVE_MAX_UPLOAD_BYTES=$MaxUploadBytes"
    ) -join [Environment]::NewLine

    Set-Content -LiteralPath $OutputEnvPath -Value ($envContent + [Environment]::NewLine) -Encoding UTF8

    Write-Host "Created minimal FileBrowser API token: $tokenDisplayName"
    Write-Host "Verified user permissions: api/create/modify/download"
    if (-not $SkipWebDavValidation) {
        Write-Host "Verified WebDAV: create, modify, download"
    }
    Write-Host "Wrote env file: $OutputEnvPath"
}
finally {
    if ($plainPassword) {
        $plainPassword = $null
    }
}
