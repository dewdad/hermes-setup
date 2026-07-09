#!/usr/bin/env bash
# SAVED-STATE, fully agent-driveable E2E for hermes-setup distributions via a snapshot/restore
# HERMES_HOME. No VM, no Desktop GUI — the Hermes Desktop app shares this exact HERMES_HOME
# (config.yaml, profiles/, auth.json, desktop.json, skills/, sessions/), so driving it through the
# `hermes` CLI exercises the same state the GUI renders.
#
# Relocates HERMES_HOME (PROCESS-SCOPED — exported only in this script + its child `hermes` calls)
# to a persistent host STORE with two homes:
#   <store>/factory/  — a snapshot of a post-install HERMES_HOME ("freshly installed / factory reset"
#                       Hermes Desktop with the compiled profile applied + Tier-0 skills). Built ONCE.
#   <store>/work/     — the live HERMES_HOME the harness points `hermes` at for a run.
#
# Actions:
#   build   Pay the install cost ONCE: fresh profile install + Tier-0 skill into work/, assert the
#           Tier-0 contract, then (only if all checks passed) snapshot work/ -> factory/.
#   reset   Requirement 1 — restore factory/ -> work/ (a fast mirror, seconds, NOT a reinstall) and
#           re-assert the pristine post-install contract. Per-run "start from a factory-reset Desktop".
#   dirty   Requirement 2 — leave work/ AS-IS (accumulated state) and run `hermes profile update`
#           (and, with --new-persona, install/update ANOTHER persona) against that dirty home; assert
#           the update lands and the G1 user-skill-survival guard holds.
#   status  Show the store, which homes exist, and the profiles installed in work/.
#   clean   Remove the whole store (factory + work).
#
# SAFETY (multiple independent gates):
#   * assert_safe_store runs BEFORE any delete/mirror and aborts unless the store resolves to a path
#     that does NOT equal/contain/sit inside the real Hermes home, the repo, dist/, $HOME, or the fs
#     root (the store may live UNDER $HOME — the default does); symlinked store/homes are rejected.
#   * HERMES_HOME is exported PROCESS-SCOPED and `hermes config path` is HARD-ASSERTED to resolve
#     inside the store work home (separator-aware containment), aborting otherwise.
# Store default: ${XDG_DATA_HOME:-$HOME/.local/share}/hermes-e2e/<template>.
#
# Usage:
#   tests/factory-home/factory-home.sh build [--template general] [--skip-skills]
#   tests/factory-home/factory-home.sh reset [--template general]
#   tests/factory-home/factory-home.sh dirty [--template general] [--new-persona il-citizen]
#   tests/factory-home/factory-home.sh status [--template general]
#   tests/factory-home/factory-home.sh clean  [--template general]
set -euo pipefail

ACTION="${1:-reset}"; shift || true
TEMPLATE="general"; NEW_PERSONA=""; STORE=""; SKIP_SKILLS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --template) TEMPLATE="$2"; shift 2 ;;
    --new-persona) NEW_PERSONA="$2"; shift 2 ;;
    --store) STORE="$2"; shift 2 ;;
    --skip-skills) SKIP_SKILLS=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

for n in "$TEMPLATE" "$NEW_PERSONA"; do
  [ -n "$n" ] || continue
  if ! printf '%s' "$n" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    echo "Invalid name '$n'. Allowed: letters, digits, '.', '_', '-'." >&2; exit 2
  fi
  if [ "$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')" = "default" ]; then
    echo "Refusing to target the reserved 'default' profile name (harness contract)." >&2; exit 2
  fi
done

GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'; RST=$'\033[0m'
FAILURES=0
ok()   { echo "  ${GREEN}[PASS]${RST} $*"; }
warn() { echo "  ${YELLOW}[WARN]${RST} $*"; }
fail() { echo "  ${RED}[FAIL]${RST} $*"; FAILURES=$((FAILURES+1)); }
step() { echo; echo "${CYAN}==> $*${RST}"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="$REPO_ROOT/dist/$TEMPLATE"
command -v hermes >/dev/null 2>&1 || { echo "hermes CLI not found on PATH." >&2; exit 1; }
[ -f "$DIST/distribution.yaml" ] || { echo "dist/$TEMPLATE not found. Compile it: python -m configurator compile $TEMPLATE" >&2; exit 1; }

REAL_HOME="${HERMES_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hermes}"
[ -n "$STORE" ] || STORE="${XDG_DATA_HOME:-$HOME/.local/share}/hermes-e2e/$TEMPLATE"
FACTORY="$STORE/factory"
WORK="$STORE/work"
META_FILE="$STORE/factory.meta"   # sidecar OUTSIDE factory/ so it isn't mirrored into work/

# ---- path helpers (normalize WITHOUT requiring existence) -------------------------------------
abspath() {
  if command -v realpath >/dev/null 2>&1 && realpath -m -- / >/dev/null 2>&1; then
    realpath -m -- "$1"
  else
    case "$1" in /*) printf '%s' "${1%/}" ;; *) printf '%s' "${PWD%/}/${1#./}" ;; esac
  fi
}
# path_contained CHILD PARENT -> 0 if CHILD == PARENT or CHILD sits inside PARENT (separator-aware)
path_contained() {
  local c p; c="$(abspath "$1")"; p="$(abspath "$2")"; c="${c%/}"; p="${p%/}"
  [ "$c" = "$p" ] && return 0
  case "$c/" in "$p/"*) return 0 ;; *) return 1 ;; esac
}

# ---- SAFETY PREFLIGHT: run BEFORE any delete/mirror -------------------------------------------
assert_safe_store() {
  local storeFull; storeFull="$(abspath "$STORE")"
  # 1. No overlap (either direction) with the real home, the repo, or dist/.
  local f
  for f in "$REAL_HOME" "$REPO_ROOT" "$REPO_ROOT/dist"; do
    if path_contained "$storeFull" "$f" || path_contained "$f" "$storeFull"; then
      echo "SAFETY ABORT: store '$storeFull' overlaps a protected path '$(abspath "$f")'." >&2; exit 1
    fi
  done
  # 2. Must not EQUAL or be an ANCESTOR of $HOME (store UNDER $HOME is fine — the default is).
  if [ -n "${HOME:-}" ] && path_contained "$(abspath "$HOME")" "$storeFull"; then
    echo "SAFETY ABORT: store '$storeFull' equals or contains \$HOME." >&2; exit 1
  fi
  # 3. Must not be the filesystem root.
  [ "$storeFull" != "/" ] || { echo "SAFETY ABORT: store resolves to '/'." >&2; exit 1; }
  # 4. Reject symlinked store or homes (a delete/mirror could otherwise escape to the link target).
  for f in "$STORE" "$WORK" "$FACTORY"; do
    if [ -L "$f" ]; then echo "SAFETY ABORT: '$f' is a symlink — refusing to delete/mirror through it." >&2; exit 1; fi
  done
}

# ---- mirror one HERMES_HOME dir onto another (fast, exact) -----------------------------------
copy_home() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src/" "$dst/"
  else
    # exact mirror WITHOUT rsync: clear dst (incl. dotfiles/dotdirs), then copy everything.
    find "$dst" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    cp -a "$src/." "$dst/"
  fi
}

# ---- fingerprint the source dist so a stale factory is detectable ----------------------------
dist_fingerprint() {
  printf 'template=%s\n' "$TEMPLATE"
  local f h
  for f in SOUL.md config.yaml distribution.yaml skills.install.json; do
    [ -f "$DIST/$f" ] || continue
    if command -v sha256sum >/dev/null 2>&1; then h="$(sha256sum "$DIST/$f" | awk '{print $1}')"
    else h="$(shasum -a 256 "$DIST/$f" | awk '{print $1}')"; fi
    printf '%s=%s\n' "$f" "$h"
  done
}

# ---- point HERMES_HOME at $WORK + HARD isolation gate ----------------------------------------
enter_work_home() {
  mkdir -p "$WORK"
  export HERMES_HOME="$WORK"
  if path_contained "$WORK" "$REAL_HOME" || path_contained "$REAL_HOME" "$WORK"; then
    echo "SAFETY ABORT: work home '$WORK' overlaps the real home '$REAL_HOME'." >&2; exit 1
  fi
  local cfg cfgdir
  cfg="$(hermes config path 2>&1 | tr -d '\r' | tail -n1)"
  cfgdir="$(dirname "$cfg" 2>/dev/null || printf '')"
  if [ -z "$cfgdir" ] || { ! path_contained "$cfg" "$WORK" && ! path_contained "$cfgdir" "$WORK"; }; then
    echo "SAFETY ABORT: hermes config path ('$cfg') is NOT inside the store work home ('$WORK')." >&2; exit 1
  fi
  ok "isolation confirmed — hermes resolves its home inside the store ($cfg)"
}

# ---- shared assertion suite (the CLI-driveable Desktop contract) -----------------------------
# args: <profile> <profRoot> <distRoot> [chat]
invoke_assertions() {
  local profile="$1" profRoot="$2" distRoot="$3" chat="${4:-}"
  step "meta-skill (/finish-setup carve-out) + reference-only [$profile]"
  [ -f "$profRoot/meta-skills/finish-setup/SKILL.md" ] && ok "meta-skills/finish-setup/SKILL.md present" || fail "finish-setup meta-skill missing from profile '$profile'"
  [ -d "$distRoot/skills" ] && fail "distribution '$distRoot' ships a skills/ dir (reference-only violation)" || ok "distribution ships no skills/ dir (reference-only)"
  if hermes -p "$profile" skills list 2>&1 | grep -q 'finish-setup'; then ok "/finish-setup registered as a slash command"; else fail "/finish-setup not registered (skills list has no finish-setup)"; fi

  step "config check (no keys required) [$profile]"
  local check; check="$(hermes -p "$profile" config check 2>&1 || true)"
  if printf '%s\n' "$check" | grep -Eiq '\berror\b|invalid|✗|✘'; then
    printf '%s\n' "$check" | grep -Ei '\berror\b|invalid|✗|✘' | sed 's/^/      /'
    fail "config check reported errors"
  else ok "config check clean (missing provider keys + unknown-key warnings tolerated)"; fi

  # profile actually loaded: it must appear by name in `profile list`.
  if hermes profile list 2>&1 | grep -Eq "(^|[[:space:]])$profile([[:space:]]|@|\$)"; then ok "profile '$profile' present in profile list"; else fail "profile '$profile' not found in profile list"; fi

  if [ "$chat" = "chat" ]; then
    step "Tier-0 chat probe (free chain needs one free-tier key / hermes auth)"
    local reply; reply="$(hermes -p "$profile" -z 'Reply with exactly the two words: hello world' 2>&1 | tr -d '\r' || true)"
    if printf '%s' "$reply" | grep -Eiq 'HTTP\s*[0-9]{3}|no permission|unauthoriz|forbidden|invalid.*key|missing.*key|rate.?limit|quota|not authenticated'; then
      warn "keyless chat returned an AUTH error, not an answer — set ONE free-tier key (or run hermes auth) in the store."
    elif [ -n "$reply" ]; then ok "chat returned a real answer: '$reply'"
    else warn "empty chat reply (network/provider)"; fi
  fi
}

# ---- G1 update-safety regression -------------------------------------------------------------
test_g1() {
  local profile="$1" profRoot="$2"
  step "update safety (G1): user-installed skill survives hermes profile update"
  local userSkill="$profRoot/skills/_factory/planted-user-skill/SKILL.md"
  mkdir -p "$(dirname "$userSkill")"
  printf -- '---\nname: planted-user-skill\ndescription: factory-home sentinel skill\n---\n' > "$userSkill"
  if ! hermes profile update "$profile" --yes >/dev/null 2>&1; then
    fail "profile update failed during G1 check — cannot assert skill survival"; return
  fi
  [ -f "$userSkill" ] && ok "user-installed skill under skills/ survived update (G1 guard)" || fail "update DELETED a user-installed skill — G1 regression"
  [ -f "$profRoot/meta-skills/finish-setup/SKILL.md" ] && ok "finish-setup meta-skill refreshed across update" || fail "update dropped the finish-setup meta-skill"
}

echo "hermes-setup factory-home E2E"
echo "  action:   $ACTION"
echo "  template: $TEMPLATE"
echo "  store:    $STORE"

assert_safe_store   # <-- gate BEFORE any destructive op below

case "$ACTION" in
  status)
    step "store status"
    if [ -d "$FACTORY" ]; then echo "    factory snapshot: present"; else echo "    factory snapshot: MISSING — run: build"; fi
    if [ -d "$WORK" ]; then echo "    work home:        present"; else echo "    work home:        MISSING — run: reset (or build)"; fi
    if [ -f "$META_FILE" ]; then
      if [ "$(cat "$META_FILE")" = "$(dist_fingerprint)" ]; then echo "    factory vs current dist: CURRENT"; else echo "    factory vs current dist: STALE (dist changed since build)"; fi
    fi
    if [ -d "$WORK" ]; then enter_work_home; step "profiles in work home"; hermes profile list 2>&1 || true; fi
    ;;

  clean)
    step "clean: removing the whole store"
    if [ -d "$STORE" ]; then rm -rf "$STORE"; ok "removed $STORE"; else ok "nothing to remove ($STORE does not exist)"; fi
    ;;

  build)
    step "BUILD — fresh install into a clean work home, then snapshot it as the factory baseline"
    rm -rf "$WORK" "$FACTORY"
    enter_work_home
    profRoot="$WORK/profiles/$TEMPLATE"
    step "install the '$TEMPLATE' distribution (one step, brand-new home)"
    if ! hermes profile install "$DIST" --name "$TEMPLATE" --yes; then
      fail "profile install failed"; step "SUMMARY (build)"; echo; echo "  ${RED}install failed — NOT snapshotting.${RST}"; exit 1
    fi
    ok "installed profile '$TEMPLATE'"
    if [ "$SKIP_SKILLS" -eq 0 ]; then
      step "install a Tier-0 skill (browser-automation-agent) into the baseline"
      if hermes -p "$TEMPLATE" skills install skills-sh/dewdad/open-skills/browser-automation-agent --yes >/dev/null 2>&1; then ok "browser-automation-agent installed into the baseline"; else warn "skill install failed (registry/network) — baseline still valid; retry later"; fi
    else warn "--skip-skills: baseline built without the network Tier-0 skill install"; fi
    invoke_assertions "$TEMPLATE" "$profRoot" "$DIST" chat
    if [ "$FAILURES" -gt 0 ]; then
      step "SUMMARY (build)"; echo; echo "  ${RED}$FAILURES CHECK(S) FAILED — NOT snapshotting a broken baseline. Fix and re-run: build${RST}"; exit 1
    fi
    step "snapshot work -> factory (the saved 'factory reset' baseline)"
    copy_home "$WORK" "$FACTORY"
    dist_fingerprint > "$META_FILE"
    ok "factory baseline saved at $FACTORY"
    step "SUMMARY (build)"; echo; echo "  ${GREEN}PASS — baseline built and snapshotted.${RST}"
    ;;

  reset)
    [ -d "$FACTORY" ] || { echo "No factory baseline at $FACTORY. Build it once first: build" >&2; exit 1; }
    if [ -f "$META_FILE" ] && [ "$(cat "$META_FILE")" != "$(dist_fingerprint)" ]; then
      warn "factory baseline is STALE — dist/$TEMPLATE changed since build. Rebuild with: build"
    fi
    step "RESET — restore the factory baseline into work (fast mirror, NOT a reinstall)"
    rm -rf "$WORK"
    copy_home "$FACTORY" "$WORK"
    ok "restored factory -> work"
    enter_work_home
    profRoot="$WORK/profiles/$TEMPLATE"
    invoke_assertions "$TEMPLATE" "$profRoot" "$DIST" chat
    step "SUMMARY (reset)"
    if [ "$FAILURES" -eq 0 ]; then echo; echo "  ${GREEN}PASS — freshly-reset baseline satisfies the Tier-0 contract.${RST}"; else echo; echo "  ${RED}$FAILURES CHECK(S) FAILED — see the [FAIL] lines above.${RST}"; fi
    ;;

  dirty)
    [ -d "$WORK" ] || { echo "No work home at $WORK. Build/Reset it first: build (or reset)." >&2; exit 1; }
    step "DIRTY — update/install personas on the ACCUMULATED (not reset) work home"
    enter_work_home
    profRoot="$WORK/profiles/$TEMPLATE"
    step "profile update '$TEMPLATE' on the dirty home (version-bump-lands-on-existing-user)"
    if hermes profile update "$TEMPLATE" --yes; then ok "profile '$TEMPLATE' updated from the current dist"; else fail "profile update failed on the dirty home"; fi
    invoke_assertions "$TEMPLATE" "$profRoot" "$DIST"
    test_g1 "$TEMPLATE" "$profRoot"
    if [ -n "$NEW_PERSONA" ]; then
      newDist="$REPO_ROOT/dist/$NEW_PERSONA"
      if [ ! -f "$newDist/distribution.yaml" ]; then
        fail "dist/$NEW_PERSONA not found — compile it first: python -m configurator compile $NEW_PERSONA"
      else
        newRoot="$WORK/profiles/$NEW_PERSONA"
        rc=0
        if [ -f "$newRoot/config.yaml" ]; then
          step "update the existing NEW persona '$NEW_PERSONA' on the dirty home (already installed)"
          if hermes profile update "$NEW_PERSONA" --yes; then ok "updated new persona '$NEW_PERSONA'"; else fail "new persona '$NEW_PERSONA' update failed on the dirty home"; rc=1; fi
        else
          step "install a NEW persona '$NEW_PERSONA' on the dirty home (must not clobber '$TEMPLATE')"
          if hermes profile install "$newDist" --name "$NEW_PERSONA" --yes; then ok "installed new persona '$NEW_PERSONA'"; else fail "new persona '$NEW_PERSONA' install failed on the dirty home"; rc=1; fi
        fi
        if [ "$rc" -eq 0 ]; then
          invoke_assertions "$NEW_PERSONA" "$newRoot" "$newDist"
          [ -f "$profRoot/config.yaml" ] && ok "existing profile '$TEMPLATE' still present after '$NEW_PERSONA'" || fail "handling '$NEW_PERSONA' clobbered the existing '$TEMPLATE' profile"
        fi
      fi
    fi
    step "SUMMARY (dirty)"
    if [ "$FAILURES" -eq 0 ]; then echo; echo "  ${GREEN}PASS — dirty-home update/install checks passed.${RST}"; else echo; echo "  ${RED}$FAILURES CHECK(S) FAILED — see the [FAIL] lines above.${RST}"; fi
    ;;

  *) echo "unknown action '$ACTION' (build|reset|dirty|status|clean)" >&2; exit 2 ;;
esac

[ "$FAILURES" -eq 0 ] || exit 1
