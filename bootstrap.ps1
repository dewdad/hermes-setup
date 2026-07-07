#Requires -Version 5.1
<#
.SYNOPSIS
  Reproducible Hermes Agent setup — copies managed config, SOUL.md and custom
  skills from this repo into your Hermes home. Safe to run on a fresh install
  or to extend an existing one.

.DESCRIPTION
  Merge semantics (never destructive to your data):
    * config.yaml  -> existing file backed up to config.yaml.bak.<timestamp>, then replaced
    * SOUL.md      -> only written if missing, still the default (<!-- UNCONFIGURED -->),
                      or -Force is given; a customized SOUL.md is preserved
    * skills/      -> managed skills are merged in; your other skills are untouched
    * .env         -> created from .env.example ONLY if missing; an existing .env
                      is never overwritten (missing keys are reported instead)
  A full backup (hermes backup, or a zip fallback) is taken first unless -SkipBackup.

.PARAMETER HermesHome
  Target Hermes home directory. Default: $env:HERMES_HOME, else `hermes config path`,
  else %LOCALAPPDATA%\hermes, else ~\.hermes.

.PARAMETER DryRun
  Show what would change without writing anything.

.PARAMETER Force
  Overwrite SOUL.md even if it has been customized.

.PARAMETER SkipBackup
  Skip the safety backup step.

.PARAMETER SkipSkills
  Do not copy the managed skills.

.EXAMPLE
  .\bootstrap.ps1 -DryRun
.EXAMPLE
  .\bootstrap.ps1
.EXAMPLE
  .\bootstrap.ps1 -HermesHome "D:\hermes" -Force
#>
[CmdletBinding()]
param(
  [string]$HermesHome,
  [switch]$DryRun,
  [switch]$Force,
  [switch]$SkipBackup,
  [switch]$SkipSkills
)

$ErrorActionPreference = 'Stop'
$RepoRoot   = $PSScriptRoot
$SourceHome = Join-Path $RepoRoot 'hermes-home'
$EnvExample = Join-Path $RepoRoot '.env.example'

# ----- logging ---------------------------------------------------------------
function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Info($m) { Write-Host "    $m" }
function Write-Ok($m)   { Write-Host "  + $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-Skip($m) { Write-Host "  - $m" -ForegroundColor DarkGray }

# ----- resolve hermes CLI ----------------------------------------------------
$HermesCli = (Get-Command hermes -ErrorAction SilentlyContinue).Source

# ----- resolve HERMES_HOME ---------------------------------------------------
function Resolve-HermesHome {
  param([string]$Explicit)
  if ($Explicit)          { return $Explicit }
  if ($env:HERMES_HOME)   { return $env:HERMES_HOME }
  if ($HermesCli) {
    try {
      $cfgPath = (& $HermesCli config path 2>$null | Select-Object -First 1).Trim()
      if ($cfgPath -and (Test-Path -LiteralPath $cfgPath -IsValid)) {
        return (Split-Path -Parent $cfgPath)
      }
    } catch { }
  }
  $localApp = Join-Path $env:LOCALAPPDATA 'hermes'
  if (Test-Path -LiteralPath $localApp) { return $localApp }
  $dotHermes = Join-Path $env:USERPROFILE '.hermes'
  if (Test-Path -LiteralPath $dotHermes) { return $dotHermes }
  return $localApp   # sensible default for the Windows Desktop installer
}

# ----- helpers ---------------------------------------------------------------
function New-Dir($path) {
  if ($DryRun) { Write-Info "[dry-run] mkdir $path"; return }
  New-Item -ItemType Directory -Force -Path $path | Out-Null
}

function Get-EnvKeys($file) {
  if (-not (Test-Path -LiteralPath $file)) { return @() }
  Get-Content -LiteralPath $file |
    Where-Object { $_ -match '^\s*[^#\s][^=]*=' } |
    ForEach-Object { ($_ -split '=', 2)[0].Trim() }
}

# =============================================================================
Write-Host "Hermes Agent — reproducible bootstrap" -ForegroundColor White
if ($DryRun) { Write-Warn2 "DRY RUN — no changes will be written." }

if (-not (Test-Path -LiteralPath $SourceHome)) {
  throw "Source '$SourceHome' not found. Run this script from inside the repo."
}

$Target = Resolve-HermesHome -Explicit $HermesHome
Write-Step "Target Hermes home"
Write-Info $Target
if ($HermesCli) { Write-Info "hermes CLI: $HermesCli" } else { Write-Warn2 "hermes CLI not found on PATH (install Hermes, or files will be staged for when it is)." }
New-Dir $Target
# Pin every subsequent CLI call (backup, verify) to the home we're configuring,
# so a custom -HermesHome doesn't back up / check the default home by mistake.
# Saved and restored below so we don't leak this into the caller's shell.
$OrigHermesHome = $env:HERMES_HOME
$env:HERMES_HOME = $Target
try {

# ----- 1. backup -------------------------------------------------------------
Write-Step "Safety backup"
if ($SkipBackup) {
  Write-Skip "skipped (-SkipBackup)"
} elseif (-not (Test-Path -LiteralPath (Join-Path $Target 'config.yaml'))) {
  Write-Skip "nothing to back up (fresh install)"
} elseif ($DryRun) {
  Write-Info "[dry-run] would run 'hermes backup' (or zip $Target)"
} else {
  $done = $false
  if ($HermesCli) {
    try { & $HermesCli backup | Out-Null; Write-Ok "hermes backup created"; $done = $true } catch { Write-Warn2 "hermes backup failed: $($_.Exception.Message)" }
  }
  if (-not $done) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $zip = Join-Path $env:TEMP "hermes-home-backup-$stamp.zip"
    Compress-Archive -Path (Join-Path $Target '*') -DestinationPath $zip -Force
    Write-Ok "zip backup: $zip"
  }
}

# ----- 2. config.yaml --------------------------------------------------------
Write-Step "config.yaml"
$srcCfg = Join-Path $SourceHome 'config.yaml'
$dstCfg = Join-Path $Target 'config.yaml'
if (Test-Path -LiteralPath $dstCfg) {
  $bak = "$dstCfg.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
  if ($DryRun) { Write-Info "[dry-run] backup existing -> $bak; then replace" }
  else { Copy-Item -LiteralPath $dstCfg -Destination $bak -Force; Write-Ok "backed up existing -> $(Split-Path -Leaf $bak)" }
}
if ($DryRun) { Write-Info "[dry-run] copy managed config.yaml -> $dstCfg" }
else { Copy-Item -LiteralPath $srcCfg -Destination $dstCfg -Force; Write-Ok "wrote config.yaml" }

# ----- 3. SOUL.md ------------------------------------------------------------
Write-Step "SOUL.md"
$srcSoul = Join-Path $SourceHome 'SOUL.md'
$dstSoul = Join-Path $Target 'SOUL.md'
$writeSoul = $true
if ((Test-Path -LiteralPath $dstSoul) -and -not $Force) {
  $isDefault = (Get-Content -LiteralPath $dstSoul -Raw) -match '<!--\s*UNCONFIGURED\s*-->'
  if (-not $isDefault) { $writeSoul = $false }
}
if ($writeSoul) {
  if ($DryRun) { Write-Info "[dry-run] write SOUL.md -> $dstSoul" }
  else { Copy-Item -LiteralPath $srcSoul -Destination $dstSoul -Force; Write-Ok "wrote SOUL.md" }
} else {
  Write-Skip "existing SOUL.md is customized — preserved (use -Force to overwrite)"
}

# ----- 4. skills -------------------------------------------------------------
Write-Step "Custom skills"
if ($SkipSkills) {
  Write-Skip "skipped (-SkipSkills)"
} else {
  $srcSkills = Join-Path $SourceHome 'skills'
  $dstSkills = Join-Path $Target 'skills'
  New-Dir $dstSkills
  $skillDirs = Get-ChildItem -LiteralPath $srcSkills -Recurse -Filter 'SKILL.md' -File |
    ForEach-Object { $_.Directory.FullName }
  foreach ($sd in $skillDirs) {
    $rel = $sd.Substring($srcSkills.Length).TrimStart('\','/')
    $dest = Join-Path $dstSkills $rel
    if ($DryRun) { Write-Info "[dry-run] merge skill -> $rel"; continue }
    New-Dir (Split-Path -Parent $dest)
    Copy-Item -LiteralPath $sd -Destination $dest -Recurse -Force
    Write-Ok "skill: $rel"
  }
}

# ----- 5. .env ---------------------------------------------------------------
Write-Step ".env"
$dstEnv = Join-Path $Target '.env'
if (-not (Test-Path -LiteralPath $dstEnv)) {
  if ($DryRun) { Write-Info "[dry-run] create .env from .env.example (fill in your keys)" }
  else { Copy-Item -LiteralPath $EnvExample -Destination $dstEnv -Force; Write-Ok "created .env from template — EDIT IT to add your keys" }
} else {
  $have = Get-EnvKeys $dstEnv
  $need = Get-EnvKeys $EnvExample
  $missing = $need | Where-Object { $_ -notin $have }
  if ($missing) {
    Write-Warn2 "existing .env preserved. Keys in template not present in your .env:"
    $missing | ForEach-Object { Write-Info "    $_" }
  } else {
    Write-Ok "existing .env preserved; all template keys present"
  }
}

# ----- 6. verify -------------------------------------------------------------
Write-Step "Verify"
if ($DryRun) {
  Write-Info "[dry-run] would run: hermes config check ; hermes doctor"
} elseif ($HermesCli) {
  try { & $HermesCli config check } catch { Write-Warn2 "config check reported issues (see above)." }
  Write-Info "Run 'hermes doctor' for a full health check."
} else {
  Write-Warn2 "hermes CLI not found — install Hermes, then run 'hermes config check' && 'hermes doctor'."
}

}
finally {
  # Restore the caller's HERMES_HOME so we don't leak our target into their shell.
  if ($null -eq $OrigHermesHome) { Remove-Item Env:\HERMES_HOME -ErrorAction SilentlyContinue }
  else { $env:HERMES_HOME = $OrigHermesHome }
}

Write-Host "`nDone." -ForegroundColor Green
Write-Info "Next: edit '$dstEnv' with your API keys, then run 'hermes'."
