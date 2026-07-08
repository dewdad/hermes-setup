#Requires -Version 5.1
<#
.SYNOPSIS
  Apply a compiled Hermes persona distribution (dist/<template>) to your DEFAULT Hermes profile.
  Safe on a fresh install or to extend an existing one. For a *named* profile instead, use
  `hermes profile install .\dist\<name> --name <profile>`.

.DESCRIPTION
  Sources from dist/<template> (produced by `python -m configurator compile <template>`).
  Merge semantics (never destructive to your data):
    * config.yaml   -> existing file backed up to config.yaml.bak.<timestamp>, then replaced
    * SOUL.md       -> only written if missing / still the default marker / -Force
    * skills/       -> distribution skills merged in; your other skills are untouched
    * skill-bundles/, cron/, mcp.json -> merged/copied if the distribution ships them
    * .env          -> created from the distribution's .env.EXAMPLE ONLY if missing
  A full backup (hermes backup, or a zip fallback) is taken first unless -SkipBackup.
  Best-effort: clones/pulls the optional shared skills checkout at ~/open-skills.

.PARAMETER Template
  Distribution to apply. A ref ("persona/developer") or bare name ("developer"); the leaf name
  selects dist/<name>. Default: base/general.

.PARAMETER HermesHome
  Target Hermes home. Default: $env:HERMES_HOME, else `hermes config path`, else %LOCALAPPDATA%\hermes.

.PARAMETER DryRun     Show what would change without writing anything.
.PARAMETER Force      Overwrite SOUL.md even if customized.
.PARAMETER SkipBackup Skip the safety backup step.
.PARAMETER SkipSkills Do not copy the distribution skills.
.PARAMETER SkipOpenSkills Do not clone/pull ~/open-skills.
.PARAMETER SkipSkillsInstall Do not auto-install the distribution's referenced skills.
.PARAMETER Yes    Auto-confirm the referenced-skill install prompt (non-interactive).

.EXAMPLE
  .\bootstrap.ps1 -Template persona/developer -DryRun
.EXAMPLE
  .\bootstrap.ps1 -Template il-legal
#>
[CmdletBinding()]
param(
  [string]$Template = 'base/general',
  [string]$HermesHome,
  [switch]$DryRun,
  [switch]$Force,
  [switch]$SkipBackup,
  [switch]$SkipSkills,
  [switch]$SkipOpenSkills,
  [switch]$SkipSkillsInstall,
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$RepoRoot     = $PSScriptRoot
$TemplateName = Split-Path -Leaf $Template
$SourceHome   = Join-Path $RepoRoot "dist\$TemplateName"
$EnvExample   = Join-Path $SourceHome '.env.EXAMPLE'

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Info($m) { Write-Host "    $m" }
function Write-Ok($m)   { Write-Host "  + $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-Skip($m) { Write-Host "  - $m" -ForegroundColor DarkGray }

$HermesCli = (Get-Command hermes -ErrorAction SilentlyContinue).Source

function Resolve-HermesHome {
  param([string]$Explicit)
  if ($Explicit)        { return $Explicit }
  if ($env:HERMES_HOME) { return $env:HERMES_HOME }
  if ($HermesCli) {
    try {
      $cfgPath = (& $HermesCli config path 2>$null | Select-Object -First 1).Trim()
      if ($cfgPath -and (Test-Path -LiteralPath $cfgPath -IsValid)) { return (Split-Path -Parent $cfgPath) }
    } catch { }
  }
  $localApp = Join-Path $env:LOCALAPPDATA 'hermes'
  if (Test-Path -LiteralPath $localApp) { return $localApp }
  $dotHermes = Join-Path $env:USERPROFILE '.hermes'
  if (Test-Path -LiteralPath $dotHermes) { return $dotHermes }
  return $localApp
}

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

function Copy-Tree($srcRoot, $dstRoot, $label) {
  # Merge a directory tree file-by-file (never deletes existing files in the target).
  if (-not (Test-Path -LiteralPath $srcRoot)) { return }
  New-Dir $dstRoot
  Get-ChildItem -LiteralPath $srcRoot -Recurse -File | ForEach-Object {
    $rel  = $_.FullName.Substring($srcRoot.Length).TrimStart('\','/')
    $dest = Join-Path $dstRoot $rel
    if ($DryRun) { Write-Info "[dry-run] $label -> $rel"; return }
    New-Dir (Split-Path -Parent $dest)
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
    Write-Ok "$label`: $rel"
  }
}

Write-Host "Hermes Agent — apply distribution '$TemplateName'" -ForegroundColor White
if ($DryRun) { Write-Warn2 "DRY RUN — no changes will be written." }

if (-not (Test-Path -LiteralPath $SourceHome)) {
  throw "Distribution '$SourceHome' not found. Compile it first: python -m configurator compile $Template"
}

$Target = Resolve-HermesHome -Explicit $HermesHome
Write-Step "Target Hermes home"
Write-Info $Target
if ($HermesCli) { Write-Info "hermes CLI: $HermesCli" } else { Write-Warn2 "hermes CLI not found on PATH." }
New-Dir $Target
$OrigHermesHome = $env:HERMES_HOME
$env:HERMES_HOME = $Target
try {

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
      $zip = Join-Path $env:TEMP ("hermes-home-backup-{0}.zip" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
      Compress-Archive -Path (Join-Path $Target '*') -DestinationPath $zip -Force
      Write-Ok "zip backup: $zip"
    }
  }

  Write-Step "config.yaml"
  $srcCfg = Join-Path $SourceHome 'config.yaml'
  $dstCfg = Join-Path $Target 'config.yaml'
  if (Test-Path -LiteralPath $dstCfg) {
    $bak = "$dstCfg.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    if ($DryRun) { Write-Info "[dry-run] backup existing -> $bak; then replace" }
    else { Copy-Item -LiteralPath $dstCfg -Destination $bak -Force; Write-Ok "backed up existing -> $(Split-Path -Leaf $bak)" }
  }
  if ($DryRun) { Write-Info "[dry-run] copy config.yaml -> $dstCfg" }
  else { Copy-Item -LiteralPath $srcCfg -Destination $dstCfg -Force; Write-Ok "wrote config.yaml" }

  Write-Step "SOUL.md"
  $srcSoul = Join-Path $SourceHome 'SOUL.md'
  $dstSoul = Join-Path $Target 'SOUL.md'
  if (Test-Path -LiteralPath $srcSoul) {
    $writeSoul = $true
    if ((Test-Path -LiteralPath $dstSoul) -and -not $Force) {
      $isDefault = (Get-Content -LiteralPath $dstSoul -Raw) -match '<!--\s*UNCONFIGURED\s*-->'
      if (-not $isDefault) { $writeSoul = $false }
    }
    if ($writeSoul) {
      if ($DryRun) { Write-Info "[dry-run] write SOUL.md -> $dstSoul" }
      else { Copy-Item -LiteralPath $srcSoul -Destination $dstSoul -Force; Write-Ok "wrote SOUL.md" }
    } else { Write-Skip "existing SOUL.md is customized — preserved (use -Force to overwrite)" }
  } else { Write-Skip "distribution ships no SOUL.md" }

  Write-Step "Distribution assets (skills / skill-bundles / cron / mcp.json)"
  if ($SkipSkills) { Write-Skip "skills skipped (-SkipSkills)" }
  else { Copy-Tree (Join-Path $SourceHome 'skills') (Join-Path $Target 'skills') 'skill' }
  Copy-Tree (Join-Path $SourceHome 'skill-bundles') (Join-Path $Target 'skill-bundles') 'bundle'
  Copy-Tree (Join-Path $SourceHome 'cron') (Join-Path $Target 'cron') 'cron'
  $srcMcp = Join-Path $SourceHome 'mcp.json'
  if (Test-Path -LiteralPath $srcMcp) {
    if ($DryRun) { Write-Info "[dry-run] copy mcp.json" }
    else { Copy-Item -LiteralPath $srcMcp -Destination (Join-Path $Target 'mcp.json') -Force; Write-Ok "wrote mcp.json" }
  }

  Write-Step "Optional shared skills (~/open-skills)"
  if ($SkipOpenSkills) { Write-Skip "skipped (-SkipOpenSkills)" }
  elseif ($DryRun) { Write-Info "[dry-run] clone/pull https://github.com/dewdad/open-skills -> ~/open-skills" }
  else {
    $osDir = Join-Path $env:USERPROFILE 'open-skills'
    $git = (Get-Command git -ErrorAction SilentlyContinue).Source
    if (-not $git) { Write-Warn2 "git not found — skipping (config tolerates a missing ~/open-skills)" }
    else {
      try {
        if (Test-Path -LiteralPath (Join-Path $osDir '.git')) { & $git -C $osDir pull --ff-only | Out-Null; Write-Ok "pulled ~/open-skills" }
        else { & $git clone --depth 1 https://github.com/dewdad/open-skills $osDir | Out-Null; Write-Ok "cloned ~/open-skills" }
      } catch { Write-Warn2 "open-skills provisioning failed (tolerated): $($_.Exception.Message)" }
    }
  }

  Write-Step ".env"
  $dstEnv = Join-Path $Target '.env'
  if (-not (Test-Path -LiteralPath $EnvExample)) {
    Write-Skip "distribution ships no .env.EXAMPLE (no keys required)"
  } elseif (-not (Test-Path -LiteralPath $dstEnv)) {
    if ($DryRun) { Write-Info "[dry-run] create .env from .env.EXAMPLE" }
    else { Copy-Item -LiteralPath $EnvExample -Destination $dstEnv -Force; Write-Ok "created .env from template — EDIT IT to add your keys" }
  } else {
    $missing = (Get-EnvKeys $EnvExample) | Where-Object { $_ -notin (Get-EnvKeys $dstEnv) }
    if ($missing) { Write-Warn2 "existing .env preserved. Template keys not present:"; $missing | ForEach-Object { Write-Info "    $_" } }
    else { Write-Ok "existing .env preserved; all template keys present" }
  }

  Write-Step "Referenced skills (auto-install)"
  $InstallManifest = Join-Path $SourceHome 'skills.install.json'
  if ($SkipSkillsInstall) { Write-Skip "skipped (-SkipSkillsInstall)" }
  elseif (-not (Test-Path -LiteralPath $InstallManifest)) { Write-Skip "distribution references no skills" }
  elseif (-not $HermesCli) { Write-Warn2 "hermes CLI not found — skipping skill install (run the README block later)" }
  else {
    $entries = @()
    try { $entries = @((Get-Content -LiteralPath $InstallManifest -Raw | ConvertFrom-Json).skills) } catch { Write-Warn2 "could not read skills.install.json (tolerated)" }
    if (-not $entries -or $entries.Count -eq 0) { Write-Skip "no referenced skills listed" }
    else {
      $ids = @($entries | ForEach-Object { $_.id })
      Write-Info ("references {0} skill(s): {1}" -f $entries.Count, ($ids -join ', '))
      $proceed = $true
      if ($DryRun) { Write-Info "[dry-run] would run 'hermes skills install/tap add' for each (Hermes security-scans each)"; $proceed = $false }
      elseif (-not $Yes) {
        $ans = Read-Host "Install these referenced skills now (Hermes will security-scan each)? [y/N]"
        if ($ans -notmatch '^(?i)(y|yes)$') { $proceed = $false; Write-Skip "declined — install later via the README block" }
      }
      if ($proceed) {
        foreach ($e in $entries) {
          try {
            if ([bool]$e.tap) { & $HermesCli skills tap add $e.id 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { Write-Ok "tap add $($e.id)" } else { Write-Warn2 "tap add $($e.id) reported non-zero (tolerated)" } }
            else { & $HermesCli skills install $e.id --yes 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { Write-Ok "installed $($e.id)" } else { Write-Warn2 "install $($e.id) reported non-zero (tolerated)" } }
          } catch { Write-Warn2 "skill '$($e.id)' failed (tolerated): $($_.Exception.Message)" }
        }
      }
    }
  }

  Write-Step "Verify"
  if ($DryRun) { Write-Info "[dry-run] would run: hermes config check" }
  elseif ($HermesCli) { try { & $HermesCli config check } catch { Write-Warn2 "config check reported issues (see above)." }; Write-Info "Run 'hermes doctor' for a full health check." }
  else { Write-Warn2 "hermes CLI not found — run 'hermes config check' after installing Hermes." }

} finally {
  if ($null -eq $OrigHermesHome) { Remove-Item Env:\HERMES_HOME -ErrorAction SilentlyContinue }
  else { $env:HERMES_HOME = $OrigHermesHome }
}

Write-Host "`nDone." -ForegroundColor Green
Write-Info "Applied '$TemplateName'. Next: edit '$(Join-Path $Target '.env')' with your API keys, then run 'hermes'."
