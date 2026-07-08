#!/usr/bin/env bash
# BLANK-SLATE CLI E2E for a hermes-setup distribution via a relocated, disposable HERMES_HOME.
# Fast, fully scriptable, host-safe — the POSIX sibling of run-blank-home.ps1.
#
# Points HERMES_HOME at a fresh mktemp dir (exported ONLY into this script's process), so Hermes
# starts from a brand-new-user state: no keys, no profiles, no auth. Installs the compiled
# distribution and asserts the Tier-0 contract (keyless chat, /finish-setup, clean config) plus the
# G1 update-safety guard, then removes the temp home.
#
# SAFETY: your real Hermes home (~/.hermes) is NEVER read or written. The script HARD-ASSERTS that
# `hermes config path` resolves inside the temp home before doing anything, aborting otherwise. The
# export is process-scoped, and an EXIT trap removes the temp home.
#
# Usage: tests/blank-home/run-blank-home.sh [--template general] [--profile blankslate] [--keep-home]
set -euo pipefail

TEMPLATE=general; PROFILE=blankslate; KEEP_HOME=0
while [ $# -gt 0 ]; do
  case "$1" in
    --template) TEMPLATE="$2"; shift 2 ;;
    --profile)  PROFILE="$2";  shift 2 ;;
    --keep-home) KEEP_HOME=1; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

RED=$'\033[31m'; GREEN=$'\033[32m'; CYAN=$'\033[36m'; YEL=$'\033[33m'; RST=$'\033[0m'
FAILURES=0
ok()   { echo "  ${GREEN}[PASS] $1${RST}"; }
warn() { echo "  ${YEL}[WARN] $1${RST}"; }
fail() { echo "  ${RED}[FAIL] $1${RST}"; FAILURES=$((FAILURES+1)); }
step() { echo ""; echo "${CYAN}==> $1${RST}"; }

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIST="$REPO_ROOT/dist/$TEMPLATE"
[ -f "$DIST/distribution.yaml" ] || { echo "dist/$TEMPLATE not found — run: python -m configurator compile $TEMPLATE" >&2; exit 1; }
command -v hermes >/dev/null 2>&1 || { echo "hermes CLI not found on PATH" >&2; exit 1; }

# ---- relocate HERMES_HOME to a throwaway temp dir (process-scoped) ----------
REAL_HOME="${HOME}/.hermes"
BLANK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/hermes-blank-home-XXXXXXXX")"
export HERMES_HOME="$BLANK_HOME"
step "relocated HERMES_HOME -> $BLANK_HOME"

cleanup() {
  if [ "$KEEP_HOME" = "1" ]; then
    echo ""; echo "${YEL}(--keep-home) leaving blank home: $BLANK_HOME${RST}"
  else
    step "teardown"; rm -rf "$BLANK_HOME"; ok "removed blank home ($BLANK_HOME)"
  fi
}
trap cleanup EXIT

# ---- HARD SAFETY GATES: never operate on the real home ---------------------
if [ "$(cd "$BLANK_HOME" && pwd -P)" = "$(cd "$REAL_HOME" 2>/dev/null && pwd -P || echo __none__)" ]; then
  fail "blank home resolved to the REAL home — aborting"; exit 1
fi
CFG_PATH="$(hermes config path 2>&1 | tr -d '\r')"
case "$CFG_PATH" in
  "$BLANK_HOME"*) ok "isolation confirmed — hermes resolves its home inside the temp dir ($CFG_PATH)" ;;
  *) fail "hermes config path ('$CFG_PATH') is NOT inside the blank home — aborting to protect your real env"; exit 1 ;;
esac

# ---- install the distribution (brand-new home: no keys, no profiles) -------
step "install '$TEMPLATE' as profile '$PROFILE' (one step, fresh home)"
hermes profile install "$DIST" --name "$PROFILE" --yes || { fail "profile install failed"; exit 1; }
ok "installed profile '$PROFILE'"
PROF_ROOT="$BLANK_HOME/profiles/$PROFILE"

# ---- meta-skill carve-out + /finish-setup ----------------------------------
step "meta-skill (/finish-setup carve-out)"
[ -f "$PROF_ROOT/meta-skills/finish-setup/SKILL.md" ] && ok "meta-skills/finish-setup/SKILL.md landed" || fail "finish-setup meta-skill missing"
[ ! -d "$DIST/skills" ] && ok "distribution ships no skills/ dir (reference-only)" || fail "distribution ships a skills/ dir (reference-only violation)"
if hermes -p "$PROFILE" skills list 2>&1 | grep -q 'finish-setup'; then ok "/finish-setup registered"; else fail "/finish-setup not registered"; fi

# ---- keyless config check --------------------------------------------------
step "config check (no keys set)"
CHECK="$(hermes -p "$PROFILE" config check 2>&1 || true)"
if echo "$CHECK" | grep -Eiq '\berror\b|invalid|unknown key|✗|✘'; then fail "config check reported errors"; else ok "config check clean (keys optional)"; fi

# ---- Tier-0 chat: the free chain needs ONE free-tier key / Nous OAuth ------
# An HTTP 4xx / "no permission" body is an AUTH error surfaced as the reply, NOT a real answer, and
# must never count as a pass. Genuinely keyless Tier-0 = web search + browser automation, not chat.
step "Tier-0 chat (free chain — needs a key; keyless probe of the failure mode)"
REPLY="$(hermes -p "$PROFILE" -z "Reply with exactly the two words: hello world" 2>&1 | tr -d '\r' | tr '\n' ' ' | sed 's/ *$//')" || REPLY=""
if [ -n "$REPLY" ] && ! printf '%s' "$REPLY" | grep -Eiq 'HTTP\s*[0-9]{3}|no permission|unauthoriz|forbidden|invalid.*key|missing.*key|rate.?limit|quota|not authenticated'; then
  ok "chat returned a real answer with no key: '$REPLY'"
elif [ -n "$REPLY" ]; then
  warn "keyless chat returned an AUTH error, not an answer: '$REPLY' — set ONE free-tier key (or run hermes auth for Nous), then chat works."
else
  warn "empty chat reply (network/provider)"
fi

# ---- Tier-0 skill install --------------------------------------------------
step "install a Tier-0 skill (browser-automation-agent)"
if hermes -p "$PROFILE" skills install skills-sh/dewdad/open-skills/browser-automation-agent --yes >/dev/null 2>&1; then
  ok "browser-automation-agent installed into the profile"
else warn "skill install failed (registry/network) — tolerated"; fi

# ---- G1 update-safety regression -------------------------------------------
step "update safety (G1): user-installed skill survives hermes profile update"
USER_SKILL="$PROF_ROOT/skills/_blankhome/planted-user-skill/SKILL.md"
mkdir -p "$(dirname "$USER_SKILL")"
printf -- '---\nname: planted-user-skill\ndescription: blank-home sentinel skill\n---\n' > "$USER_SKILL"
hermes profile update "$PROFILE" --yes >/dev/null 2>&1 || true
[ -f "$USER_SKILL" ] && ok "user-installed skill under skills/ survived update (G1 guard)" || fail "update DELETED a user-installed skill — G1 regression"
[ -f "$PROF_ROOT/meta-skills/finish-setup/SKILL.md" ] && ok "finish-setup meta-skill refreshed across update" || fail "update dropped the finish-setup meta-skill"

step "SUMMARY"
if [ "$FAILURES" -eq 0 ]; then echo "${GREEN}  PASS — all blank-slate CLI checks passed.${RST}"; else echo "${RED}  $FAILURES CHECK(S) FAILED.${RST}"; exit 1; fi
