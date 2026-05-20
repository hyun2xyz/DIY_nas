param(
  [Parameter(Mandatory = $true)]
  [string]$DestinationRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationRoot)

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw 'git command was not found.'
}

Push-Location $repoRoot
try {
  $files = git ls-files --cached --others --exclude-standard
}
finally {
  Pop-Location
}

if (-not $files) {
  throw 'No public files found from git ls-files.'
}

New-Item -ItemType Directory -Force -Path $destination | Out-Null

$copied = 0
foreach ($file in $files) {
  $relative = $file -replace '/', [System.IO.Path]::DirectorySeparatorChar
  $source = Join-Path $repoRoot $relative
  $target = Join-Path $destination $relative

  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    continue
  }

  $targetDir = Split-Path -Parent $target
  New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
  Copy-Item -LiteralPath $source -Destination $target -Force
  $copied++
}

Write-Host "Copied $copied public files to $destination"
Write-Host 'Run verification in the destination before publishing:'
Write-Host '  npm.cmd run check'
Write-Host '  npm.cmd test'
Write-Host '  npm.cmd run audit:public'
