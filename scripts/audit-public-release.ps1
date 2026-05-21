param(
    [string] $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$skipPatterns = @(
    '(^|/)\.git(/|$)',
    '^\.env$',
    '^\.env\.(?!example$).*$',
    '(^|/)node_modules(/|$)',
    '(^|/)coverage(/|$)',
    '(^|/)dist(/|$)',
    '(^|/)\.cache(/|$)',
    '(^|/)data(/|$)',
    '(^|/)logs(/|$)',
    '(^|/)tmp(/|$)',
    '(^|/)downloads(/|$)',
    '(^|/)secrets(/|$)',
    '(^|/)nas-pilot-data(/|$)',
    '(^|/)nas-cloud-backups(/|$)',
    '(^|/)nas-restore-tests(/|$)',
    '(^|/)tools/cloudflared(/|$)',
    '^scripts/audit-public-release\.ps1$',
    '^docs/current-.*\.md$',
    '^docs/disk-inventory\.md$',
    '^docs/linux-vm-pilot-runbook\.md$',
    '^docs/morning-handoff\.md$',
    '^docs/diy-nas-pipeline\.md$',
    '^docs/pilot-results\.md$',
    '^docs/production-storage-plan\.md$',
    '^docs/zfs-mirror-migration-runbook\.md$',
    '^docs/superpowers(/|$)',
    '^docs/access-security\.md$',
    '^docs/backup-restore\.md$',
    '^docs/external-system-integration-plan\.md$',
    '^docs/filebrowser-quantum-korean\.md$',
    '^docs/nextcloud-backup-restore\.md$',
    '^docs/nextcloud-install-notes\.md$',
    '^docs/nextcloud-integration-gateway\.md$',
    '^docs/ssd-pilot-and-hosting\.md$',
    '^docs/windows-native-pilot-cloud\.md$',
    '^docs/examples/cafe24-upload-example\.js$',
    '^samples/production-storage-plan-current\.json$',
    '^scripts/vm/attach-current-8tb-hdds\.ps1$',
    '^scripts/vm/safe-detach-all-8tb-hdds\.ps1$',
    '^scripts/vm/restore-live-disks-after-dock-change\.ps1$',
    '^scripts/backup/create-windows-backup-mirror\.ps1$',
    '^scripts/backup/clear-backup-disk-metadata\.ps1$',
    '^scripts/backup/copy-latest-nextcloud-backup.*\.ps1$',
    '^scripts/backup/invoke-nextcloud-backup-pipeline\.ps1$',
    '^scripts/backup/test-nextcloud-backup-restore.*\.ps1$',
    '^scripts/linux/setup-zfs-mirrors\.sh$'
)

$rules = @(
    [pscustomobject]@{ Name = "personal domain or account marker"; Pattern = '(?i)\biyoxyz\b|233qla|iyohouse|mshome|nasadmin|iyo[_-]?drive|IYO' },
    [pscustomobject]@{ Name = "local Windows user path"; Pattern = '(?i)C:\\Users\\Q\b' },
    [pscustomobject]@{ Name = "real disk serial marker"; Pattern = '0000000049(26|27|28|29)' },
    [pscustomobject]@{ Name = "Cloudflare tunnel install token or JWT-looking token"; Pattern = 'cloudflared\.exe service install|eyJ' },
    [pscustomobject]@{ Name = "real Tailscale IP"; Pattern = '\b100\.(?!64\.0\.0\b)(?!64\.0\.0/10\b)(?!64\.)\d{1,3}\.\d{1,3}\.\d{1,3}\b' },
    [pscustomobject]@{ Name = "real 172.16/12 private IP"; Pattern = '\b172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3}\b' }
)

function Test-SkipPath {
    param([string] $RelativePath)

    foreach ($pattern in $skipPatterns) {
        if ($RelativePath -match $pattern) {
            return $true
        }
    }

    return $false
}

$findings = New-Object System.Collections.Generic.List[object]
$files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force
$rootWithSeparator = $Root.TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar

foreach ($file in $files) {
    if ($file.FullName.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $file.FullName.Substring($rootWithSeparator.Length).Replace("\", "/")
    } else {
        $relative = $file.FullName.Replace("\", "/")
    }

    if (Test-SkipPath -RelativePath $relative) {
        continue
    }

    if ($file.Length -gt 5MB) {
        continue
    }

    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue) {
        $lineNumber++
        foreach ($rule in $rules) {
            if ($line -match $rule.Pattern) {
                $findings.Add([pscustomobject]@{
                    File = $relative
                    Line = $lineNumber
                    Rule = $rule.Name
                    Text = $line.Trim()
                })
            }
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "Public release audit failed. Remove or ignore private deployment values before publishing." -ForegroundColor Red
    exit 1
}

Write-Host "Public release audit passed."
