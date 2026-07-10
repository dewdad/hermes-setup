#Requires -Version 5.1
<#
.SYNOPSIS
  Launch the hermes-setup BLANK-SLATE Desktop E2E inside Windows Sandbox — host-safe.

.DESCRIPTION
  Generates a .wsb that maps THIS repo READ-ONLY into a disposable Windows Sandbox and auto-runs
  tests/sandbox/provision.ps1 at logon. The Sandbox is a throwaway VM: nothing it does can touch
  your host, and it is wiped when the window closes. Your real Hermes install
  (%LOCALAPPDATA%\hermes — config.yaml, .env, keys, profiles, auth.json) is never read or written.

.PARAMETER Template      Distribution to test (default: general). Must be compiled under dist/.
.PARAMETER GenerateOnly  Write + validate the .wsb but do NOT launch (CI / inspection).
.PARAMETER NoLog         Do NOT map a writable host log folder. The run stays fully isolated but its
                         [PASS]/[FAIL] results are then visible ONLY inside the VM window. Default:
                         a dedicated, log-only host folder IS mapped writable (the repo mapping stays
                         READ-ONLY) so the run is hands-off and its results are readable on the host.
.PARAMETER NoWait        Launch and return immediately instead of streaming the host log to
                         completion. Ignored when -NoLog (there is no host log to tail).
.PARAMETER PersistHome   DEV FAST-ITERATION MODE (NOT blank-slate). Maps a persistent, writable host
                         folder as the sandbox's HERMES_HOME + Playwright cache + Desktop-app dir, so
                         the ~15-min install (Hermes CLI toolchain, WebView2, Hermes-Setup.exe /S) is
                         paid ONCE and REUSED on every later run (seconds to a working env).
                         Because it deliberately carries state across runs it is NOT a blank slate:
                         use it to iterate on Part B, never as the pristine G9/G10 gate (which is the
                         default, PersistHome-off run).                          Host store: %LOCALAPPDATA%\hermes-sandbox-persist\<template>
                         (delete it to reset to a clean slate).
.PARAMETER ResetState    Only meaningful with -PersistHome. Before the checks, wipe the MUTABLE Hermes
                         state (reinstall the profile pristine from the mapped dist; clear
                         sessions/logs/memories) so each persisted run starts from the post-install
                         BASELINE while keeping the expensive install. OMIT it (the default) to let the
                         persisted home accumulate a lived-in "dirty" state — e.g. to test the impact
                         of a hermes-setup distribution update / version bump on an existing user.
.PARAMETER HostHermes    DEV FAST MODE (CLI-only; NOT blank-slate). Instead of the ~15-min fresh
                         install, map the HOST's already-installed Hermes CLI into the VM at IDENTICAL
                         absolute paths, READ-ONLY, and just put its venv\Scripts on PATH — a working
                         `hermes` in seconds. Maps two host folders: the install dir
                         (HERMES_HOME\hermes-agent — a secret-free SUBFOLDER; the parent home with
                         .env/auth.json/config.yaml is NEVER mapped) and the venv's base uv Python
                         (pyvenv.cfg 'home' — python311.dll + stdlib), because the venv is not
                         self-contained and its launchers bake in absolute paths. HERMES_HOME stays a
                         FRESH VM-local dir (never the host's), so no host secrets/state are touched.
                         CLI-only: the Desktop-app steps (WebView2 + Hermes-Setup.exe) are skipped.
                         Like -PersistHome this is a dev optimization, NOT the pristine G9/G10 gate.

.EXAMPLE
  pwsh -File tests/sandbox/run-sandbox.ps1
.EXAMPLE
  pwsh -File tests/sandbox/run-sandbox.ps1 -Template il-citizen
.EXAMPLE
  pwsh -File tests/sandbox/run-sandbox.ps1 -GenerateOnly
.EXAMPLE
  pwsh -File tests/sandbox/run-sandbox.ps1 -NoWait          # launch, don't tail
.EXAMPLE
  pwsh -File tests/sandbox/run-sandbox.ps1 -PersistHome     # fast dev re-runs (NOT blank-slate)
.PARAMETER Desktop       Provision WebView2 and LAUNCH the native Electron Desktop app via
                         `hermes desktop`, leaving the VM running with the GUI up (instead of the
                         CLI-only stop, or the Hermes-Setup.exe installer). Combined with -HostHermes
                         it passes --skip-build to launch the host's PREBUILT app mapped read-only —
                         a running Desktop in ~a minute, no build, no fresh install.

.EXAMPLE
  pwsh -File tests/sandbox/run-sandbox.ps1 -Template il-therapist -HostHermes   # map host CLI (seconds, CLI-only)
.EXAMPLE
  pwsh -File tests/sandbox/run-sandbox.ps1 -Template il-therapist -HostHermes -Desktop   # + WebView2 + launch the Desktop GUI
#>
[CmdletBinding()]
param(
  [string]$Template = 'general',
  [switch]$GenerateOnly,
  [switch]$NoLog,
  [switch]$NoWait,
  [switch]$PersistHome,
  [switch]$ResetState,
  [switch]$HostHermes,
  [switch]$Desktop
)
$ErrorActionPreference = 'Stop'

# $Template names a dist/ folder AND is interpolated into the .wsb XML + the sandbox LogonCommand,
# so constrain it to a safe profile-name charset (blocks XML breakage / command injection).
if ($Template -notmatch '^[A-Za-z0-9._-]+$') {
  throw "Invalid -Template '$Template'. Allowed characters: letters, digits, '.', '_', '-'."
}
function ConvertTo-XmlText([string]$s) { [System.Security.SecurityElement]::Escape($s) }

$RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$SandboxRepo  = 'C:\hermes-setup'                      # where the repo appears inside the sandbox
$Provision    = "$SandboxRepo\tests\sandbox\provision.ps1"
$SandboxLog   = 'C:\hermes-logs'                       # writable, log-only mount inside the sandbox
$SandboxPersist = 'C:\hermes-persist'                  # writable, persistent HERMES_HOME/cache mount

# ---- host-side log folder (writable; repo mapping itself stays READ-ONLY) --------------------
# A dedicated, log-only folder is the ONE writable mount: provision.ps1 tees its output here so the
# run is hands-off and the host can read the real result without touching the VM. The repo is still
# mapped read-only, and %LOCALAPPDATA%\hermes is never mapped at all.
$LogDirHost = ''
$LogArg     = ''
$LogMapXml  = ''
if (-not $NoLog) {
  $LogDirHost = Join-Path $env:TEMP "hermes-sandbox-logs\$Template"
  # Best-effort clear: a still-running VM from a prior session can hold provision.log open; don't
  # let that abort the launcher (Start-Transcript -Force overwrites it inside the VM anyway).
  if (Test-Path $LogDirHost) {
    try { Remove-Item -Recurse -Force -LiteralPath $LogDirHost -ErrorAction Stop }
    catch { Write-Warning "could not fully clear old log dir (a prior VM may still hold it open): $($_.Exception.Message)" }
  }
  New-Item -ItemType Directory -Force -Path $LogDirHost | Out-Null
  $LogArg    = " -LogDir '$SandboxLog'"
  $LogMapXml = @"

    <MappedFolder>
      <HostFolder>$(ConvertTo-XmlText $LogDirHost)</HostFolder>
      <SandboxFolder>$SandboxLog</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
"@
}

# ---- optional persistent HERMES_HOME (DEV fast-iteration; NOT blank-slate) -------------------
# When -PersistHome is set, map a STABLE writable host folder as the sandbox's HERMES_HOME + caches
# so the ~15-min install is paid once and reused. This host store is deliberately NOT cleared between
# runs (that is the whole point). The repo mapping stays READ-ONLY; the real host %LOCALAPPDATA%\hermes
# is still never mapped. This carries state across runs, so it is NOT the blank-slate gate.
$PersistHostDir = ''
$PersistArg     = ''
$PersistMapXml  = ''
if ($PersistHome) {
  $PersistHostDir = Join-Path $env:LOCALAPPDATA "hermes-sandbox-persist\$Template"
  New-Item -ItemType Directory -Force -Path $PersistHostDir | Out-Null   # created once, never auto-cleared
  $PersistArg    = " -PersistRoot '$SandboxPersist'"
  $PersistMapXml = @"

    <MappedFolder>
      <HostFolder>$(ConvertTo-XmlText $PersistHostDir)</HostFolder>
      <SandboxFolder>$SandboxPersist</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
"@
}

# ---- optional reset-to-baseline (only meaningful with -PersistHome) --------------------------
$ResetArg = ''
if ($ResetState) {
  if ($PersistHome) { $ResetArg = ' -ResetState' }
  else { Write-Warning "-ResetState ignored without -PersistHome (a blank-slate sandbox is already fresh every run)." }
}

# ---- optional mapped HOST Hermes install (DEV fast mode; CLI-only; NOT blank-slate) ----------
# Skip the ~15-min fresh install by mapping the host's already-installed CLI into the VM at IDENTICAL
# absolute paths, READ-ONLY. The venv is NOT self-contained (pyvenv.cfg 'home' points at the base uv
# Python that holds python311.dll + the stdlib) and its launchers bake in absolute paths, so we map
# BOTH the install dir and the base Python at their exact host paths. We map only the secret-free
# 'hermes-agent' SUBFOLDER of HERMES_HOME — the parent home (.env / auth.json / config.yaml / keys) is
# NEVER mapped, and provision.ps1 keeps HERMES_HOME a fresh VM-local dir. NOT the pristine G9/G10 gate.
$HostArg    = ''
$HostMapXml = ''
if ($HostHermes) {
  $hostHome      = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
  $hostInstall   = Join-Path $hostHome 'hermes-agent'
  $hostHermesExe = Join-Path $hostInstall 'venv\Scripts\hermes.exe'
  if (-not (Test-Path $hostHermesExe)) {
    throw "-HostHermes: no host Hermes install at '$hostInstall' (expected venv\Scripts\hermes.exe). Install Hermes on the host first, or omit -HostHermes."
  }
  $pyCfg  = Join-Path $hostInstall 'venv\pyvenv.cfg'
  $basePy = ''
  if (Test-Path $pyCfg) {
    $homeLine = (Get-Content -LiteralPath $pyCfg | Where-Object { $_ -match '^\s*home\s*=' } | Select-Object -First 1)
    if ($homeLine) { $basePy = ($homeLine -replace '^\s*home\s*=\s*', '').Trim() }
  }
  if (-not $basePy -or -not (Test-Path $basePy)) {
    throw "-HostHermes: could not resolve the venv base Python from '$pyCfg' (home='$basePy'). Cannot map a working install."
  }
  # Identical-path (SandboxFolder == HostFolder), read-only mappings so the baked-in absolute paths resolve.
  $HostMapXml = @"

    <MappedFolder>
      <HostFolder>$(ConvertTo-XmlText $hostInstall)</HostFolder>
      <SandboxFolder>$(ConvertTo-XmlText $hostInstall)</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$(ConvertTo-XmlText $basePy)</HostFolder>
      <SandboxFolder>$(ConvertTo-XmlText $basePy)</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
"@
  $HostArg = " -HostHermes -HostInstallDir '$hostInstall'"
}

# ---- optional: provision WebView2 + launch the native Electron Desktop (`hermes desktop`) ----
$DesktopArg = if ($Desktop) { ' -Desktop' } else { '' }

# ---- preflight -------------------------------------------------------------
$distManifest = Join-Path $RepoRoot "dist\$Template\distribution.yaml"
if (-not (Test-Path $distManifest)) {
  throw "dist\$Template not found. Compile it first:  python -m configurator compile $Template"
}
$sandboxExe = Join-Path $env:WINDIR 'System32\WindowsSandbox.exe'
if (-not (Test-Path $sandboxExe)) {
  Write-Warning "Windows Sandbox is not installed/enabled on this machine."
  Write-Warning "Enable it once (Admin PowerShell), then reboot:"
  Write-Warning "  Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -All"
  if (-not $GenerateOnly) { throw "WindowsSandbox.exe missing — enable the feature and re-run." }
}

# ---- generate the .wsb -----------------------------------------------------
$wsb = @"
<Configuration>
  <!-- Generated by tests/sandbox/run-sandbox.ps1 — host-safe blank-slate Desktop E2E. -->
  <Networking>Default</Networking>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$(ConvertTo-XmlText $RepoRoot)</HostFolder>
      <SandboxFolder>$SandboxRepo</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>$LogMapXml$PersistMapXml$HostMapXml
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -NoExit -ExecutionPolicy Bypass -Command "Start-Sleep -Seconds 10; &amp; '$Provision' -Template $Template$LogArg$PersistArg$ResetArg$HostArg$DesktopArg"</Command>
  </LogonCommand>
</Configuration>
"@
$wsbPath = Join-Path $env:TEMP "hermes-blank-$Template.wsb"
Set-Content -LiteralPath $wsbPath -Value $wsb -Encoding UTF8
[xml](Get-Content -LiteralPath $wsbPath -Raw) | Out-Null   # fail loudly if not well-formed XML

Write-Host "Generated Sandbox config: $wsbPath"
Write-Host "  maps (read-only): $RepoRoot  ->  $SandboxRepo"
if (-not $NoLog)   { Write-Host "  maps (writable):  $LogDirHost  ->  $SandboxLog   (log-only)" }
if ($PersistHome)  {
  Write-Host "  maps (writable):  $PersistHostDir  ->  $SandboxPersist   (persistent HERMES_HOME/cache)" -ForegroundColor Yellow
  Write-Host "  PERSIST MODE: NOT a blank slate - install is reused across runs. Delete the host folder to reset." -ForegroundColor Yellow
  if ($ResetState) { Write-Host "  RESET-TO-BASELINE: mutable state wiped each run (fresh post-install slate; install kept)." -ForegroundColor Yellow }
  else             { Write-Host "  DIRTY MODE: mutable state ACCUMULATES across runs (good for testing update/version-bump impact)." -ForegroundColor Yellow }
}
if ($HostHermes) {
  Write-Host "  maps (read-only): $hostInstall  ->  (same path)   (host Hermes install)" -ForegroundColor Yellow
  Write-Host "  maps (read-only): $basePy  ->  (same path)   (venv base Python)" -ForegroundColor Yellow
  if ($Desktop) { Write-Host "  HOST-HERMES MODE: mapped host CLI, no fresh install. NOT a blank slate." -ForegroundColor Yellow }
  else          { Write-Host "  HOST-HERMES MODE: mapped host CLI, no fresh install (seconds). CLI-only - Desktop steps skipped. NOT a blank slate." -ForegroundColor Yellow }
}
if ($Desktop) {
  Write-Host "  DESKTOP MODE: provision WebView2 + launch the native Electron app via 'hermes desktop'$(if ($HostHermes) { ' --skip-build (prebuilt, mapped)' } else { ' (builds from source)' }). VM stays running with the GUI up." -ForegroundColor Yellow
}
Write-Host "  logon auto-runs:  provision.ps1 -Template $Template$LogArg$PersistArg$ResetArg$HostArg$DesktopArg"

if ($GenerateOnly) {
  Write-Host "`n(-GenerateOnly) not launching. Double-click the .wsb, or re-run without -GenerateOnly."
  return
}
Write-Host "`nLaunching Windows Sandbox... your host is untouched; close the window to discard everything."
& $sandboxExe $wsbPath

if ($NoLog -or $NoWait) {
  if (-not $NoLog) { Write-Host "`nPart A runs hands-off inside the VM; its log streams to: $LogDirHost\provision.log" }
  return
}

# ---- stream the host log to completion (hands-off; nothing typed inside the VM) --------------
$logFile  = Join-Path $LogDirHost 'provision.log'
$doneFile = Join-Path $LogDirHost 'DONE.txt'
Write-Host "`nPart A runs hands-off inside the VM. Streaming its log here (fresh Hermes install can take"
Write-Host "several minutes). Ctrl+C stops watching only — the sandbox keeps running; close the VM to discard.`n"
$deadline = (Get-Date).AddMinutes(30)
$shown = 0
while (-not (Test-Path $doneFile) -and (Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 3
  if (Test-Path $logFile) {
    try {
      $lines = @(Get-Content -LiteralPath $logFile -ErrorAction SilentlyContinue)
      if ($lines.Count -gt $shown) {
        $lines[$shown..($lines.Count - 1)] | ForEach-Object { Write-Host $_ }
        $shown = $lines.Count
      }
    } catch {}
  }
}
if (Test-Path $doneFile) {
  $lines = @(Get-Content -LiteralPath $logFile -ErrorAction SilentlyContinue)
  if ($lines.Count -gt $shown) { $lines[$shown..($lines.Count - 1)] | ForEach-Object { Write-Host $_ } }
  $fail = if ((Get-Content -LiteralPath $doneFile -Raw) -match 'failures=(\d+)') { [int]$Matches[1] } else { -1 }
  Write-Host ""
  if     ($fail -eq 0) { Write-Host "PART A COMPLETE: all automated checks passed (row 5 keyless-chat WARN is by design)." -ForegroundColor Green }
  elseif ($fail -gt 0) { Write-Host "PART A COMPLETE: $fail check(s) FAILED - see the [FAIL] lines above." -ForegroundColor Red }
  else                 { Write-Host "PART A COMPLETE (could not parse the failure count from DONE.txt)." -ForegroundColor Yellow }
  Write-Host "Now do Part B (Desktop GUI) inside the same VM, then close the window to discard everything."
} else {
  Write-Host "`nTimed out (30 min) waiting for DONE.txt. The VM may still be installing Hermes, or an" -ForegroundColor Yellow
  Write-Host "installer prompt is waiting inside the VM window. Check the VM, or re-run with -NoWait." -ForegroundColor Yellow
}
