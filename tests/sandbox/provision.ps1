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
  [string]$Template = 'general',
  [string]$LogDir = '',                    # writable host-mapped log folder (run-sandbox.ps1 -LogDir); repo stays read-only
  [string]$PersistRoot = '',               # writable host-mapped persist folder (run-sandbox.ps1 -PersistHome); reuses the install across runs (NOT blank-slate)
  [switch]$ResetState                      # persist mode only: wipe mutable state to the post-install baseline each run (else the persisted home accumulates a "dirty" state)
)

function Ok($m)   { Write-Host "  [PASS] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:Failures++ }
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
$script:Failures = 0

# ---- host-visible logging (optional; repo stays read-only, only $LogDir is writable) -----------
$script:Transcribing = $false
if ($LogDir -and (Test-Path $LogDir)) {
  try {
    Start-Transcript -LiteralPath (Join-Path $LogDir 'provision.log') -Force -ErrorAction Stop | Out-Null
    $script:Transcribing = $true
  } catch { Write-Warning "could not start transcript in ${LogDir}: $_" }
}

try {
$Dist = Join-Path $RepoRoot "dist\$Template"
Step "blank-slate sandbox E2E — template '$Template'"
Write-Host "    repo (read-only): $RepoRoot"
Write-Host "    dist:             $Dist"
if (-not (Test-Path (Join-Path $Dist 'distribution.yaml'))) {
  Fail "dist not found at $Dist — is the repo mapped into the sandbox?"
  Write-Host "`nCannot continue." -ForegroundColor Red; return
}

# ---- optional persistence (DEV fast re-runs; NOT blank-slate) ---------------
# When run-sandbox.ps1 -PersistHome maps a persistent writable folder as $PersistRoot, relocate
# HERMES_HOME + the Playwright browser cache + the Desktop-app dir under it so the ~15-min install
# (CLI toolchain + Playwright + Hermes-Setup.exe) is paid once and REUSED across runs — install.ps1
# honors $env:HERMES_HOME. Blank-slate runs pass no PersistRoot and keep %LOCALAPPDATA%\hermes.
if ($PersistRoot) {
  $env:HERMES_HOME = Join-Path $PersistRoot 'hermes-home'
  $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $PersistRoot 'ms-playwright'
  New-Item -ItemType Directory -Force -Path $env:HERMES_HOME, $env:PLAYWRIGHT_BROWSERS_PATH | Out-Null
  Write-Host "    PERSIST MODE: HERMES_HOME=$($env:HERMES_HOME) (mapped to host; install reused across runs; NOT blank-slate)"
}
# NB: do NOT name this $hermesHome — PowerShell vars are case-insensitive, so it would collide with
# install.ps1's `param([string]$HermesHome=...)` when that script is Invoke-Expression'd in this scope,
# and (since we read it first) trigger "Cannot overwrite variable HermesHome ... optimized". Use $ResolvedHome.
$ResolvedHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
$profRoot     = Join-Path $ResolvedHome "profiles\$Template"
$desktopDir = if ($PersistRoot) { Join-Path $PersistRoot 'hermes-desktop' } else { '' }

# ---- 1. Fresh Hermes install ------------------------------------------------
Step "install Hermes (fresh, native Windows)"
function Resolve-Hermes {
  # Persist mode ($env:HERMES_HOME set): the install lives UNDER HERMES_HOME. Resolve it there ONLY —
  # never accept a stray hermes.exe from PATH or the default %LOCALAPPDATA%\hermes, which would desync
  # $profRoot (derived from $ResolvedHome) and make the reuse/reset/skip checks target the wrong home.
  if ($env:HERMES_HOME) {
    foreach ($p in @(
      (Join-Path $env:HERMES_HOME 'hermes-agent\venv\Scripts\hermes.exe'),
      (Join-Path $env:HERMES_HOME 'bin\hermes.exe'))) {
      if (Test-Path $p) { return $p }
    }
    return $null   # first persisted run: nothing yet — installer (honoring $env:HERMES_HOME) creates it
  }
  # Default (blank-slate) mode: PATH first, then the standard location.
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

# ---- 1b. reset-to-baseline (persist mode, opt-in) ---------------------------
# -ResetState wipes the MUTABLE Hermes state so a persisted run starts from the post-install baseline
# (fresh profile reinstalled from the mapped dist + no session/log/memory clutter) while KEEPING the
# expensive install (toolchain, venv, Node, Playwright, Desktop app). Omit it to let the persisted
# home accumulate a lived-in "dirty" state on purpose — e.g. to test how a hermes-setup distribution
# update (version bump) lands on an existing user via `hermes profile update`.
if ($ResetState) {
  Step "reset-to-baseline (persist mode): wiping mutable state, keeping the install"
  if (Test-Path (Join-Path $profRoot 'config.yaml')) {
    & $hermes profile delete $Template --yes 2>&1 | Out-Null   # step 2 then reinstalls it pristine from the mapped dist
    if (Test-Path (Join-Path $profRoot 'config.yaml')) { Remove-Item -LiteralPath $profRoot -Recurse -Force -ErrorAction SilentlyContinue }
  }
  foreach ($d in @('sessions', 'logs', 'memories')) {
    $dir = Join-Path $ResolvedHome $d
    if (Test-Path $dir) { Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
  }
  Ok "reset done — profile reinstalled fresh + sessions/logs/memories cleared (install, caches, and any .env keys are preserved)"
} elseif ($PersistRoot) {
  Write-Host "    (persist mode, NO -ResetState: mutable state ACCUMULATES across runs — good for update/version-bump impact testing)"
}

# ---- 2. Install the distribution (blank slate: no keys, no prior profiles) --
Step "install the '$Template' distribution (one step, from the mapped folder)"
if (Test-Path (Join-Path $profRoot 'config.yaml')) {
  # Persisted (dirty) run: bring the existing profile up to the CURRENT mapped dist before asserting,
  # so the checks test today's code — and so this doubles as the "version-bump lands on an existing
  # user" test. (-ResetState already deleted the profile in step 1b, so it takes the else branch.)
  & $hermes profile update $Template --yes 2>&1 | Out-Null
  Ok "profile '$Template' already present (persisted) — updated from the mapped dist to test current code"
} else {
  & $hermes profile install $Dist --name $Template --yes
  if ($LASTEXITCODE -ne 0) { Fail "profile install failed"; return }
  Ok "installed profile '$Template'"
}

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
# NOTE: 'unknown key' is intentionally NOT a failure — the project contract (root AGENTS.md, config
# schema) is that Hermes v0.18.x WARNS (not fails) on unknown config keys like image_gen/tts.
$check = (& $hermes -p $Template config check 2>&1 | Out-String)
if (($check -split "`n") | Where-Object { $_ -match '(?i)\berror\b|invalid|✗|✘' }) {
  ($check -split "`n") | Where-Object { $_ -match '(?i)\berror\b|invalid|✗|✘' } | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
  Fail "config check reported errors"
} else { Ok "config check clean (missing provider keys + unknown-key warnings are tolerated)" }

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

# ---- 8. Hermes DESKTOP prerequisite: Edge WebView2 Runtime (for Part B) ------
# Windows Sandbox ships WITHOUT the Evergreen WebView2 Runtime, so the Hermes Desktop installer
# aborts with "WebView2 not found". Pre-provision it here (silent) so Part B's GUI launches with no
# extra download. Network-tolerant (WARN, not FAIL — Part A is CLI-only) and idempotent.
Step "Hermes Desktop prerequisite: Edge WebView2 Runtime (Part B)"
function Get-WebView2Version {
  foreach ($k in @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}')) {
    $pv = (Get-ItemProperty -Path $k -Name pv -ErrorAction SilentlyContinue).pv
    if ($pv -and $pv -ne '0.0.0.0') { return $pv }
  }
  return $null
}
$wv = Get-WebView2Version
if ($wv) { Ok "WebView2 Runtime already present (pv $wv)" }
else {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $boot = Join-Path $env:TEMP 'MicrosoftEdgeWebview2Setup.exe'
    Write-Host "    downloading the Evergreen WebView2 bootstrapper (official go.microsoft.com link)..."
    Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $boot -UseBasicParsing
    $proc = Start-Process -FilePath $boot -ArgumentList '/silent','/install' -PassThru -Wait
    $wv = Get-WebView2Version
    if ($wv) { Ok "WebView2 Runtime installed (pv $wv) — Hermes Desktop will launch in Part B" }
    else { Warn "WebView2 setup exited ($($proc.ExitCode)) but runtime not detected — Part B Desktop may still prompt to install it" }
  } catch { Warn "could not pre-provision WebView2 (network?): $_ — install it in Part B if the Desktop installer asks" }
}

# ---- 9. Hermes DESKTOP app — install the layman way (Hermes-Setup.exe /S) ----
# The signed Tauri v2 / NSIS bootstrap installer. `/S` is the NSIS silent switch (no GUI), so Part B
# shrinks to "launch Hermes and onboard" — no browser download and no installer click-through in the
# VM's clipboard-less, scaled display. Hermes-Setup.exe also bundles the WebView2 bootstrapper
# (embedBootstrapper) and skips it when the runtime is already present, so step 8 just speeds it up.
# Network/path-tolerant: WARN (not FAIL) — Part A's contract is the CLI, and the NSIS install path is
# not officially documented (verified empirically in the sandbox instead of assumed).
Step "Hermes Desktop app (layman path: Hermes-Setup.exe /S)"
$desktopExe = $null
if ($desktopDir -and (Test-Path $desktopDir)) {
  $desktopExe = Get-ChildItem -Path $desktopDir -Recurse -Filter 'Hermes*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
}
if ($desktopExe) {
  Ok "Hermes Desktop already installed (persisted): $($desktopExe.FullName)"
} else {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $setup = Join-Path $env:TEMP 'Hermes-Setup.exe'
    Write-Host "    downloading Hermes-Setup.exe (signed Tauri bootstrap installer, ~7 MB)..."
    Invoke-WebRequest -Uri 'https://hermes-assets.nousresearch.com/Hermes-Setup.exe' -OutFile $setup -UseBasicParsing
    $sArgs = @('/S'); if ($desktopDir) { $sArgs += "/D=$desktopDir" }   # NSIS: /D must be the LAST arg, unquoted
    Write-Host "    running silent install: Hermes-Setup.exe $($sArgs -join ' ') ..."
    $proc = Start-Process -FilePath $setup -ArgumentList $sArgs -PassThru
    # Guard against a silent installer that never returns: wait up to 12 min, then continue. The VM
    # is disposable, so a still-running installer must NOT block Part A's summary / DONE.txt.
    Wait-Process -Id $proc.Id -Timeout 720 -ErrorAction SilentlyContinue
    $exited = $proc.HasExited
    Start-Sleep -Seconds 3
    $startMenus = @(
      (Join-Path $env:APPDATA     'Microsoft\Windows\Start Menu\Programs'),
      (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')) | Where-Object { Test-Path $_ }
    $landed = $null
    if ($startMenus) { $landed = Get-ChildItem -Path $startMenus -Recurse -Filter '*Hermes*.lnk' -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $landed -and $desktopDir -and (Test-Path $desktopDir)) { $landed = Get-ChildItem -Path $desktopDir -Recurse -Filter 'Hermes*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $exited)                          { Warn "Hermes-Setup.exe /S still running after 12 min — continuing; finish/verify it in the VM (Part B)" }
    elseif ($proc.ExitCode -eq 0 -and $landed) { Ok "Hermes Desktop installed silently ($([IO.Path]::GetFileName($landed.FullName)))" }
    elseif ($proc.ExitCode -eq 0)              { Warn "Hermes-Setup.exe /S exited 0 but no Hermes shortcut/exe found in the usual spots — launch it in Part B" }
    else                                       { Warn "Hermes-Setup.exe /S exited $($proc.ExitCode) — desktop install may be incomplete; run it manually in Part B" }
  } catch { Warn "could not download/run Hermes-Setup.exe (network?): $_ — download+run it manually in Part B" }
}

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
  '  (Hermes Desktop + the Edge WebView2 Runtime were already installed above via Hermes-Setup.exe /S.)',
  '  1. Launch "Hermes" from the Start Menu (no browser download, no installer click-through needed).',
  '     If a first-launch setup runs, let it finish - it provisions the desktop runtime for you.',
  "  2. Import / install the profile from:  $Dist",
  "     (or select the '$Template' profile already installed above).",
  '  3. Run  /finish-setup  in the Desktop chat -> set ONE free provider key (or run hermes auth),',
  '     and confirm it renders the tiered setup flow (the one chat key, Tier-0 vs Tier-1 skills,',
  '     discover-more catalogues).',
  '  4. Send a hello message -> after that one key/sign-in, free chat replies. (Web search + browser',
  '     automation work even before you add the key.)',
  '',
  'When finished, just CLOSE the Sandbox window. Everything here - Hermes, the profile,',
  'any keys you typed, this entire OS - is discarded. Your real machine is untouched.',
  $rule
)
Write-Host ($partB -join "`n") -ForegroundColor White
}
finally {
  # Machine-readable completion marker + transcript flush so the host (and an orchestrating agent)
  # can read the real result WITHOUT touching the VM. Runs even on an early `return` above —
  # finally always executes when leaving the try, including via return.
  if ($LogDir -and (Test-Path $LogDir)) {
    try {
      @(
        "failures=$script:Failures",
        "template=$Template",
        "timestamp=$(Get-Date -Format o)"
      ) -join "`n" | Set-Content -LiteralPath (Join-Path $LogDir 'DONE.txt') -Encoding UTF8
    } catch { Write-Warning "could not write DONE.txt: $_" }
  }
  if ($script:Transcribing) { try { Stop-Transcript | Out-Null } catch {} }
}
