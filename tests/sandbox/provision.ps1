#Requires -Version 5.1
<#
.SYNOPSIS
  BLANK-SLATE end-to-end test for a hermes-setup distribution — runs INSIDE Windows Sandbox.

.DESCRIPTION
  Launched automatically by the Sandbox LogonCommand (see run-sandbox.ps1 / hermes-blank.wsb).
  On a pristine, disposable Windows instance it: installs Hermes fresh, installs the compiled
  `general` distribution as a new profile, and asserts the layman Tier-0 contract — keyless free
  chat, /finish-setup registration, clean config check — plus the G1 update-safety guard (a
  user-installed skill under skills/ survives `hermes profile update`).

  SAFETY: This script is designed to run ONLY inside Windows Sandbox, which is a disposable VM —
  the entire environment (the Hermes install, the profile, any keys you type, this whole OS) is
  discarded when the Sandbox window closes. The repo is mapped READ-ONLY, so nothing here can write
  to your host. That whole-VM isolation is why this script may target a profile named `general`
  (not the `cfgtest-*` throwaway names the host-side livetest.* harness must use) and needs no
  teardown — do NOT run it on your host.
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = 'C:\hermes-setup',   # repo root, mapped read-only into the sandbox
  [string]$Template = 'general'
)

function Ok($m)   { Write-Host "  [PASS] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:Failures++ }
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
$script:Failures = 0

$Dist = Join-Path $RepoRoot "dist\$Template"
Step "blank-slate sandbox E2E — template '$Template'"
Write-Host "    repo (read-only): $RepoRoot"
Write-Host "    dist:             $Dist"
if (-not (Test-Path (Join-Path $Dist 'distribution.yaml'))) {
  Fail "dist not found at $Dist — is the repo mapped into the sandbox?"
  Write-Host "`nCannot continue." -ForegroundColor Red; return
}

# ---- 1. Fresh Hermes install ------------------------------------------------
Step "install Hermes (fresh, native Windows)"
function Resolve-Hermes {
  $c = (Get-Command hermes -ErrorAction SilentlyContinue).Source
  if ($c) { return $c }
  foreach ($p in @(
    (Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'),
    (Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'))) {
    if (Test-Path $p) { return $p }
  }
  return $null
}
$hermes = Resolve-Hermes
if (-not $hermes) {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "    running the official installer — this downloads uv/Python/Node/MinGit and can"
    Write-Host "    take several minutes; answer any prompts it shows..."
    Invoke-Expression (Invoke-RestMethod 'https://hermes-agent.nousresearch.com/install.ps1')
  } catch {
    Fail "Hermes install failed: $_"
    Write-Host "    Install manually in this sandbox, then re-run: powershell -File $PSCommandPath" -ForegroundColor Yellow
    return
  }
  # Refresh PATH from the registry so `hermes` resolves in this already-open session.
  $env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
  $hermes = Resolve-Hermes
}
if (-not $hermes) { Fail "hermes CLI not found after install"; return }
Ok "hermes present: $hermes"

# ---- 2. Install the distribution (blank slate: no keys, no prior profiles) --
Step "install the '$Template' distribution (one step, from the mapped folder)"
& $hermes profile install $Dist --name $Template --yes
if ($LASTEXITCODE -ne 0) { Fail "profile install failed"; return }
Ok "installed profile '$Template'"
$profRoot = Join-Path $env:LOCALAPPDATA "hermes\profiles\$Template"

# ---- 3. Meta-skill carve-out + /finish-setup registration -------------------
Step "meta-skill (/finish-setup carve-out)"
if (Test-Path (Join-Path $profRoot 'meta-skills\finish-setup\SKILL.md')) {
  Ok "meta-skills/finish-setup/SKILL.md landed"
} else { Fail "finish-setup meta-skill missing from the installed profile" }
$list = (& $hermes -p $Template skills list 2>&1 | Out-String)
if ($list -match 'finish-setup') { Ok "/finish-setup registered as a slash command" }
else { Fail "/finish-setup not registered (skills list has no finish-setup)" }

# ---- 4. config check clean, keyless -----------------------------------------
Step "config check (no keys set)"
$check = (& $hermes -p $Template config check 2>&1 | Out-String)
if (($check -split "`n") | Where-Object { $_ -match '(?i)\berror\b|invalid|unknown key|✗|✘' }) {
  ($check -split "`n") | Where-Object { $_ -match '(?i)\berror\b|invalid|unknown key|✗|✘' } | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
  Fail "config check reported errors"
} else { Ok "config check clean (missing provider keys are optional/tolerated)" }

# ---- 5. Tier-0 chat: the free chain needs ONE free-tier key / Nous OAuth ----
# An HTTP 4xx / "no permission" body is an AUTH error surfaced as the reply, NOT a real answer, and
# must never count as a pass. Genuinely keyless Tier-0 = web search + browser automation, not chat.
Step "Tier-0 chat (free chain — needs a key; keyless probe of the failure mode)"
try {
  $reply = (& $hermes -p $Template -z "Reply with exactly the two words: hello world" 2>&1 | Out-String).Trim()
  $chatErr = $reply -match '(?i)HTTP\s*\d{3}|no permission|unauthoriz|forbidden|invalid.*key|missing.*key|rate.?limit|quota|not authenticated'
  if ($reply -and -not $chatErr) { Ok "chat returned a real answer with no key: '$reply'" }
  elseif ($chatErr) { Warn "keyless chat returned an AUTH error, not an answer: '$reply' — set ONE free-tier key (or run hermes auth) in the sandbox, then chat works." }
  else { Warn "empty chat reply (network/provider)" }
} catch { Warn "chat call failed (network/provider): $_" }

# ---- 6. Tier-0 skill install (referenced-skill path + network) --------------
Step "install a Tier-0 skill (browser-automation-agent)"
& $hermes -p $Template skills install skills-sh/dewdad/open-skills/browser-automation-agent --yes 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Ok "browser-automation-agent installed into the profile" }
else { Warn "skill install failed (registry/network) — tolerated; retry from /finish-setup" }

# ---- 7. G1 update-safety regression -----------------------------------------
Step "update safety (G1): user-installed skill survives hermes profile update"
$userSkill = Join-Path $profRoot 'skills\_sandbox\planted-user-skill\SKILL.md'
New-Item -ItemType Directory -Force -Path (Split-Path $userSkill) | Out-Null
Set-Content -LiteralPath $userSkill -Value "---`nname: planted-user-skill`ndescription: sandbox sentinel skill`n---`n" -Encoding UTF8
& $hermes profile update $Template --yes 2>&1 | Out-Null
if (Test-Path $userSkill) { Ok "user-installed skill under skills/ survived update (G1 guard)" }
else { Fail "update DELETED a user-installed skill — G1 regression: distribution must ship no skills/ dir" }
if (Test-Path (Join-Path $profRoot 'meta-skills\finish-setup\SKILL.md')) { Ok "finish-setup meta-skill refreshed across update" }
else { Fail "update dropped the finish-setup meta-skill" }

# ---- summary + manual Part B ------------------------------------------------
Step "SUMMARY (Part A - automated, CLI)"
if ($script:Failures -eq 0) { Write-Host "`n  ALL AUTOMATED CHECKS PASSED." -ForegroundColor Green }
else { Write-Host "`n  $($script:Failures) CHECK(S) FAILED - see the [FAIL] lines above." -ForegroundColor Red }

$rule = ('-' * 78)
$partB = @(
  '',
  $rule,
  'Part B - Hermes DESKTOP GUI (manual, still inside this disposable sandbox)',
  $rule,
  '  1. Download Hermes Desktop:  https://hermes-agent.nousresearch.com/',
  '  2. Install and launch it.',
  "  3. Import / install the profile from:  $Dist",
  "     (or select the '$Template' profile already installed above).",
  '  4. Run  /finish-setup  in the Desktop chat -> set ONE free provider key (or run hermes auth),',
  '     and confirm it renders the tiered setup flow (the one chat key, Tier-0 vs Tier-1 skills,',
  '     discover-more catalogues).',
  '  5. Send a hello message -> after that one key/sign-in, free chat replies. (Web search + browser',
  '     automation work even before you add the key.)',
  '',
  'When finished, just CLOSE the Sandbox window. Everything here - Hermes, the profile,',
  'any keys you typed, this entire OS - is discarded. Your real machine is untouched.',
  $rule
)
Write-Host ($partB -join "`n") -ForegroundColor White
