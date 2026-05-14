#requires -Version 5.1
<#
.SYNOPSIS
  PowerShell port of tools/smoke_e2e.sh — drive the CLI end-to-end
  against a local Supabase from a Windows shell.

.DESCRIPTION
  Walks every shipping command at least once, asserts the round-trip
  is consistent, then cleans up after itself.

.PARAMETER Keep
  Skip the rm step. Useful when debugging a failure mid-run.

.NOTES
  Required environment:
    TAGLIBRO_TEST_EMAIL       email of a pre-existing local supabase
                              test user (seed_dev.sql usually adds
                              alice@example.com).
    TAGLIBRO_TEST_PASSWORD    password for that user.

  Exit codes:
    0   all steps passed
    1   a step failed (which step is written to stderr)
    77  local supabase not running / prereq missing → skipped
#>
param(
  [switch]$Keep
)

$ErrorActionPreference = 'Stop'

# ── helpers ────────────────────────────────────────────────────────

function Skip([string]$msg) {
  Write-Error -Message "[skip] $msg" -ErrorAction Continue
  exit 77
}

function Fail([string]$msg) {
  Write-Error -Message "[fail] $msg" -ErrorAction Continue
  exit 1
}

function Step([string]$msg) {
  Write-Host "[step] $msg" -ForegroundColor Cyan
}

# ── pre-flight ────────────────────────────────────────────────────

if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
  Skip 'dart not on PATH (install Dart SDK or run from a "dart" shell)'
}

# Probe local Supabase. Three-second cap so we exit quickly when the
# stack isn't running.
try {
  $null = Invoke-WebRequest -Uri 'http://localhost:19000/rest/v1/' `
    -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
} catch {
  Skip 'local Supabase not reachable at http://localhost:19000 — run `supabase start`'
}

if (-not $env:TAGLIBRO_TEST_EMAIL -or -not $env:TAGLIBRO_TEST_PASSWORD) {
  Skip 'TAGLIBRO_TEST_EMAIL / TAGLIBRO_TEST_PASSWORD not set'
}

# Isolate credentials + editor side-effects to a temp dir under
# %TEMP%.  %APPDATA% override is enforced by setting APPDATA before
# invoking the CLI — credentials_store.dart reads it.
$workdir = Join-Path $env:TEMP "taglibro-e2e-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $workdir | Out-Null
$origAppData = $env:APPDATA
$env:APPDATA = Join-Path $workdir 'AppData'
New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null

try {
  # Dummy editor: copies a seed file over whatever path is passed
  # as the first argument. The PowerShell .ps1 form would need
  # explicit invocation, so we ship a .cmd shim instead — Process.start
  # under cmd.exe /c calls .cmd files straight off PATH.
  $seedHolder = Join-Path $workdir 'seed.md'
  $editorCmd = Join-Path $workdir 'dummy_editor.cmd'
  @"
@echo off
copy /Y "%TAGLIBRO_E2E_SEED%" "%~1" >nul
"@ | Set-Content -Path $editorCmd -Encoding ASCII
  $env:EDITOR = $editorCmd
  $env:VISUAL = $editorCmd
  $env:PATH = "$workdir;$env:PATH"

  $cliDir = Resolve-Path (Join-Path $PSScriptRoot '..')

  function Cli {
    param([Parameter(ValueFromRemainingArguments=$true)]$args)
    Push-Location $cliDir
    try {
      & dart run bin/taglibro.dart --env=dev @args
      if ($LASTEXITCODE -ne 0) { throw "cli exit $LASTEXITCODE" }
    } finally {
      Pop-Location
    }
  }

  $testDate = '2099-01-01'
  $testKeyword = 'TaglibroSmokeKeyword'

  # 1/12 login
  Step '1/12 login'
  $loginInput = "$($env:TAGLIBRO_TEST_EMAIL)`n$($env:TAGLIBRO_TEST_PASSWORD)`n"
  Push-Location $cliDir
  try {
    $loginInput | & dart run bin/taglibro.dart --env=dev login | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'login' }
  } finally {
    Pop-Location
  }

  # 2/12 whoami
  Step '2/12 whoami'
  $who = Cli whoami
  if ($who -notmatch [regex]::Escape($env:TAGLIBRO_TEST_EMAIL)) {
    Fail "whoami did not echo the test email (got: $who)"
  }

  # 3/12 list — test date should not yet exist
  Step '3/12 list (test date should not exist)'
  $listOut = Cli list --from $testDate --to $testDate --limit 1
  if ($listOut -match [regex]::Escape($testDate)) {
    Fail "list already shows $testDate — stale fixture?"
  }

  # 4/12 new
  Step '4/12 new (dummy editor seeds the body)'
  "# Smoke title`r`n`r`n$testKeyword in the body.`r`n" | Set-Content -Path $seedHolder -Encoding UTF8
  $env:TAGLIBRO_E2E_SEED = $seedHolder
  Cli new --date $testDate | Out-Null

  # 5/12 list now includes the test date
  Step '5/12 list now includes the test date'
  $listOut = Cli list --from $testDate --to $testDate
  if ($listOut -notmatch [regex]::Escape($testDate)) {
    Fail "list missing $testDate after new"
  }

  # 6/12 show
  Step '6/12 show round-trips the body'
  $showOut = Cli show $testDate
  if ($showOut -notmatch [regex]::Escape($testKeyword)) {
    Fail "show didn't return the seeded body"
  }

  # 7/12 search
  Step '7/12 search finds the keyword'
  $searchOut = Cli search $testKeyword
  if ($searchOut -notmatch [regex]::Escape($testDate)) {
    Fail "search didn't locate the test diary"
  }

  # 8/12 export --stdout
  Step '8/12 export --stdout includes the body'
  $exportOut = Cli export --from $testDate --to $testDate --stdout
  if ($exportOut -notmatch [regex]::Escape($testKeyword)) {
    Fail 'export stdout missing body'
  }

  # 9/12 edit
  Step '9/12 edit replaces the body'
  "# Updated`r`n`r`n$testKeyword revised.`r`n" | Set-Content -Path $seedHolder -Encoding UTF8
  Cli edit $testDate | Out-Null
  $showOut = Cli show $testDate
  if ($showOut -notmatch 'revised') {
    Fail "edit didn't take effect"
  }

  # 10/12 rm
  if ($Keep) {
    Write-Host "[info] kept $testDate in place per -Keep" -ForegroundColor Yellow
  } else {
    Step '10/12 rm'
    Cli rm $testDate --yes | Out-Null
    $listOut = Cli list --from $testDate --to $testDate
    if ($listOut -match [regex]::Escape($testDate)) {
      Fail "rm reported success but list still shows $testDate"
    }
  }

  # 11/12 re-login + list — tombstone stays gone
  if (-not $Keep) {
    Step '11/12 re-login + list — tombstoned diary stays gone'
    Cli logout | Out-Null
    Push-Location $cliDir
    try {
      $loginInput | & dart run bin/taglibro.dart --env=dev login | Out-Null
      if ($LASTEXITCODE -ne 0) { Fail 'login (re-login)' }
    } finally {
      Pop-Location
    }
    $listOut = Cli list --from $testDate --to $testDate
    if ($listOut -match [regex]::Escape($testDate)) {
      Fail "$testDate reappeared after re-login (tombstone not honoured?)"
    }
  }

  # 12/12 logout clears credentials
  Step '12/12 logout clears credentials'
  Cli logout | Out-Null
  $credPath = Join-Path $env:APPDATA 'taglibro\credentials.json'
  if (Test-Path $credPath) {
    Fail 'logout did not remove credentials file'
  }

  Write-Host '[ok] all 12 steps passed' -ForegroundColor Green
} finally {
  if ($origAppData) { $env:APPDATA = $origAppData } else { Remove-Item env:APPDATA }
  Remove-Item -Recurse -Force $workdir -ErrorAction SilentlyContinue
}
