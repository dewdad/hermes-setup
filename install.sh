#!/usr/bin/env bash
# List and install Hermes profiles from this repo — the agent/one-command entry point.
#
# Hermes' `hermes profile install` CANNOT install from a repo-SUBDIRECTORY URL (it clones the URL
# root and needs distribution.yaml there). This script bridges that gap: it installs a chosen
# persona from the repo's LOCAL dist/<name> folder, cloning the repo first when run standalone.
#
# Usage:
#   ./install.sh --list                 # list installable profiles (name + description)
#   ./install.sh <name> [--name PROF]   # install dist/<name> as a Hermes profile (default PROF=<name>)
#   ./install.sh <name> --yes           # skip the Hermes install confirmation prompt
#
# Standalone (piped, no local checkout): pass the repo to clone via --repo <url> or $HERMES_SETUP_REPO:
#   curl -fsSL <raw>/install.sh | bash -s -- --repo <git-url> --list
#
# No org/URL is baked in. Run from a clone of hermes-setup and it uses that checkout directly.
set -euo pipefail

LIST=0
ASSUME_YES=0
PROFILE=""
NAME=""
REPO_URL="${HERMES_SETUP_REPO:-}"

usage() {
  cat <<'EOF'
Usage: ./install.sh --list
       ./install.sh <name> [--name PROFILE] [--yes] [--repo GIT_URL]
  --list         List installable profiles (name + description) and exit.
  <name>         Profile to install (a dist/<name> in this repo; see --list).
  --name PROFILE Hermes profile name to install under (default: <name>).
  --yes          Pass --yes to `hermes profile install` (no confirmation prompt).
  --repo GIT_URL Clone this repo URL when run standalone (or set HERMES_SETUP_REPO).
  -h, --help     Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST=1; shift;;
    --name) NAME="$2"; shift 2;;
    --repo) REPO_URL="$2"; shift 2;;
    --yes|-y) ASSUME_YES=1; shift;;
    -h|--help) usage; exit 0;;
    -*) echo "unknown option: $1" >&2; usage; exit 2;;
    *) if [ -z "$PROFILE" ]; then PROFILE="$1"; shift; else echo "unexpected argument: $1" >&2; exit 2; fi;;
  esac
done

# Resolve the repo root: prefer the checkout this script lives in; otherwise clone REPO_URL.
resolve_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  if [ -n "$script_dir" ] && [ -d "$script_dir/dist" ]; then
    REPO_ROOT="$script_dir"; return
  fi
  if [ -z "$REPO_URL" ]; then
    echo "No local dist/ found next to this script and no repo URL given." >&2
    echo "Run this from a clone of hermes-setup, or pass --repo <git-url> (or set HERMES_SETUP_REPO)." >&2
    exit 1
  fi
  command -v git >/dev/null 2>&1 || { echo "git not found — needed to clone $REPO_URL" >&2; exit 1; }
  local cache="${HERMES_SETUP_CACHE:-$HOME/.cache/hermes-setup}"
  if [ -d "$cache/.git" ]; then
    git -C "$cache" pull --ff-only >/dev/null 2>&1 || true
  else
    mkdir -p "$(dirname "$cache")"
    git clone --depth 1 "$REPO_URL" "$cache" >/dev/null 2>&1 || { echo "clone failed: $REPO_URL" >&2; exit 1; }
  fi
  REPO_ROOT="$cache"
}

list_profiles() {
  local found=0 d name desc
  for d in "$REPO_ROOT"/dist/*/; do
    [ -f "$d/distribution.yaml" ] || continue
    found=1
    name="$(basename "$d")"
    desc="$(grep -E '^description:' "$d/distribution.yaml" | head -n1 | sed -E 's/^description:[[:space:]]*//; s/^["'\'']//; s/["'\'']$//')"
    printf '  %-14s %s\n' "$name" "$desc"
  done
  [ "$found" = 1 ] || { echo "No compiled profiles found under $REPO_ROOT/dist/." >&2; exit 1; }
}

install_profile() {
  local persona="$1" src profile
  src="$REPO_ROOT/dist/$persona"
  if [ ! -f "$src/distribution.yaml" ]; then
    echo "Unknown profile: '$persona'. Available:" >&2
    list_profiles >&2
    exit 2
  fi
  command -v hermes >/dev/null 2>&1 || {
    echo "hermes CLI not found on PATH. Install Hermes first (see PREREQUISITES.md)." >&2
    exit 1
  }
  profile="${NAME:-$persona}"
  echo "Installing '$persona' as Hermes profile '$profile' from $src ..."
  if [ "$ASSUME_YES" = 1 ]; then
    hermes profile install "$src" --name "$profile" --yes
  else
    hermes profile install "$src" --name "$profile"
  fi
  echo
  echo "Installed. Finish setup:"
  echo "  hermes -p $profile        # open the profile"
  echo "  # then run /finish-setup inside the agent to add a free key + install its skills"
}

resolve_repo_root

if [ "$LIST" = 1 ]; then
  echo "Installable profiles (from $REPO_ROOT/dist/):"
  list_profiles
  echo
  echo "Install one with: ./install.sh <name>"
  exit 0
fi

if [ -z "$PROFILE" ]; then
  echo "No profile selected." >&2
  echo "Available profiles:" >&2
  list_profiles >&2
  echo >&2
  usage >&2
  exit 2
fi

install_profile "$PROFILE"
