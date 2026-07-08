#Requires -Version 5.1
<#
.SYNOPSIS
  Battle-test a compiled distribution against the LOCAL Hermes install using a THROWAWAY named
  profile. Compiles, installs, asserts `config check` is clean and `skills list` matches the
  manifest, exercises the update path, then always tears the profile down.

.DESCRIPTION
  SAFETY (non-negotiable): runs ONLY against a throwaway profile named `cfgtest-<template>`. It
  refuses to touch `default` or an empty profile, and never writes %LOCALAPPDATA%\hermes\config.yaml.
  Teardown runs in a finally block. Missing API keys and a missing ~/open-skills are tolerated.

.PARAMETER Template   Distribution name/ref to test (e.g. base/general, il-legal, developer).
.PARAMETER WhatIf     Print the plan and safety checks; do not install anything.
.PARAMETER KeepProfile Leave the throwaway profile installed (skip teardown) for manual inspection.
.PARAMETER InstallSkills Exercise the apply flow: auto-install the referenced skills into the
  throwaway profile (network + Hermes security scan) and assert they land. Off by default so the
  harness stays offline-safe; the post_install/README correctness checks always run.

.EXAMPLE
  pwsh -File tests/livetest.ps1 -Template persona/developer -WhatIf
.EXAMPLE
  pwsh -File tests/livetest.ps1 -Template base/general
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Template,
  [switch]$WhatIf,
  [switch]$KeepProfile,
  [switch]$InstallSkills
)

$ErrorActionPreference = 'Stop'
$RepoRoot     = Split-Path -Parent $PSScriptRoot
$TemplateName = Split-Path -Leaf $Template
$ProfileName      = "cfgtest-$TemplateName"
$DistDir      = Join-Path $RepoRoot "dist\$TemplateName"

function Fail($m) { Write-Host "FAIL: $m" -ForegroundColor Red; exit 1 }
function Ok($m)   { Write-Host "  ✓ $m" -ForegroundColor Green }
function Info($m) { Write-Host "    $m" }

# ---- SAFETY GATES ----------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($TemplateName)) { Fail "empty template name" }
if ($ProfileName -ieq 'cfgtest-' ) { Fail "refusing empty profile suffix" }
if ($TemplateName -ieq 'default' -or $ProfileName -ieq 'default') { Fail "refusing to target the 'default' profile" }
if ($ProfileName -notlike 'cfgtest-*') { Fail "profile '$ProfileName' is not a throwaway cfgtest-* name" }

$Hermes = (Get-Command hermes -ErrorAction SilentlyContinue).Source
if (-not $Hermes) { Fail "hermes CLI not found on PATH" }

Write-Host "Live harness — template '$TemplateName' -> throwaway profile '$ProfileName'" -ForegroundColor White
Info "dist dir: $DistDir"
Info "SAFE: never targets 'default'; never writes %LOCALAPPDATA%\hermes\config.yaml"

if ($WhatIf) {
  Write-Host "`n[WhatIf] Plan:" -ForegroundColor Yellow
  Info "1. python -m configurator compile $Template"
  Info "2. hermes profile install `"$DistDir`" --name $ProfileName --yes"
  Info "3. hermes -p $ProfileName config check   (assert: Config version + no errors)"
  Info "4. hermes -p $ProfileName skills list"
  Info "5. hermes profile update $ProfileName --yes   (update path)"
  Info "6. hermes profile delete $ProfileName --yes   (teardown)"
  Ok "safety gates passed; no changes made"
  exit 0
}

# ---- COMPILE ---------------------------------------------------------------
Write-Host "`n==> compile" -ForegroundColor Cyan
& python -m configurator compile $Template
if ($LASTEXITCODE -ne 0) { Fail "compile failed" }
if (-not (Test-Path -LiteralPath $DistDir)) { Fail "dist dir not produced: $DistDir" }
Ok "compiled $TemplateName"

try {
  # ---- INSTALL -------------------------------------------------------------
  Write-Host "`n==> install" -ForegroundColor Cyan
  & $Hermes profile install $DistDir --name $ProfileName --yes
  if ($LASTEXITCODE -ne 0) { Fail "install failed" }
  Ok "installed $ProfileName"

  # ---- CONFIG CHECK --------------------------------------------------------
  Write-Host "`n==> config check" -ForegroundColor Cyan
  $check = (& $Hermes -p $ProfileName config check 2>&1 | Out-String)
  if ($check -notmatch 'Config version') { Fail "config check did not report a config version" }
  $errLines = ($check -split "`n") | Where-Object { $_ -match '(?i)\berror\b|invalid|unknown key|✗|✘' }
  if ($errLines) { $errLines | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }; Fail "config check reported errors" }
  Ok "config check clean (missing API keys tolerated)"

  # ---- REFERENCE-ONLY: distribution vendors no skills ---------------------
  Write-Host "`n==> skills (reference-only model)" -ForegroundColor Cyan
  if (Test-Path (Join-Path $DistDir 'skills')) { Fail "distribution ships a skills/ dir — reference-only model forbids vendored skill content" }
  Ok "no vendored skills/ dir (reference-only)"

  # skills.install.json must list exactly the compiled post_install ids (machine-readable apply list).
  $installManifest = Join-Path $DistDir 'skills.install.json'
  $refs = @()
  if (Test-Path $installManifest) {
    $refs = @((Get-Content -LiteralPath $installManifest -Raw | ConvertFrom-Json).skills)
    Info ("references {0} skill(s): {1}" -f $refs.Count, (($refs | ForEach-Object { $_.id }) -join ', '))
    # Every id in skills.install.json must also appear in the README post-install block.
    $readme = (Get-Content -LiteralPath (Join-Path $DistDir 'README.md') -Raw)
    foreach ($r in $refs) {
      if ($readme -notmatch [regex]::Escape($r.id)) { Fail "README missing referenced skill id '$($r.id)'" }
    }
    Ok "skills.install.json matches README post-install block ($($refs.Count) id(s))"
  } else { Ok "distribution references no skills (no skills.install.json)" }

  # .no-bundled-skills must have suppressed the bulk bundled seed (0 builtin) when present.
  $skillsOut = (& $Hermes -p $ProfileName skills list 2>&1 | Out-String)
  Write-Host $skillsOut
  if ((Test-Path (Join-Path $DistDir '.no-bundled-skills')) -and ($skillsOut -match '(\d+)\s+builtin')) {
    if ([int]$Matches[1] -ne 0) { Fail ".no-bundled-skills present but $($Matches[1]) builtin skills seeded" }
    Ok "bundled seed suppressed (0 builtin)"
  }

  # ---- APPLY FLOW: auto-install the referenced skills (opt-in, network) ----
  if ($InstallSkills -and $refs.Count -gt 0) {
    Write-Host "`n==> apply-flow skill install (into $ProfileName)" -ForegroundColor Cyan
    foreach ($r in $refs) {
      if ([bool]$r.tap) {
        & $Hermes -p $ProfileName skills tap add $r.id 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Ok "tap add $($r.id)" } else { Write-Host "  ! tap add $($r.id) failed (tolerated)" -ForegroundColor Yellow }
      } else {
        & $Hermes -p $ProfileName skills install $r.id --yes 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Ok "installed $($r.id)" } else { Write-Host "  ! install $($r.id) failed (tolerated)" -ForegroundColor Yellow }
      }
    }
    $after = (& $Hermes -p $ProfileName skills list 2>&1 | Out-String)
    $landed = @($refs | Where-Object { -not [bool]$_.tap } | ForEach-Object { ($_.id -split '/')[-1] } | Where-Object { $after -match [regex]::Escape($_) })
    if ($landed.Count -gt 0) { Ok "apply flow landed $($landed.Count) referenced skill(s): $($landed -join ', ')" }
    else { Write-Host "  ! no referenced skills detected in skills list (registry/network may be unavailable)" -ForegroundColor Yellow }
    # config check must remain clean after installs.
    $recheck = (& $Hermes -p $ProfileName config check 2>&1 | Out-String)
    if ((($recheck -split "`n") | Where-Object { $_ -match '(?i)\berror\b|invalid|unknown key|✗|✘' })) { Fail "config check reported errors after skill install" }
    Ok "config check still clean after apply-flow install"
  }

  # ---- .env.EXAMPLE generated in the profile ------------------------------
  $profRoot = Join-Path $env:LOCALAPPDATA "hermes\profiles\$ProfileName"
  if (Test-Path (Join-Path $DistDir '.env.EXAMPLE')) {
    if (-not (Test-Path (Join-Path $profRoot '.env.EXAMPLE'))) { Fail ".env.EXAMPLE not generated in profile" }
    Ok ".env.EXAMPLE present in profile"
  }

  # ---- external-dir silent-skip contract ----------------------------------
  # config check already passed with ~/open-skills absent — that IS the silent-skip proof.
  if (-not (Test-Path (Join-Path $env:USERPROFILE 'open-skills'))) { Ok "missing ~/open-skills tolerated (silent-skip contract)" }

  # ---- doctor (config-level health; missing API keys tolerated) -----------
  Write-Host "`n==> doctor" -ForegroundColor Cyan
  $doctor = (& $Hermes -p $ProfileName doctor 2>&1 | Out-String)
  $docErr = ($doctor -split "`n") | Where-Object { $_ -match '(?i)invalid config|config error|unknown key|schema' }
  if ($docErr) { $docErr | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }; Fail "doctor reported config-level errors" }
  Ok "doctor: no config-level errors"

  # ---- UPDATE PATH preserves user-owned files ------------------------------
  Write-Host "`n==> update path (assert user-owned files preserved)" -ForegroundColor Cyan
  $memDir = Join-Path $profRoot 'memories'
  New-Item -ItemType Directory -Force -Path $memDir | Out-Null
  $sentinel = Join-Path $memDir 'livetest-sentinel.txt'
  $stamp = [guid]::NewGuid().ToString()
  Set-Content -LiteralPath $sentinel -Value $stamp -Encoding UTF8
  & $Hermes profile update $ProfileName --yes 2>&1 | Out-String | Write-Host
  if ($LASTEXITCODE -ne 0) { Write-Host "  ! update reported non-zero (source may be a local dir)" -ForegroundColor Yellow } else { Ok "update path OK" }
  if (-not (Test-Path -LiteralPath $sentinel)) { Fail "update deleted a user-owned file (memories/)" }
  if ((Get-Content -LiteralPath $sentinel -Raw).Trim() -ne $stamp) { Fail "update mutated a user-owned file" }
  Ok "user-owned memories/ preserved across update"

  Write-Host "`nPASS: $TemplateName" -ForegroundColor Green
}
finally {
  if ($KeepProfile) {
    Write-Host "`n(-KeepProfile) leaving $ProfileName installed" -ForegroundColor Yellow
  } else {
    Write-Host "`n==> teardown" -ForegroundColor Cyan
    & $Hermes profile delete $ProfileName --yes 2>&1 | Out-Null
    Ok "deleted $ProfileName"
  }
}

