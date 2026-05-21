[CmdletBinding()]
param(
    [string] $BaseUrl = "https://drive.example.com",
    [string] $WebDavUrl = "https://drive.example.com/dav/DIY%20NAS%20Drive/",
    [string] $SourceName = "DIY NAS Drive",
    [string] $WikiScope = "/WIKI",
    [string] $UploadUsername = "wiki_upload",
    [string] $AdminUsername = "admin",
    [string] $OutputEnvPath = ".\secrets\drive.env",
    [string] $PublicShareHash = "REPLACE_WITH_FILEBROWSER_SHARE_HASH",
    [int] $MaxUploadBytes = 10485760
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

function Invoke-FbRequest {
    param(
        [string] $Method,
        [string] $Uri,
        [hashtable] $Headers,
        [object] $Body,
        [Microsoft.PowerShell.Commands.WebRequestSession] $WebSession,
        [string] $ContentType = "application/json"
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
$WikiScope = "/" + $WikiScope.Trim("/")

Write-Host "Configuring FileBrowser wiki upload account without printing secrets."
Write-Host "Upload user: $UploadUsername"
Write-Host "Scope: $WikiScope"
Write-Host "WebDAV: $WebDavUrl"

$adminPasswordSecure = Read-Host "FileBrowser admin password for $AdminUsername" -AsSecureString
$adminPassword = ConvertFrom-SecureStringToPlainText $adminPasswordSecure

try {
    $adminSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $adminLoginUri = "$BaseUrl/api/auth/login?username=$([Uri]::EscapeDataString($AdminUsername))"
    Invoke-FbRequest -Method "POST" -Uri $adminLoginUri -Headers @{
        "X-Password" = [Uri]::EscapeDataString($adminPassword)
        "X-Secret" = ""
    } -WebSession $adminSession | Out-Null

    $usersResponse = Invoke-FbRequest -Method "GET" -Uri "$BaseUrl/api/users" -WebSession $adminSession
    $users = @($usersResponse.Content | ConvertFrom-Json)
    if ($users.Count -eq 1 -and $users[0] -is [array]) {
        $users = @($users[0])
    }
    $uploadUser = $users | Where-Object { $_.username -eq $UploadUsername } | Select-Object -First 1
    if (-not $uploadUser) {
        throw "FileBrowser user '$UploadUsername' was not found. Create it first, then rerun this script."
    }

    $permissions = [ordered]@{
        api = $true
        admin = $false
        modify = $true
        share = $false
        realtime = $false
        delete = $true
        create = $true
        download = $true
    }
    $scopes = @(
        [ordered]@{
            name = $SourceName
            scope = $WikiScope
        }
    )
    $bodyObject = [ordered]@{
        which = @("permissions", "scopes")
        data = [ordered]@{
            permissions = $permissions
            scopes = $scopes
        }
    }
    $body = $bodyObject | ConvertTo-Json -Depth 10
    $uploadUserId = [string] $uploadUser.id
    if ($uploadUserId -match '\s') {
        throw "Resolved multiple user IDs for '$UploadUsername': $uploadUserId"
    }
    $updateUri = "$BaseUrl/api/users?id=$uploadUserId"
    Invoke-FbRequest -Method "PUT" -Uri $updateUri -WebSession $adminSession -Headers @{
        "X-Password" = [Uri]::EscapeDataString($adminPassword)
    } -Body $body | Out-Null
    Write-Host "Updated '$UploadUsername': scope=$WikiScope, download/create/modify/delete/api enabled."
}
finally {
    $adminPassword = $null
}

Write-Host "Creating a fresh upload token as '$UploadUsername'."
& "$PSScriptRoot\create-filebrowser-webdav-token.ps1" `
    -BaseUrl $BaseUrl `
    -WebDavUrl $WebDavUrl `
    -Root "" `
    -Username $UploadUsername `
    -TokenName "diy-nas-wiki-upload" `
    -PublicShareHash $PublicShareHash `
    -MaxUploadBytes $MaxUploadBytes `
    -OutputEnvPath $OutputEnvPath `
    -UseCustomPermissionsToken

Write-Host "Testing WebDAV token."
& "$PSScriptRoot\test-filebrowser-webdav-token.ps1" `
    -EnvPath $OutputEnvPath `
    -TestPath "hi.txt" `
    -ShowPermissions `
    -Overwrite
