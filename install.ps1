<#
.SYNOPSIS
  Taglibro CLI installer for Windows.

.DESCRIPTION
  One-liner:
    irm https://raw.githubusercontent.com/chai0204/taglibro-cli/main/install.ps1 | iex

  Detects the host architecture, fetches the latest GitHub Release
  asset, downloads tgl.exe under %LOCALAPPDATA%\Programs\tgl\,
  appends that directory to the User PATH, and prints next-step
  instructions.

.PARAMETER DryRun
  Walk the steps without downloading or writing anything.

.PARAMETER NoPath
  Skip the User PATH append (use this when running with --update on an
  existing install you already wired up).

.NOTES
  Exit codes:
    0  ok
    1  unsupported architecture
    2  download or write failure
    3  binary smoke (`--version`) failed
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$NoPath
)

$ErrorActionPreference = 'Stop'

$Repo = 'chai0204/taglibro-cli'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\tgl'
$BinName = 'tgl.exe'
$Target = Join-Path $InstallDir $BinName

# ── architecture check ─────────────────────────────────────────────
# PROCESSOR_ARCHITECTURE is AMD64 on x64 Windows. ARM64 is theoretical
# until we ship a windows-arm64 binary; explicitly refuse for now so
# the user gets a clear error instead of a "binary won't run" puzzle.
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -ne 'AMD64') {
  Write-Error "Unsupported Windows architecture: $arch (need AMD64). " +
    "Only x64 Windows binaries are built today."
  exit 1
}
$Asset = 'taglibro-windows-x64.exe'
Write-Host "→ Detected Windows/$arch → asset: $Asset" -ForegroundColor Cyan

# ── fetch latest release ──────────────────────────────────────────
$Api = "https://api.github.com/repos/$Repo/releases/latest"
Write-Host "→ Querying $Api"
try {
  $release = Invoke-RestMethod -Uri $Api -UseBasicParsing -Headers @{
    'User-Agent' = 'taglibro-installer'
  }
} catch {
  Write-Error "Failed to query GitHub Releases API: $_"
  exit 2
}

$tag = $release.tag_name
$assetUrl = ($release.assets | Where-Object { $_.name -eq $Asset } |
  Select-Object -First 1).browser_download_url

if (-not $tag -or -not $assetUrl) {
  Write-Error "Could not find asset '$Asset' in the latest release. " +
    "Tag parsed: '$tag'. Open $Api to inspect what was published."
  exit 2
}

Write-Host "→ Latest release: $tag"
Write-Host "→ Asset URL:      $assetUrl"

if ($DryRun) {
  Write-Host "[dry-run] would download to $Target"
  Write-Host "[dry-run] would append $InstallDir to User PATH"
  exit 0
}

# ── download ──────────────────────────────────────────────────────
if (-not (Test-Path $InstallDir)) {
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
$tmp = [System.IO.Path]::GetTempFileName()
try {
  Write-Host "→ Downloading binary (~10 MB) to $Target…"
  Invoke-WebRequest -Uri $assetUrl -OutFile $tmp -UseBasicParsing -Headers @{
    'User-Agent' = 'taglibro-installer'
  }
  Move-Item -Path $tmp -Destination $Target -Force
} catch {
  Write-Error "Download failed: $_"
  if (Test-Path $tmp) { Remove-Item $tmp -Force }
  exit 2
}

# ── User PATH append ──────────────────────────────────────────────
if (-not $NoPath) {
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($null -eq $userPath) { $userPath = '' }
  $segments = $userPath -split ';' | Where-Object { $_ -ne '' }
  if ($segments -notcontains $InstallDir) {
    $newPath = (@($segments) + $InstallDir) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    # Also update the current session's PATH so the smoke step below
    # sees the new binary without requiring a new shell.
    $env:Path = "$env:Path;$InstallDir"
    Write-Host "✓ Added $InstallDir to User PATH (open a new shell to pick it up everywhere)"
  } else {
    Write-Host "→ $InstallDir already on User PATH"
  }
}

# ── verify ────────────────────────────────────────────────────────
try {
  $versionOut = & $Target --version 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "exit code $LASTEXITCODE; output: $versionOut"
  }
} catch {
  Write-Error "'$Target --version' failed: $_"
  exit 3
}

Write-Host ''
Write-Host "✓ Installed $versionOut" -ForegroundColor Green
Write-Host "  Binary: $Target"
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. tgl login   # one-time auth, saves to %APPDATA%\taglibro'
Write-Host '  2. tgl new     # create today''s diary in $env:EDITOR'
Write-Host '  3. tgl --help  # full command list'
