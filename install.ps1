#Requires -Version 5.1
<#
.SYNOPSIS
  List and install Hermes profiles from this repo — the agent/one-command entry point (Windows).

.DESCRIPTION
  Hermes' `hermes profile install` CANNOT install from a repo-SUBDIRECTORY URL (it clones the URL
  root and needs distribution.yaml there). This script bridges that gap: it installs a chosen
  persona from the repo's LOCAL dist/<name> folder, cloning the repo first when run standalone.

  No org/URL is baked in. Run from a clone of hermes-setup and it uses that checkout directly.

.PARAMETER Profile
  Profile to install (a dist/<name> in this repo; see -List).

.PARAMETER List
  List installable profiles (name + description) and exit.

.PARAMETER Name
  Hermes profile name to install under. Default: <Profile>.

.PARAMETER Yes
  Pass --yes to `hermes profile install` (no confirmation prompt).

.PARAMETER Repo
  Clone this repo URL when run standalone (or set $env:HERMES_SETUP_REPO).

.EXAMPLE
  .\install.ps1 -List
.EXAMPLE
  .\install.ps1 il-legal -Name my-legal -Yes
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Profile,
  [switch]$List,
  [string]$Name,
  [switch]$Yes,
  [string]$Repo
)

$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = $env:HERMES_SETUP_REPO }

function Resolve-RepoRoot {
  $scriptDir = $PSScriptRoot
  if ($scriptDir -and (Test-Path -LiteralPath (Join-Path $scriptDir 'dist'))) { return $scriptDir }
  if (-not $Repo) {
    Write-Error "No local dist/ found next to this script and no repo URL given. Run this from a clone of hermes-setup, or pass -Repo <git-url> (or set `$env:HERMES_SETUP_REPO)."
  }
  $git = (Get-Command git -ErrorAction SilentlyContinue).Source
  if (-not $git) { Write-Error "git not found — needed to clone $Repo" }
  $cache = if ($env:HERMES_SETUP_CACHE) { $env:HERMES_SETUP_CACHE } else { Join-Path $env:LOCALAPPDATA 'hermes-setup-cache' }
  if (Test-Path -LiteralPath (Join-Path $cache '.git')) {
    & $git -C $cache pull --ff-only 2>&1 | Out-Null
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cache) | Out-Null
    & $git clone --depth 1 $Repo $cache 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error "clone failed: $Repo" }
  }
  return $cache
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

if (-not $Profile) {
  Write-Host 'No profile selected. Available profiles:'
  Show-Profiles $Profiles
  Write-Host ''
  Write-Host 'Usage: .\install.ps1 <name> [-Name PROFILE] [-Yes] [-Repo GIT_URL]'
  exit 2
}

$src = Join-Path $RepoRoot "dist\$Profile"
if (-not (Test-Path -LiteralPath (Join-Path $src 'distribution.yaml'))) {
  Write-Host "Unknown profile: '$Profile'. Available:"
  Show-Profiles $Profiles
  exit 2
}

$hermes = (Get-Command hermes -ErrorAction SilentlyContinue).Source
if (-not $hermes) { Write-Error 'hermes CLI not found on PATH. Install Hermes first (see PREREQUISITES.md).' }

$profileName = if ($Name) { $Name } else { $Profile }
Write-Host "Installing '$Profile' as Hermes profile '$profileName' from $src ..."
if ($Yes) { & $hermes profile install $src --name $profileName --yes }
else { & $hermes profile install $src --name $profileName }

Write-Host ''
Write-Host 'Installed. Finish setup:'
Write-Host "  hermes -p $profileName        # open the profile"
Write-Host '  # then run /finish-setup inside the agent to add a free key + install its skills'
