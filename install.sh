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
#   ./install.sh <name> --pro           # after install, apply the PAID Nous Portal base (see below)
#
# --pro (paid Nous Portal mode): the free chain is the default. With --pro, after the persona is
# installed this splices the base/general-pro base-layer config (Nous provider + Tool Gateway) onto
# the profile via `hermes config set`, then runs the Portal OAuth login (`hermes auth add nous`).
# It requires a PAID Nous Portal subscription and the general-pro base compiled (dist/general-pro/).
#
# Standalone (piped, no local checkout): pass the repo to clone via --repo <url> or $HERMES_SETUP_REPO:
#   curl -fsSL <raw>/install.sh | bash -s -- --repo <git-url> --list
#
# No org/URL is baked in. Run from a clone of hermes-setup and it uses that checkout directly.
set -euo pipefail

LIST=0
ASSUME_YES=0
PRO=0
PROFILE=""
NAME=""
REPO_URL="${HERMES_SETUP_REPO:-}"

usage() {
  cat <<'EOF'
Usage: ./install.sh --list
       ./install.sh <name> [--name PROFILE] [--yes] [--pro] [--repo GIT_URL]
   --list         List installable profiles (name + description) and exit.
   <name>         Profile to install (a dist/<name> in this repo; see --list).
   --name PROFILE Hermes profile name to install under (default: <name>).
   --yes          Pass --yes to `hermes profile install` (no confirmation prompt).
   --pro          After install, apply the PAID Nous Portal base (needs a paid Portal plan).
   --repo GIT_URL Clone this repo URL when run standalone (or set HERMES_SETUP_REPO).
   -h, --help     Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST=1; shift;;
    --name) [ $# -ge 2 ] || { echo "--name requires a value" >&2; usage >&2; exit 2; }; NAME="$2"; shift 2;;
    --repo) [ $# -ge 2 ] || { echo "--repo requires a value" >&2; usage >&2; exit 2; }; REPO_URL="$2"; shift 2;;
    --yes|-y) ASSUME_YES=1; shift;;
    --pro) PRO=1; shift;;
    -h|--help) usage; exit 0;;
    --) shift
        while [ $# -gt 0 ]; do
          if [ -z "$PROFILE" ]; then PROFILE="$1"; shift
          else echo "unexpected argument: $1" >&2; exit 2; fi
        done;;
    -*) echo "unknown option: $1" >&2; usage; exit 2;;
    *) if [ -z "$PROFILE" ]; then PROFILE="$1"; shift; else echo "unexpected argument: $1" >&2; exit 2; fi;;
  esac
done

# Derive a downloadable GitHub tarball URL from the given repo URL (default branch via HEAD).
# Prints nothing for non-GitHub hosts (no generic archive scheme). No org is baked in — the URL is
# computed entirely from the --repo value the caller supplied.
github_tarball_url() {
  local u="${1%.git}" slug=""
  case "$u" in
    git@github.com:*/*)            slug="${u#git@github.com:}";;
    https://github.com/*/*|http://github.com/*/*|github.com/*/*)
      slug="${u#*github.com/}"; slug="${slug%/}";;
    *) return 0;;
  esac
  # Keep only owner/repo (strip any trailing path).
  slug="$(printf '%s' "$slug" | cut -d/ -f1-2)"
  case "$slug" in */*) printf 'https://codeload.github.com/%s/tar.gz/HEAD' "$slug";; esac
}

# A checkout is reusable only if git has a commit AND the tree actually contains dist/.
# A half-finished clone leaves a .git but no dist/, so a .git alone is not enough.
valid_checkout() { [ -d "$1/.git" ] && git -C "$1" rev-parse HEAD >/dev/null 2>&1 && [ -d "$1/dist" ]; }

# Clone with retries + a low-speed abort so a stalled transfer fails fast instead of hanging.
# Surfaces git's own output on failure (the old '>/dev/null 2>&1' hid the very errors we diagnose).
robust_clone() {
  local url="$1" dest="$2" i out
  for i in 1 2 3; do
    rm -rf "$dest"
    if out="$(git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 clone --depth 1 "$url" "$dest" 2>&1)" && [ -d "$dest/dist" ]; then
      return 0
    fi
    echo "  clone attempt $i/3 failed." >&2
    [ -n "$out" ] && printf '    git: %s\n' "$out" >&2
  done
  return 1
}

# Last-resort recovery when git transport itself is broken: download the repo as a tarball.
# GitHub-only (URL derived from --repo); prints the extracted repo root on success.
tarball_fallback() {
  local url="$1" cache="$2" tgz_url tgz extract inner
  tgz_url="$(github_tarball_url "$url")"
  [ -n "$tgz_url" ] || { echo "  no tarball fallback available for this host (only GitHub URLs are supported)." >&2; return 1; }
  command -v curl >/dev/null 2>&1 || { echo "  curl not found — cannot run the tarball fallback." >&2; return 1; }
  tgz="$cache.tar.gz"; extract="$cache-tgz"
  echo "  git clone failed — trying tarball fallback: $tgz_url" >&2
  curl -fsSL -o "$tgz" "$tgz_url" || { echo "  tarball download failed." >&2; return 1; }
  rm -rf "$extract"; mkdir -p "$extract"
  tar -xzf "$tgz" -C "$extract" || { echo "  tarball extract failed." >&2; rm -f "$tgz"; return 1; }
  rm -f "$tgz"
  # A GitHub archive nests everything under a single <repo>-<ref>/ folder.
  for inner in "$extract"/*/; do
    if [ -d "${inner}dist" ]; then printf '%s' "${inner%/}"; return 0; fi
  done
  echo "  tarball extracted but no dist/ found." >&2
  return 1
}

# Resolve the repo root: prefer the checkout this script lives in; otherwise clone REPO_URL.
resolve_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  if [ -n "$script_dir" ] && [ -d "$script_dir/dist" ]; then
    REPO_ROOT="$script_dir"; return
  fi
  if [ -z "$REPO_URL" ]; then
    echo "No local dist/ found next to this script and no repo URL given." >&2
    echo "Run this from a clone of hermes-setup, or pass --repo <git-url-or-local-folder> (or set HERMES_SETUP_REPO)." >&2
    exit 1
  fi
  # --repo may be a local checkout (e.g. a manually extracted archive) — use it directly, no clone.
  if [ -d "$REPO_URL" ] && [ -d "$REPO_URL/dist" ]; then
    REPO_ROOT="$(cd "$REPO_URL" && pwd)"; return
  fi
  command -v git >/dev/null 2>&1 || { echo "git not found — needed to clone $REPO_URL" >&2; exit 1; }
  # Never let a git credential helper pop an interactive prompt (a common silent-hang).
  export GIT_TERMINAL_PROMPT=0
  # Key the cache dir by the repo URL so a later --repo <other-url> never reuses the wrong clone.
  local cache_base url_key cache zip_root
  cache_base="${HERMES_SETUP_CACHE:-$HOME/.cache/hermes-setup}"
  url_key="$(printf '%s' "$REPO_URL" | cksum | cut -d' ' -f1)"
  cache="$cache_base/$url_key"
  mkdir -p "$cache_base"
  # Reuse a cached clone ONLY if it is valid; a corrupt/half-clone is nuked and refetched.
  if [ -d "$cache/.git" ]; then
    if valid_checkout "$cache"; then
      git -C "$cache" pull --ff-only >/dev/null 2>&1 || true   # refresh; tolerate offline / non-ff
      REPO_ROOT="$cache"; return
    fi
    echo "Cached checkout at $cache is incomplete or corrupt — removing and re-fetching." >&2
    rm -rf "$cache"
  fi
  if robust_clone "$REPO_URL" "$cache"; then REPO_ROOT="$cache"; return; fi
  if zip_root="$(tarball_fallback "$REPO_URL" "$cache")" && [ -n "$zip_root" ]; then REPO_ROOT="$zip_root"; return; fi
  echo "" >&2
  echo "Could not obtain the repo from: $REPO_URL" >&2
  echo "Remediation:" >&2
  echo "  1. Download the repo archive (for a GitHub repo: <repo-url>/archive/HEAD.tar.gz)," >&2
  echo "     extract it, then rerun pointing --repo at the extracted folder:" >&2
  echo "         ./install.sh ${PROFILE:-<persona>} --repo '<extracted-folder>'" >&2
  echo "  2. Or clone it yourself and run ./install.sh from inside that checkout." >&2
  exit 1
}

list_profiles() {
  local found=0 d name desc
  for d in "$REPO_ROOT"/dist/*/; do
    [ -f "$d/distribution.yaml" ] || continue
    found=1
    name="$(basename "$d")"
    # pipefail-safe: a manifest with no `description:` must not abort the script.
    desc="$( { grep -m1 -E '^description:' "$d/distribution.yaml" || true; } | sed -E 's/^description:[[:space:]]*//; s/^["'\'']//; s/["'\'']$//' )"
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
  # Preflight: fail clearly on a name collision instead of hanging on a Hermes prompt.
  if hermes profile list 2>/dev/null | grep -Eq "(^|[[:space:]])${profile}([[:space:]]|\$)"; then
    echo "A Hermes profile named '$profile' already exists." >&2
    echo "Rerun with a different name:  ./install.sh $persona --name <new-name>" >&2
    echo "(or update the existing one:  hermes profile update $profile)" >&2
    exit 3
  fi
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

# Splice the paid Nous Portal base-layer config onto an already-installed profile, then OAuth-login.
# The base-layer key/value pairs mirror templates/base/general-pro/template.yaml (its compiled
# dist/general-pro/config.yaml is the canonical declaration + the "is the base compiled?" gate).
portal_splice() {
  local profile="$1" cfg
  cfg="$REPO_ROOT/dist/general-pro/config.yaml"
  if [ ! -f "$cfg" ]; then
    echo "Paid Portal mode (--pro) needs the general-pro base compiled, but $cfg is missing." >&2
    echo "Compile it first:  python -m configurator compile general-pro" >&2
    exit 4
  fi
  echo
  echo "Applying the PAID Nous Portal base to '$profile' (requires a paid Portal subscription) ..."
  local pairs=(
    "model.provider=nous"
    "model.default=anthropic/claude-sonnet-4.6"
    "model.base_url=https://inference-api.nousresearch.com/v1"
    "model.max_tokens=128000"
    "web.backend=nous"
    "web.use_gateway=true"
    "browser.backend=nous"
    "browser.use_gateway=true"
    "image_gen.provider=nous"
    "image_gen.use_gateway=true"
    "tts.provider=nous"
    "tts.use_gateway=true"
    "delegation.provider=nous"
    "delegation.model=anthropic/claude-haiku-4.5"
    "auxiliary.vision.provider=nous"
    "auxiliary.vision.model=google/gemini-3-flash-preview"
    "auxiliary.vision.base_url=https://inference-api.nousresearch.com/v1"
  )
  local kv key val
  for kv in "${pairs[@]}"; do
    key="${kv%%=*}"; val="${kv#*=}"
    hermes -p "$profile" config set "$key" "$val" >/dev/null 2>&1 \
      || echo "  warning: 'hermes -p $profile config set $key' failed — set it manually." >&2
  done
  echo "Logging in to Nous Portal (OAuth) ..."
  hermes auth add nous \
    || echo "  Portal login not completed. Run 'hermes auth add nous' when a browser is available." >&2
  echo "Paid Portal base applied. Verify with:  hermes -p $profile portal info"
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

if [ "$PRO" = 1 ]; then
  portal_splice "${NAME:-$PROFILE}"
fi
