#Requires -Version 5.1
<#
.SYNOPSIS
  BLANK-SLATE CLI E2E for a hermes-setup distribution via a relocated, disposable HERMES_HOME.
  Fast, fully scriptable, host-safe — no VM, no Desktop GUI.

.DESCRIPTION
  Points HERMES_HOME at a throwaway temp directory (PROCESS-SCOPED — only this script and its child
  `hermes` calls see it), so Hermes starts from a genuine brand-new-user state: no keys, no profiles,
  no auth.json, no config. It then installs the compiled distribution and asserts the layman Tier-0
  contract (keyless free chat, /finish-setup registration, clean config) plus the G1 update-safety
  guard, and finally deletes the temp home.

  SAFETY: Your real Hermes home (%LOCALAPPDATA%\hermes) is NEVER read or written. Before doing
  anything, the script HARD-ASSERTS that `hermes config path` resolves INSIDE the temp home and is
  NOT your real home; it aborts otherwise. The env change is process-scoped (setting $env:HERMES_HOME
  in this script never touches your machine/user environment) and the temp home is removed on exit.

.PARAMETER Template     Distribution to test (default: general). Must be compiled under dist/.
.PARAMETER ProfileName  Throwaway profile name to install under the blank home (default: blankslate).
.PARAMETER KeepHome     Leave the temp HERMES_HOME on disk for inspection (default: remove it).

.EXAMPLE
  pwsh -File tests/blank-home/run-blank-home.ps1
.EXAMPLE
  pwsh -File tests/blank-home/run-blank-home.ps1 -Template il-citizen -KeepHome
#>
[CmdletBinding()]
param(
  [string]$Template = 'general',
  [string]$ProfileName = 'blankslate',
  [switch]$KeepHome
)
$ErrorActionPreference = 'Stop'
function Ok($m)   { Write-Host "  [PASS] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:Failures++ }
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
$script:Failures = 0

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Dist = Join-Path $RepoRoot "dist\$Template"
if (-not (Test-Path (Join-Path $Dist 'distribution.yaml'))) {
  throw "dist\$Template not found. Compile it first:  python -m configurator compile $Template"
}
$hermes = (Get-Command hermes -ErrorAction SilentlyContinue).Source
if (-not $hermes) { throw "hermes CLI not found on PATH." }

# ---- relocate HERMES_HOME to a throwaway temp dir (process-scoped) ----------
$realHome  = Join-Path $env:LOCALAPPDATA 'hermes'
$blankHome = Join-Path $env:TEMP ('hermes-blank-home-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $blankHome | Out-Null
$env:HERMES_HOME = $blankHome
Step "relocated HERMES_HOME -> $blankHome"

# ---- HARD SAFETY GATES: never operate on the real home ----------------------
$blankResolved = (Resolve-Path $blankHome).Path
$realResolved  = if (Test-Path $realHome) { (Resolve-Path $realHome).Path } else { $realHome }
if ($blankResolved -ieq $realResolved) { Fail "blank home resolved to the REAL home — aborting"; return }
$cfgPath = (& $hermes config path 2>&1 | Out-String).Trim()
if ($cfgPath -notlike "$blankHome*") {
  Fail "hermes config path ('$cfgPath') is NOT inside the blank home — aborting to protect your real env"
  Remove-Item -Recurse -Force $blankHome -ErrorAction SilentlyContinue
  Remove-Item Env:\HERMES_HOME -ErrorAction SilentlyContinue
  return
}
Ok "isolation confirmed — hermes resolves its home inside the temp dir ($cfgPath)"

try {
  # ---- install the distribution (brand-new home: no keys, no profiles) ------
  Step "install '$Template' as profile '$ProfileName' (one step, fresh home)"
  & $hermes profile install $Dist --name $ProfileName --yes
  if ($LASTEXITCODE -ne 0) { Fail "profile install failed"; return }
  Ok "installed profile '$ProfileName'"
  $profRoot = Join-Path $blankHome "profiles\$ProfileName"

  # ---- meta-skill carve-out + /finish-setup ---------------------------------
  Step "meta-skill (/finish-setup carve-out)"
  if (Test-Path (Join-Path $profRoot 'meta-skills\finish-setup\SKILL.md')) { Ok "meta-skills/finish-setup/SKILL.md landed" }
  else { Fail "finish-setup meta-skill missing from the installed profile" }
  if (Test-Path (Join-Path $Dist 'skills')) { Fail "distribution ships a skills/ dir (reference-only violation)" }
  else { Ok "distribution ships no skills/ dir (reference-only)" }
  $list = (& $hermes -p $ProfileName skills list 2>&1 | Out-String)
  if ($list -match 'finish-setup') { Ok "/finish-setup registered as a slash command" }
  else { Fail "/finish-setup not registered (skills list has no finish-setup)" }

  # ---- keyless config check -------------------------------------------------
  Step "config check (no keys set)"
  $check = (& $hermes -p $ProfileName config check 2>&1 | Out-String)
  if (($check -split "`n") | Where-Object { $_ -match '(?i)\berror\b|invalid|unknown key|✗|✘' }) { Fail "config check reported errors" }
  else { Ok "config check clean (missing provider keys optional/tolerated)" }

  # ---- Tier-0 chat: with NO key the free chain needs one free provider key / Nous OAuth --------
  # An HTTP 4xx / "no permission" body is an AUTH error surfaced as the reply, NOT a real answer —
  # it must never count as a pass. Genuinely keyless Tier-0 = web search + browser automation.
  Step "Tier-0 chat (free chain — expects a key; keyless run just probes the failure mode)"
  try {
    $reply = (& $hermes -p $ProfileName -z "Reply with exactly the two words: hello world" 2>&1 | Out-String).Trim()
    $chatErr = $reply -match '(?i)HTTP\s*\d{3}|no permission|unauthoriz|forbidden|invalid.*key|missing.*key|rate.?limit|quota|not authenticated'
    if ($reply -and -not $chatErr) { Ok "chat returned a real answer: '$reply'" }
    elseif ($chatErr) { Warn "keyless chat returned an AUTH error, not an answer: '$reply' — the free model chain needs ONE free-tier key (or run hermes auth for Nous). Set one and re-run to confirm chat." }
    else { Warn "empty chat reply (network/provider)" }
  } catch { Warn "chat call failed (network/provider): $_" }

  # ---- Tier-0 skill install (referenced-skill path + network) ---------------
  Step "install a Tier-0 skill (browser-automation-agent)"
  & $hermes -p $ProfileName skills install skills-sh/dewdad/open-skills/browser-automation-agent --yes 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) { Ok "browser-automation-agent installed into the profile" }
  else { Warn "skill install failed (registry/network) — tolerated" }

  # ---- G1 update-safety regression ------------------------------------------
  Step "update safety (G1): user-installed skill survives hermes profile update"
  $userSkill = Join-Path $profRoot 'skills\_blankhome\planted-user-skill\SKILL.md'
  New-Item -ItemType Directory -Force -Path (Split-Path $userSkill) | Out-Null
  Set-Content -LiteralPath $userSkill -Value "---`nname: planted-user-skill`ndescription: blank-home sentinel skill`n---`n" -Encoding UTF8
  & $hermes profile update $ProfileName --yes 2>&1 | Out-Null
  if (Test-Path $userSkill) { Ok "user-installed skill under skills/ survived update (G1 guard)" }
  else { Fail "update DELETED a user-installed skill — G1 regression: distribution must ship no skills/ dir" }
  if (Test-Path (Join-Path $profRoot 'meta-skills\finish-setup\SKILL.md')) { Ok "finish-setup meta-skill refreshed across update" }
  else { Fail "update dropped the finish-setup meta-skill" }

  Step "SUMMARY"
  if ($script:Failures -eq 0) { Write-Host "`n  PASS — all blank-slate CLI checks passed." -ForegroundColor Green }
  else { Write-Host "`n  $($script:Failures) CHECK(S) FAILED — see the [FAIL] lines above." -ForegroundColor Red }
}
finally {
  if ($KeepHome) {
    Write-Host "`n(-KeepHome) leaving blank home for inspection: $blankHome" -ForegroundColor Yellow
    Write-Host "  (it is a throwaway temp dir; delete it when done. Your real home was never touched.)" -ForegroundColor Yellow
  } else {
    Step "teardown"
    Remove-Item -Recurse -Force $blankHome -ErrorAction SilentlyContinue
    Ok "removed blank home ($blankHome)"
  }
  Remove-Item Env:\HERMES_HOME -ErrorAction SilentlyContinue
}
if ($script:Failures -gt 0) { exit 1 }
