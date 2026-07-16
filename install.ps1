#Requires -Version 5.1
<#
.SYNOPSIS
  List and install Hermes profiles from this repo — the agent/one-command entry point (Windows).

.DESCRIPTION
  Hermes' `hermes profile install` CANNOT install from a repo-SUBDIRECTORY URL (it clones the URL
  root and needs distribution.yaml there). This script bridges that gap: it installs a chosen
  persona from the repo's LOCAL dist/<name> folder, cloning the repo first when run standalone.

  No org/URL is baked in. Run from a clone of hermes-setup and it uses that checkout directly.

.PARAMETER Persona
  Profile to install (a dist/<name> in this repo; see -List).

.PARAMETER List
  List installable profiles (name + description) and exit.

.PARAMETER Name
  Hermes profile name to install under. Default: <Persona>.

.PARAMETER Yes
  Pass --yes to `hermes profile install` (no confirmation prompt).

.PARAMETER Pro
  After install, apply the PAID Nous Portal base-layer config (Nous provider + Tool Gateway) to the
  profile via `hermes config set`, then run the Portal OAuth login. Requires a PAID Nous Portal
  subscription and the general-pro base compiled (dist/general-pro/). The free chain is the default.

.PARAMETER Repo
  Clone this repo URL when run standalone (or set $env:HERMES_SETUP_REPO).

.EXAMPLE
  .\install.ps1 -List
.EXAMPLE
  .\install.ps1 il-legal -Name my-legal -Yes
.EXAMPLE
  .\install.ps1 developer -Pro -Yes
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Persona,
  [switch]$List,
  [string]$Name,
  [switch]$Yes,
  [switch]$Pro,
  [string]$Repo
)

$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = $env:HERMES_SETUP_REPO }

# Derive a downloadable GitHub archive URL from the given repo URL (default branch via HEAD).
# Returns $null for non-GitHub hosts, where no generic archive scheme exists. No org is baked in —
# the URL is computed entirely from the -Repo value the caller supplied.
function Convert-ToGitHubZipUrl($repoUrl) {
  $u = ($repoUrl -as [string]).Trim() -replace '\.git$', ''
  if ($u -match '^git@github\.com:(?<slug>[^/]+/[^/]+)$') { return "https://codeload.github.com/$($Matches.slug)/zip/HEAD" }
  if ($u -match '^(https?://)?github\.com/(?<slug>[^/]+/[^/]+?)/?$') { return "https://codeload.github.com/$($Matches.slug)/zip/HEAD" }
  return $null
}

# A checkout is only reusable if git agrees it has a commit AND the tree actually contains dist/.
# A half-finished clone leaves a .git but no dist/, so presence of .git alone is not enough.
function Test-RepoCheckout($git, $path) {
  if (-not (Test-Path -LiteralPath (Join-Path $path '.git'))) { return $false }
  & $git -C $path rev-parse HEAD 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { return $false }
  return (Test-Path -LiteralPath (Join-Path $path 'dist'))
}

# Clone with retries + a low-speed abort so a stalled transfer fails fast instead of hanging.
# Surfaces git's own output on failure (the old '2>&1 | Out-Null' hid the very errors we diagnose).
function Invoke-RobustClone($git, $url, $dest) {
  for ($i = 1; $i -le 3; $i++) {
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
    $out = & $git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 clone --depth 1 $url $dest 2>&1
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $dest 'dist'))) { return $true }
    Write-Host "  clone attempt $i/3 failed (exit $LASTEXITCODE)."
    if ($out) { $out | ForEach-Object { Write-Host "    git: $_" } }
  }
  return $false
}

# Last-resort recovery when git transport itself is broken: download the repo as a ZIP and extract.
# GitHub-only (URL derived from -Repo); returns the extracted repo root, or $null if unavailable.
function Invoke-ZipFallback($url, $cache) {
  $zipUrl = Convert-ToGitHubZipUrl $url
  if (-not $zipUrl) {
    Write-Host "  no ZIP fallback available for this host (only GitHub URLs are supported)."
    return $null
  }
  $curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
  if (-not $curl) { Write-Host "  curl.exe not found — cannot run the ZIP fallback."; return $null }
  $zipPath = "$cache.zip"
  $extract = "$cache-zip"
  Write-Host "  git clone failed — trying ZIP fallback: $zipUrl"
  & $curl -fsSL -o $zipPath $zipUrl
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zipPath)) { Write-Host "  ZIP download failed."; return $null }
  if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue }
  try { Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force } catch { Write-Host "  ZIP extract failed: $($_.Exception.Message)"; return $null }
  Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
  # A GitHub archive nests everything under a single <repo>-<ref>/ folder.
  $inner = Get-ChildItem -LiteralPath $extract -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'dist') } | Select-Object -First 1
  if (-not $inner) { Write-Host "  ZIP extracted but no dist/ found."; return $null }
  Write-Host "  recovered via ZIP fallback."
  return $inner.FullName
}

function Resolve-RepoRoot {
  $scriptDir = $PSScriptRoot
  if ($scriptDir -and (Test-Path -LiteralPath (Join-Path $scriptDir 'dist'))) { return $scriptDir }
  if (-not $Repo) {
    Write-Error "No local dist/ found next to this script and no repo URL given. Run this from a clone of hermes-setup, or pass -Repo <git-url-or-local-folder> (or set `$env:HERMES_SETUP_REPO)."
  }
  # -Repo may be a local checkout (e.g. a manually extracted ZIP) — use it directly, no clone.
  if ((Test-Path -LiteralPath $Repo -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Repo 'dist'))) {
    return (Resolve-Path -LiteralPath $Repo).Path
  }
  $git = (Get-Command git -ErrorAction SilentlyContinue).Source
  if (-not $git) { Write-Error "git not found — needed to clone $Repo" }
  # Never let a git credential helper pop an interactive prompt (a common silent-hang on Windows).
  $env:GIT_TERMINAL_PROMPT = '0'
  # Key the cache dir by the repo URL so a later -Repo <other-url> never reuses the wrong clone.
  $cacheBase = if ($env:HERMES_SETUP_CACHE) { $env:HERMES_SETUP_CACHE } else { Join-Path $env:LOCALAPPDATA 'hermes-setup-cache' }
  $md5 = [System.Security.Cryptography.MD5]::Create()
  $urlKey = ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($Repo))) -replace '-', '').Substring(0, 12)
  $cache = Join-Path $cacheBase $urlKey
  # Reuse a cached clone ONLY if it is valid; a corrupt/half-clone is nuked and refetched.
  if (Test-Path -LiteralPath (Join-Path $cache '.git')) {
    if (Test-RepoCheckout $git $cache) {
      & $git -C $cache pull --ff-only 2>&1 | Out-Null   # refresh; tolerate offline / non-ff
      return $cache
    }
    Write-Host "Cached checkout at $cache is incomplete or corrupt — removing and re-fetching."
    Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue
  }
  New-Item -ItemType Directory -Force -Path $cacheBase | Out-Null
  if (Invoke-RobustClone $git $Repo $cache) { return $cache }
  $zipRoot = Invoke-ZipFallback $Repo $cache
  if ($zipRoot) { return $zipRoot }
  Write-Host ''
  Write-Host "Could not obtain the repo from: $Repo"
  Write-Host 'Remediation:'
  Write-Host "  1. Download the repo ZIP in a browser (for a GitHub repo: <repo-url>/archive/HEAD.zip),"
  Write-Host '     extract it, then rerun pointing -Repo at the extracted folder:'
  Write-Host "         .\install.ps1 $(if ($Persona) { $Persona } else { '<persona>' }) -Repo '<extracted-folder>'"
  Write-Host '  2. Or clone it yourself and run .\install.ps1 from inside that checkout.'
  Write-Error "clone failed: $Repo"
  exit 1
}

function Get-Profiles($repoRoot) {
  $distRoot = Join-Path $repoRoot 'dist'
  if (-not (Test-Path -LiteralPath $distRoot)) { return @() }
  Get-ChildItem -LiteralPath $distRoot -Directory | ForEach-Object {
    $manifest = Join-Path $_.FullName 'distribution.yaml'
    if (-not (Test-Path -LiteralPath $manifest)) { return }
    $descLine = Select-String -LiteralPath $manifest -Pattern '^description:' | Select-Object -First 1
    $desc = ''
    if ($descLine) { $desc = ($descLine.Line -replace '^description:\s*', '').Trim().Trim('"', "'") }
    [pscustomobject]@{ Name = $_.Name; Description = $desc }
  }
}

function Show-Profiles($profiles) {
  foreach ($p in $profiles) { '  {0,-14} {1}' -f $p.Name, $p.Description | Write-Host }
}

# Splice the paid Nous Portal base-layer config onto an already-installed profile, then OAuth-login.
# The base-layer key/value pairs mirror templates/base/general-pro/template.yaml (its compiled
# dist/general-pro/config.yaml is the canonical declaration + the "is the base compiled?" gate).
function Invoke-PortalSplice($repoRoot, $hermes, $profileName) {
  $cfg = Join-Path $repoRoot 'dist\general-pro\config.yaml'
  if (-not (Test-Path -LiteralPath $cfg)) {
    Write-Error "Paid Portal mode (-Pro) needs the general-pro base compiled, but $cfg is missing. Compile it first:  python -m configurator compile general-pro"
  }
  Write-Host ''
  Write-Host "Applying the PAID Nous Portal base to '$profileName' (requires a paid Portal subscription) ..."
  $pairs = [ordered]@{
    'model.provider'          = 'nous'
    'model.default'           = 'anthropic/claude-sonnet-4.6'
    'model.base_url'          = 'https://inference-api.nousresearch.com/v1'
    'model.max_tokens'        = '128000'
    'web.backend'             = 'nous'
    'web.use_gateway'         = 'true'
    'browser.backend'         = 'nous'
    'browser.use_gateway'     = 'true'
    'image_gen.provider'      = 'nous'
    'image_gen.use_gateway'   = 'true'
    'tts.provider'            = 'nous'
    'tts.use_gateway'         = 'true'
    'delegation.provider'     = 'nous'
    'delegation.model'        = 'anthropic/claude-haiku-4.5'
    'auxiliary.vision.provider' = 'nous'
    'auxiliary.vision.model'  = 'google/gemini-3-flash-preview'
    'auxiliary.vision.base_url' = 'https://inference-api.nousresearch.com/v1'
  }
  foreach ($key in $pairs.Keys) {
    & $hermes -p $profileName config set $key $pairs[$key] 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "  warning: 'hermes -p $profileName config set $key' failed — set it manually." }
  }
  Write-Host 'Logging in to Nous Portal (OAuth) ...'
  & $hermes auth add nous
  if ($LASTEXITCODE -ne 0) { Write-Host "  Portal login not completed. Run 'hermes auth add nous' when a browser is available." }
  Write-Host "Paid Portal base applied. Verify with:  hermes -p $profileName portal info"
}

$RepoRoot = Resolve-RepoRoot
$Profiles = @(Get-Profiles $RepoRoot)

if ($List) {
  Write-Host "Installable profiles (from $((Join-Path $RepoRoot 'dist'))):"
  if ($Profiles.Count -eq 0) { Write-Error "No compiled profiles found under $((Join-Path $RepoRoot 'dist'))." }
  Show-Profiles $Profiles
  Write-Host ''
  Write-Host 'Install one with: .\install.ps1 <name>'
  return
}

if (-not $Persona) {
  Write-Host 'No profile selected. Available profiles:'
  Show-Profiles $Profiles
  Write-Host ''
  Write-Host 'Usage: .\install.ps1 <name> [-Name PROFILE] [-Yes] [-Repo GIT_URL]'
  exit 2
}

$src = Join-Path $RepoRoot "dist\$Persona"
if (-not (Test-Path -LiteralPath (Join-Path $src 'distribution.yaml'))) {
  Write-Host "Unknown profile: '$Persona'. Available:"
  Show-Profiles $Profiles
  exit 2
}

$hermes = (Get-Command hermes -ErrorAction SilentlyContinue).Source
if (-not $hermes) { Write-Error 'hermes CLI not found on PATH. Install Hermes first (see PREREQUISITES.md).' }

$profileName = if ($Name) { $Name } else { $Persona }

# Preflight: fail clearly on a name collision instead of hanging on a Hermes prompt.
$existing = ''
try { $existing = ((& $hermes profile list 2>$null) -join "`n") } catch { }
if ($existing -match "(^|\s)$([regex]::Escape($profileName))(\s|`$)") {
  Write-Host "A Hermes profile named '$profileName' already exists."
  Write-Host "Rerun with a different name:  .\install.ps1 $Persona -Name <new-name>"
  Write-Host "(or update the existing one:  hermes profile update $profileName)"
  exit 3
}

Write-Host "Installing '$Persona' as Hermes profile '$profileName' from $src ..."
if ($Yes) { & $hermes profile install $src --name $profileName --yes }
else { & $hermes profile install $src --name $profileName }
if ($LASTEXITCODE -ne 0) { Write-Host "hermes profile install failed (exit $LASTEXITCODE)."; exit $LASTEXITCODE }

if ($Pro) { Invoke-PortalSplice $RepoRoot $hermes $profileName }

Write-Host ''
Write-Host 'Installed. Finish setup:'
Write-Host "  hermes -p $profileName        # open the profile"
Write-Host '  # then run /finish-setup inside the agent to add a free key + install its skills'
