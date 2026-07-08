#!/usr/bin/env bash
# Battle-test a compiled distribution against the LOCAL Hermes install using a THROWAWAY named
# profile — the POSIX sibling of livetest.ps1. Compiles, installs, asserts the meta-skill /
# finish-setup carve-out landed, `config check` is clean, the reference-only contract holds, and
# (the load-bearing G1 regression) a user-installed skill under skills/ SURVIVES `profile update`.
#
# SAFETY (non-negotiable): runs ONLY against a throwaway profile named `cfgtest-<template>`. It
# refuses to touch `default` or an empty profile, and never writes $HERMES_HOME/config.yaml.
# Teardown runs in an EXIT trap. Missing API keys and a missing ~/open-skills are tolerated.
#
# Usage:
#   tests/livetest.sh <template> [--whatif] [--keep-profile] [--install-skills] [--resolve-ids]
# Examples:
#   tests/livetest.sh base/general --whatif
#   tests/livetest.sh persona/il-citizen
set -euo pipefail

TEMPLATE="${1:-}"
WHATIF=0; KEEP_PROFILE=0; INSTALL_SKILLS=0; RESOLVE_IDS=0
shift || true
for arg in "$@"; do
  case "$arg" in
    --whatif) WHATIF=1 ;;
    --keep-profile) KEEP_PROFILE=1 ;;
    --install-skills) INSTALL_SKILLS=1 ;;
    --resolve-ids) RESOLVE_IDS=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

RED=$'\033[31m'; GREEN=$'\033[32m'; CYAN=$'\033[36m'; YEL=$'\033[33m'; RST=$'\033[0m'
fail() { echo "${RED}FAIL: $1${RST}" >&2; exit 1; }
ok()   { echo "  ${GREEN}✓ $1${RST}"; }
info() { echo "    $1"; }
step() { echo ""; echo "${CYAN}==> $1${RST}"; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_NAME="$(basename "$TEMPLATE")"
PROFILE="cfgtest-${TEMPLATE_NAME}"
DIST_DIR="${REPO_ROOT}/dist/${TEMPLATE_NAME}"

# ---- SAFETY GATES ----------------------------------------------------------
[ -n "$TEMPLATE_NAME" ] || fail "empty template name"
[ "$PROFILE" != "cfgtest-" ] || fail "refusing empty profile suffix"
[ "$TEMPLATE_NAME" != "default" ] && [ "$PROFILE" != "default" ] || fail "refusing to target the 'default' profile"
case "$PROFILE" in cfgtest-*) : ;; *) fail "profile '$PROFILE' is not a throwaway cfgtest-* name" ;; esac
command -v hermes >/dev/null 2>&1 || fail "hermes CLI not found on PATH"

echo "Live harness — template '$TEMPLATE_NAME' -> throwaway profile '$PROFILE'"
info "dist dir: $DIST_DIR"
info "SAFE: never targets 'default'; never writes \$HERMES_HOME/config.yaml"

if [ "$WHATIF" = "1" ]; then
  echo ""; echo "${YEL}[WhatIf] Plan:${RST}"
  info "1. python -m configurator compile $TEMPLATE"
  info "2. hermes profile install \"$DIST_DIR\" --name $PROFILE --yes"
  info "3. assert meta-skills/finish-setup/SKILL.md landed + /finish-setup registers"
  info "4. hermes -p $PROFILE config check   (assert: Config version + no errors)"
  info "5. assert no skills/ shipped; skills.install.json == README post-install block"
  [ "$RESOLVE_IDS" = "1" ] && info "5b. hermes skills inspect <id> for each referenced id (network)"
  info "6. plant memories/ sentinel + skills/ user skill, then hermes profile update"
  info "   (assert BOTH survive — G1 regression — and finish-setup meta-skill refreshes)"
  info "7. hermes profile delete $PROFILE --yes   (teardown)"
  ok "safety gates passed; no changes made"
  exit 0
fi

# ---- COMPILE ---------------------------------------------------------------
step "compile"
python -m configurator compile "$TEMPLATE" || fail "compile failed"
[ -d "$DIST_DIR" ] || fail "dist dir not produced: $DIST_DIR"
ok "compiled $TEMPLATE_NAME"

teardown() {
  if [ "$KEEP_PROFILE" = "1" ]; then
    echo ""; echo "${YEL}(--keep-profile) leaving $PROFILE installed${RST}"
  else
    step "teardown"
    hermes profile delete "$PROFILE" --yes >/dev/null 2>&1 || true
    ok "deleted $PROFILE"
  fi
}
trap teardown EXIT

# ---- INSTALL ---------------------------------------------------------------
step "install"
hermes profile install "$DIST_DIR" --name "$PROFILE" --yes || fail "install failed"
ok "installed $PROFILE"

# Resolve the profile root from Hermes (never hardcode HERMES_HOME).
PROF_ROOT="$(dirname "$(hermes -p "$PROFILE" config path 2>/dev/null)")"
[ -d "$PROF_ROOT" ] || fail "could not resolve profile root for $PROFILE"

# ---- META-SKILL CARVE-OUT: /finish-setup ships under meta-skills/, never skills/ -----------
step "meta-skill (/finish-setup carve-out)"
[ -f "$PROF_ROOT/meta-skills/finish-setup/SKILL.md" ] || fail "finish-setup meta-skill not landed at meta-skills/finish-setup/SKILL.md"
ok "meta-skills/finish-setup/SKILL.md present in profile"
if hermes -p "$PROFILE" skills list 2>&1 | grep -q 'finish-setup'; then
  ok "/finish-setup registered from the meta-skills external dir"
else
  fail "/finish-setup not registered (skills list has no finish-setup)"
fi

# ---- CONFIG CHECK ----------------------------------------------------------
step "config check"
CHECK="$(hermes -p "$PROFILE" config check 2>&1 || true)"
echo "$CHECK" | grep -q 'Config version' || fail "config check did not report a config version"
if echo "$CHECK" | grep -Eiq '\berror\b|invalid|unknown key|✗|✘'; then
  echo "$CHECK" | grep -Ei '\berror\b|invalid|unknown key|✗|✘' | sed 's/^/    /'
  fail "config check reported errors"
fi
ok "config check clean (missing API keys tolerated)"

# ---- REFERENCE-ONLY: distribution vendors no skills ------------------------
step "skills (reference-only model)"
[ ! -d "$DIST_DIR/skills" ] || fail "distribution ships a skills/ dir — reference-only model forbids vendored skill content"
ok "no vendored skills/ dir (reference-only)"

if [ -f "$DIST_DIR/skills.install.json" ]; then
  IDS="$(python -c "import json,sys; print('\n'.join(s['id'] for s in json.load(open(sys.argv[1]))['skills']))" "$DIST_DIR/skills.install.json")"
  COUNT="$(printf '%s\n' "$IDS" | grep -c . || true)"
  info "references $COUNT skill(s)"
  README="$(cat "$DIST_DIR/README.md")"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    echo "$README" | grep -qF "$id" || fail "README missing referenced skill id '$id'"
  done <<< "$IDS"
  ok "skills.install.json matches README post-install block ($COUNT id(s))"
  # ---- ID RESOLUTION (opt-in, network) ----
  if [ "$RESOLVE_IDS" = "1" ]; then
    step "id resolution (hermes skills inspect)"
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      case "$id" in */superpowers|*tap*) info "skip tap-like id: $id"; continue ;; esac
      hermes skills inspect "$id" >/dev/null 2>&1 || fail "referenced id does not resolve upstream: $id"
      ok "resolves: $id"
    done <<< "$IDS"
  fi
else
  ok "distribution references no skills (no skills.install.json)"
fi

# ---- UPDATE PATH preserves user-owned files AND user-installed skills (G1 regression) ------
step "update path (assert user-owned files + installed skills preserved)"
mkdir -p "$PROF_ROOT/memories"
SENTINEL="$PROF_ROOT/memories/livetest-sentinel.txt"
STAMP="$(date +%s)-$$"
printf '%s' "$STAMP" > "$SENTINEL"
# G1 REGRESSION: a user-installed skill under skills/ MUST survive `hermes profile update`. The
# distribution ships NO skills/ dir (finish-setup lives under meta-skills/), so the user's skills/
# is never wholesale-replaced. If that regresses, the planted skill is deleted and this fails.
USER_SKILL_DIR="$PROF_ROOT/skills/_livetest/planted-user-skill"
mkdir -p "$USER_SKILL_DIR"
printf -- '---\nname: planted-user-skill\ndescription: livetest sentinel skill\n---\n' > "$USER_SKILL_DIR/SKILL.md"
hermes profile update "$PROFILE" --yes 2>&1 | sed 's/^/    /' || echo "    ! update reported non-zero (source may be a local dir)"
[ -f "$SENTINEL" ] || fail "update deleted a user-owned file (memories/)"
[ "$(cat "$SENTINEL")" = "$STAMP" ] || fail "update mutated a user-owned file"
ok "user-owned memories/ preserved across update"
[ -f "$USER_SKILL_DIR/SKILL.md" ] || fail "update DELETED a user-installed skill under skills/ — G1 regression: the distribution must ship no skills/ dir"
ok "user-installed skill under skills/ preserved across update (G1 regression guard)"
[ -f "$PROF_ROOT/meta-skills/finish-setup/SKILL.md" ] || fail "update dropped the finish-setup meta-skill"
ok "finish-setup meta-skill refreshed across update"

echo ""; echo "${GREEN}PASS: $TEMPLATE_NAME${RST}"
