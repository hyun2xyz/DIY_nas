[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Wiki', 'LMS', 'Publishing', 'Cafe24')]
    [string]$Root,

    [string]$TokensPath = (Join-Path $env:USERPROFILE 'nas-cloud-secrets\gateway-tokens.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $TokensPath)) {
    throw "Gateway token file not found: $TokensPath"
}

$tokens = Get-Content -LiteralPath $TokensPath -Raw | ConvertFrom-Json
foreach ($property in $tokens.PSObject.Properties) {
    if ($property.Value.root -eq $Root) {
        Set-Clipboard -Value $property.Name
        Write-Host "Copied $Root gateway token to clipboard."
        Write-Host 'Paste it into GATEWAY_API_TOKEN on the external server. Do not commit it.'
        exit 0
    }
}

throw "No gateway token configured for root '$Root'."
