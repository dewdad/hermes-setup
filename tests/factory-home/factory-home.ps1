#Requires -Version 5.1
<#
.SYNOPSIS
  SAVED-STATE, fully agent-driveable E2E for hermes-setup distributions via a snapshot/restore
  HERMES_HOME. No VM, no Desktop GUI — the Hermes Desktop app shares this exact HERMES_HOME
  (config.yaml, profiles/, auth.json, desktop.json, skills/, sessions/), so driving it through the
  `hermes` CLI exercises the same state the GUI renders.

.DESCRIPTION
  Relocates HERMES_HOME (PROCESS-SCOPED) to a persistent host STORE with two homes:
    <Store>\factory\  — a snapshot of a post-install HERMES_HOME ("freshly installed / factory reset"
                        Hermes Desktop with the compiled profile applied + Tier-0 skills). Built ONCE.
    <Store>\work\     — the live HERMES_HOME the harness points `hermes` at for a run.

  Actions:
    Build   Pay the install cost ONCE: fresh profile install + Tier-0 skill into work\, assert the
            Tier-0 contract, then (only if all checks passed) snapshot work\ -> factory\.
    Reset   Requirement 1 — restore factory\ -> work\ (a fast folder mirror, seconds, NOT a reinstall)
            and re-assert the pristine post-install contract. This is the "start from a freshly
            installed / factory-reset Desktop, optimized with saved state" per-run entry point.
    Dirty   Requirement 2 — leave work\ AS-IS (accumulated sessions/skills/config drift) and run
            `hermes profile update` (and, with -NewPersona, install/update ANOTHER persona) against
            that dirty home; assert the update lands and the G1 user-skill-survival guard holds.
    Status  Show the store, which homes exist, and the profiles installed in work\.
    Clean   Remove the whole store (factory + work) to return to a true clean slate.

  SAFETY (multiple independent gates):
    * A store PREFLIGHT (Assert-SafeStore) runs BEFORE any delete/mirror and aborts unless the store
      resolves to a path that does NOT equal / contain / sit inside your real Hermes home, the repo,
      dist\, %USERPROFILE%, %LOCALAPPDATA% (the store may live UNDER it — the default does), or a drive
      root; reparse points/junctions on the store are rejected too.
    * HERMES_HOME is set PROCESS-SCOPED (this script + its child `hermes` only) and restored in a
      finally block.
    * Before any `hermes` call, the script HARD-ASSERTS `hermes config path` resolves inside the store
      work home (separator-based containment, not a loose prefix) — aborting otherwise.
  Your real Hermes home (%LOCALAPPDATA%\hermes) is NEVER read or written. Store default:
  %LOCALAPPDATA%\hermes-e2e\<template> (override with -Store); delete it (or -Action Clean) to reset.

.PARAMETER Action      Build | Reset | Dirty | Status | Clean  (default: Reset).
.PARAMETER Template    Distribution the factory baseline is built from (default: general). Must be under dist\.
.PARAMETER NewPersona  Dirty action only: also install/update this OTHER compiled persona (dist\<NewPersona>)
                       into the dirty home, asserting it lands alongside the existing profile without clobbering it.
.PARAMETER Store       Persistent host store folder (default: %LOCALAPPDATA%\hermes-e2e\<template>).
.PARAMETER SkipSkills  Build only: skip the network Tier-0 skill install (faster, offline baseline).

.EXAMPLE
  pwsh -File tests/factory-home/factory-home.ps1 -Action Build          # once: create the saved baseline
.EXAMPLE
  pwsh -File tests/factory-home/factory-home.ps1 -Action Reset          # per run: fast restore + assert
.EXAMPLE
  pwsh -File tests/factory-home/factory-home.ps1 -Action Dirty          # update the persona on the dirty home
.EXAMPLE
  pwsh -File tests/factory-home/factory-home.ps1 -Action Dirty -NewPersona il-citizen   # install a new persona on a dirty home
.EXAMPLE
  pwsh -File tests/factory-home/factory-home.ps1 -Action Status
#>
[CmdletBinding()]
param(
  [ValidateSet('Build', 'Reset', 'Dirty', 'Status', 'Clean')][string]$Action = 'Reset',
  [string]$Template = 'general',
  [string]$NewPersona = '',
  [string]$Store = '',
  [switch]$SkipSkills
)
$ErrorActionPreference = 'Stop'

foreach ($n in @($Template, $NewPersona)) {
  if (-not $n) { continue }
  if ($n -notmatch '^[A-Za-z0-9._-]+$') { throw "Invalid name '$n'. Allowed: letters, digits, '.', '_', '-'." }
  if ($n -ieq 'default') { throw "Refusing to target the reserved 'default' profile name (harness contract)." }
}

function Ok($m)   { Write-Host "  [PASS] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:Failures++ }
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
$script:Failures = 0

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Dist     = Join-Path $RepoRoot "dist\$Template"
$hermes   = (Get-Command hermes -ErrorAction SilentlyContinue).Source
if (-not $hermes) { throw "hermes CLI not found on PATH." }
if (-not (Test-Path (Join-Path $Dist 'distribution.yaml'))) {
  throw "dist\$Template not found. Compile it first:  python -m configurator compile $Template"
}

if (-not $Store) { $Store = Join-Path $env:LOCALAPPDATA "hermes-e2e\$Template" }
$Factory  = Join-Path $Store 'factory'
$Work     = Join-Path $Store 'work'
$MetaFile = Join-Path $Store 'factory.meta'          # sidecar (OUTSIDE factory\ so it isn't mirrored into work)
$RealHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }

# ---- path helpers (normalize WITHOUT requiring existence) --------------------------------------
function Get-FullPath([string]$p) { return [System.IO.Path]::GetFullPath($p) }
function Test-PathContained([string]$Child, [string]$Parent) {
  # true if $Child == $Parent, or $Child sits INSIDE $Parent (separator-aware — no loose prefix match)
  $sep = [IO.Path]::DirectorySeparatorChar
  $c = (Get-FullPath $Child).TrimEnd('\', '/')
  $p = (Get-FullPath $Parent).TrimEnd('\', '/')
  if ($c -ieq $p) { return $true }
  return $c.StartsWith($p + $sep, [StringComparison]::OrdinalIgnoreCase)
}
function Test-Reparse([string]$p) {
  if (-not (Test-Path $p)) { return $false }
  return ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
}

# ---- SAFETY PREFLIGHT: run BEFORE any delete/mirror -------------------------------------------
function Assert-SafeStore {
  $storeFull = Get-FullPath $Store
  # 1. Must not overlap (either direction) with the real home, the repo, or dist\.
  foreach ($f in @($RealHome, $RepoRoot, (Join-Path $RepoRoot 'dist'))) {
    if ((Test-PathContained $storeFull $f) -or (Test-PathContained $f $storeFull)) {
      throw "SAFETY ABORT: store '$storeFull' overlaps a protected path '$(Get-FullPath $f)'."
    }
  }
  # 2. Must not EQUAL or be an ANCESTOR of these big dirs (store UNDER them is fine — the default is).
  foreach ($big in @($env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA)) {
    if ($big -and (Test-PathContained (Get-FullPath $big) $storeFull)) {
      throw "SAFETY ABORT: store '$storeFull' equals or contains a system dir '$(Get-FullPath $big)'."
    }
  }
  # 3. Must not be a drive/filesystem root.
  $root = [System.IO.Path]::GetPathRoot($storeFull)
  if ($storeFull.TrimEnd('\', '/') -ieq $root.TrimEnd('\', '/')) {
    throw "SAFETY ABORT: store '$storeFull' resolves to a drive root."
  }
  # 4. Reject reparse points/junctions/symlinks on the store or its two homes (a delete/mirror could
  #    otherwise escape the store to the link target).
  foreach ($p in @($Store, $Work, $Factory)) {
    if (Test-Reparse $p) { throw "SAFETY ABORT: '$p' is a reparse point/junction/symlink — refusing to delete/mirror through it." }
  }
}

# ---- mirror one HERMES_HOME dir onto another via robocopy (fast, exact /MIR) -----------------
function Copy-Home([string]$Src, [string]$Dst) {
  New-Item -ItemType Directory -Force -Path $Dst | Out-Null
  robocopy $Src $Dst /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
  # robocopy exit codes 0-7 are success (8+ = real error); PowerShell treats non-zero as failure, so
  # reset $LASTEXITCODE afterwards to keep later `$LASTEXITCODE -ne 0` checks meaningful.
  if ($LASTEXITCODE -ge 8) { throw "robocopy '$Src' -> '$Dst' failed (exit $LASTEXITCODE)." }
  $global:LASTEXITCODE = 0
}

# ---- fingerprint the source dist so a stale factory (built from an older dist) is detectable ---
function Get-DistFingerprint {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("template=$Template")
  foreach ($f in @('SOUL.md', 'config.yaml', 'distribution.yaml', 'skills.install.json')) {
    $fp = Join-Path $Dist $f
    if (Test-Path $fp) { [void]$sb.AppendLine("$f=" + (Get-FileHash -Algorithm SHA256 -LiteralPath $fp).Hash) }
  }
  return $sb.ToString()
}

# ---- point HERMES_HOME at $Work (process-scoped) + HARD isolation gate ------------------------
function Enter-WorkHome {
  New-Item -ItemType Directory -Force -Path $Work | Out-Null
  $env:HERMES_HOME = $Work
  if ((Test-PathContained (Get-FullPath $Work) (Get-FullPath $RealHome)) -or (Test-PathContained (Get-FullPath $RealHome) (Get-FullPath $Work))) {
    throw "SAFETY ABORT: work home '$Work' overlaps the real home '$RealHome'."
  }
  $cfgPath = (& $hermes config path 2>&1 | Out-String).Trim()
  # Separator-aware containment: the resolved config path must sit INSIDE the work home (not merely
  # share a string prefix like '...\work2\config.yaml' would).
  $cfgDir = try { Split-Path -Parent (Get-FullPath $cfgPath) } catch { '' }
  if (-not $cfgDir -or -not ((Test-PathContained $cfgPath $Work) -or (Test-PathContained $cfgDir $Work))) {
    throw "SAFETY ABORT: hermes config path ('$cfgPath') is NOT inside the store work home ('$Work')."
  }
  Ok "isolation confirmed — hermes resolves its home inside the store ($cfgPath)"
}

# ---- shared assertion suite (the CLI-driveable Desktop contract) ------------------------------
function Invoke-Assertions([string]$Profile, [string]$ProfRoot, [string]$DistRoot, [switch]$Chat) {
  Step "meta-skill (/finish-setup carve-out) + reference-only [$Profile]"
  if (Test-Path (Join-Path $ProfRoot 'meta-skills\finish-setup\SKILL.md')) { Ok "meta-skills/finish-setup/SKILL.md present" }
  else { Fail "finish-setup meta-skill missing from profile '$Profile'" }
  if (Test-Path (Join-Path $DistRoot 'skills')) { Fail "distribution '$DistRoot' ships a skills/ dir (reference-only violation)" }
  else { Ok "distribution ships no skills/ dir (reference-only)" }
  $list = (& $hermes -p $Profile skills list 2>&1 | Out-String)
  if ($list -match 'finish-setup') { Ok "/finish-setup registered as a slash command" }
  else { Fail "/finish-setup not registered (skills list has no finish-setup)" }

  Step "config check (no keys required) [$Profile]"
  $check = (& $hermes -p $Profile config check 2>&1 | Out-String)
  # 'unknown key' is intentionally NOT a failure — Hermes v0.18.x WARNS on unknown keys (project contract).
  if (($check -split "`n") | Where-Object { $_ -match '(?i)\berror\b|invalid|✗|✘' }) {
    ($check -split "`n") | Where-Object { $_ -match '(?i)\berror\b|invalid|✗|✘' } | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
    Fail "config check reported errors"
  } else { Ok "config check clean (missing provider keys + unknown-key warnings tolerated)" }

  # profile actually loaded: it must appear by name in `profile list`.
  $plist = (& $hermes profile list 2>&1 | Out-String)
  if ($plist -match ("(?m)\b" + [regex]::Escape($Profile) + "\b")) { Ok "profile '$Profile' present in profile list" }
  else { Fail "profile '$Profile' not found in profile list" }

  if ($Chat) {
    Step "Tier-0 chat probe (free chain needs one free-tier key / hermes auth)"
    try {
      $reply = (& $hermes -p $Profile -z "Reply with exactly the two words: hello world" 2>&1 | Out-String).Trim()
      $chatErr = $reply -match '(?i)HTTP\s*\d{3}|no permission|unauthoriz|forbidden|invalid.*key|missing.*key|rate.?limit|quota|not authenticated'
      if ($reply -and -not $chatErr) { Ok "chat returned a real answer: '$reply'" }
      elseif ($chatErr) { Warn "keyless chat returned an AUTH error, not an answer — set ONE free-tier key (or run hermes auth) in the store." }
      else { Warn "empty chat reply (network/provider)" }
    } catch { Warn "chat call failed (network/provider): $_" }
  }
}

# ---- G1 update-safety regression: a planted user skill survives `profile update` -------------
function Test-G1([string]$Profile, [string]$ProfRoot) {
  Step "update safety (G1): user-installed skill survives hermes profile update"
  $userSkill = Join-Path $ProfRoot 'skills\_factory\planted-user-skill\SKILL.md'
  New-Item -ItemType Directory -Force -Path (Split-Path $userSkill) | Out-Null
  Set-Content -LiteralPath $userSkill -Value "---`nname: planted-user-skill`ndescription: factory-home sentinel skill`n---`n" -Encoding UTF8
  & $hermes profile update $Profile --yes 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail "profile update failed during G1 check — cannot assert skill survival"; return }
  if (Test-Path $userSkill) { Ok "user-installed skill under skills/ survived update (G1 guard)" }
  else { Fail "update DELETED a user-installed skill — G1 regression: distribution must ship no skills/ dir" }
  if (Test-Path (Join-Path $ProfRoot 'meta-skills\finish-setup\SKILL.md')) { Ok "finish-setup meta-skill refreshed across update" }
  else { Fail "update dropped the finish-setup meta-skill" }
}

Write-Host "hermes-setup factory-home E2E" -ForegroundColor White
Write-Host "  action:   $Action"
Write-Host "  template: $Template"
Write-Host "  store:    $Store"

Assert-SafeStore   # <-- gate BEFORE any destructive op below

$oldHermesHome = $env:HERMES_HOME
try {
  switch ($Action) {

    'Status' {
      Step "store status"
      Write-Host "    factory snapshot: $(if (Test-Path $Factory) { 'present' } else { 'MISSING — run -Action Build' })"
      Write-Host "    work home:        $(if (Test-Path $Work) { 'present' } else { 'MISSING — run -Action Reset or Build' })"
      if (Test-Path $MetaFile) { Write-Host "    factory vs current dist: $(if ((Get-Content -Raw $MetaFile) -eq (Get-DistFingerprint)) { 'CURRENT' } else { 'STALE (dist changed since Build)' })" }
      if (Test-Path $Work) {
        Enter-WorkHome
        Step "profiles in work home"
        (& $hermes profile list 2>&1 | Out-String).Trim() | Write-Host
      }
    }

    'Clean' {
      Step "clean: removing the whole store"
      if (Test-Path $Store) { Remove-Item -Recurse -Force -LiteralPath $Store; Ok "removed $Store" }
      else { Ok "nothing to remove ($Store does not exist)" }
    }

    'Build' {
      Step "BUILD — fresh install into a clean work home, then snapshot it as the factory baseline"
      if (Test-Path $Work)    { Remove-Item -Recurse -Force -LiteralPath $Work }
      if (Test-Path $Factory) { Remove-Item -Recurse -Force -LiteralPath $Factory }
      Enter-WorkHome
      $profRoot = Join-Path $Work "profiles\$Template"

      Step "install the '$Template' distribution (one step, brand-new home)"
      & $hermes profile install $Dist --name $Template --yes
      if ($LASTEXITCODE -ne 0) { Fail "profile install failed"; break }
      Ok "installed profile '$Template'"

      if (-not $SkipSkills) {
        Step "install a Tier-0 skill (browser-automation-agent) into the baseline"
        & $hermes -p $Template skills install skills-sh/dewdad/open-skills/browser-automation-agent --yes 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Ok "browser-automation-agent installed into the baseline" }
        else { Warn "skill install failed (registry/network) — baseline still valid; retry later" }
      } else { Warn "-SkipSkills: baseline built without the network Tier-0 skill install" }

      Invoke-Assertions -Profile $Template -ProfRoot $profRoot -DistRoot $Dist -Chat

      if ($script:Failures -gt 0) {
        Step "SUMMARY (Build)"
        Write-Host "`n  $($script:Failures) CHECK(S) FAILED — NOT snapshotting a broken baseline. Fix and re-run -Action Build." -ForegroundColor Red
        break
      }
      Step "snapshot work -> factory (the saved 'factory reset' baseline)"
      Copy-Home $Work $Factory
      Set-Content -LiteralPath $MetaFile -Value (Get-DistFingerprint) -Encoding UTF8 -NoNewline
      Ok "factory baseline saved at $Factory"
      Step "SUMMARY (Build)"
      Write-Host "`n  PASS — baseline built and snapshotted." -ForegroundColor Green
    }

    'Reset' {
      if (-not (Test-Path $Factory)) { throw "No factory baseline at $Factory. Build it once first:  -Action Build" }
      if ((Test-Path $MetaFile) -and ((Get-Content -Raw $MetaFile) -ne (Get-DistFingerprint))) {
        Warn "factory baseline is STALE — dist\$Template changed since -Action Build. Rebuild with -Action Build to test current code."
      }
      Step "RESET — restore the factory baseline into work (fast mirror, NOT a reinstall)"
      if (Test-Path $Work) { Remove-Item -Recurse -Force -LiteralPath $Work }
      Copy-Home $Factory $Work
      Ok "restored factory -> work"
      Enter-WorkHome
      $profRoot = Join-Path $Work "profiles\$Template"
      Invoke-Assertions -Profile $Template -ProfRoot $profRoot -DistRoot $Dist -Chat
      Step "SUMMARY (Reset)"
      if ($script:Failures -eq 0) { Write-Host "`n  PASS — freshly-reset baseline satisfies the Tier-0 contract." -ForegroundColor Green }
      else { Write-Host "`n  $($script:Failures) CHECK(S) FAILED — see the [FAIL] lines above." -ForegroundColor Red }
    }

    'Dirty' {
      if (-not (Test-Path $Work)) { throw "No work home at $Work. Build/Reset it first:  -Action Build  (or -Action Reset)." }
      Step "DIRTY — update/install personas on the ACCUMULATED (not reset) work home"
      Enter-WorkHome
      $profRoot = Join-Path $Work "profiles\$Template"

      Step "profile update '$Template' on the dirty home (version-bump-lands-on-existing-user)"
      & $hermes profile update $Template --yes
      if ($LASTEXITCODE -eq 0) { Ok "profile '$Template' updated from the current dist" }
      else { Fail "profile update failed on the dirty home" }
      Invoke-Assertions -Profile $Template -ProfRoot $profRoot -DistRoot $Dist
      Test-G1 -Profile $Template -ProfRoot $profRoot

      if ($NewPersona) {
        $newDist = Join-Path $RepoRoot "dist\$NewPersona"
        if (-not (Test-Path (Join-Path $newDist 'distribution.yaml'))) {
          Fail "dist\$NewPersona not found — compile it first: python -m configurator compile $NewPersona"
        } else {
          $newRoot = Join-Path $Work "profiles\$NewPersona"
          if (Test-Path (Join-Path $newRoot 'config.yaml')) {
            Step "update the existing NEW persona '$NewPersona' on the dirty home (already installed)"
            & $hermes profile update $NewPersona --yes
            if ($LASTEXITCODE -eq 0) { Ok "updated new persona '$NewPersona'" } else { Fail "new persona '$NewPersona' update failed on the dirty home" }
          } else {
            Step "install a NEW persona '$NewPersona' on the dirty home (must not clobber '$Template')"
            & $hermes profile install $newDist --name $NewPersona --yes
            if ($LASTEXITCODE -eq 0) { Ok "installed new persona '$NewPersona'" } else { Fail "new persona '$NewPersona' install failed on the dirty home" }
          }
          if ($LASTEXITCODE -eq 0) {
            Invoke-Assertions -Profile $NewPersona -ProfRoot $newRoot -DistRoot $newDist
            if (Test-Path (Join-Path $profRoot 'config.yaml')) { Ok "existing profile '$Template' still present after '$NewPersona'" }
            else { Fail "handling '$NewPersona' clobbered the existing '$Template' profile" }
          }
        }
      }

      Step "SUMMARY (Dirty)"
      if ($script:Failures -eq 0) { Write-Host "`n  PASS — dirty-home update/install checks passed." -ForegroundColor Green }
      else { Write-Host "`n  $($script:Failures) CHECK(S) FAILED — see the [FAIL] lines above." -ForegroundColor Red }
    }
  }
}
finally {
  # Restore the caller's HERMES_HOME (or clear it) even on an exception / dot-sourced invocation.
  if ($null -eq $oldHermesHome) { Remove-Item Env:\HERMES_HOME -ErrorAction SilentlyContinue }
  else { $env:HERMES_HOME = $oldHermesHome }
}
if ($script:Failures -gt 0) { exit 1 }
