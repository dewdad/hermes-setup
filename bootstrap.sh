#!/usr/bin/env bash
# Apply a compiled Hermes persona distribution (dist/<template>) to your DEFAULT Hermes profile.
# Safe on a fresh install or to extend an existing one. For a *named* profile instead, use
#   hermes profile install ./dist/<name> --name <profile>
#
# Merge semantics (never destructive to your data):
#   config.yaml   -> existing backed up to config.yaml.bak.<ts>, then replaced
#   SOUL.md       -> only written if missing / still the default marker / --force
#   skills/, skill-bundles/, cron/, mcp.json -> merged/copied if the distribution ships them
#   .env          -> created from the distribution's .env.EXAMPLE ONLY if missing
# A backup (hermes backup, or a tar fallback) runs first unless --skip-backup.
# Best-effort: clones/pulls the optional shared skills checkout at ~/open-skills.
set -euo pipefail

TEMPLATE="base/general"
HERMES_HOME_ARG=""
DRY_RUN=0; FORCE=0; SKIP_BACKUP=0; SKIP_SKILLS=0; SKIP_OPEN_SKILLS=0; SKIP_SKILLS_INSTALL=0; ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--template REF|NAME] [--hermes-home PATH]
                      [--dry-run] [--force] [--skip-backup] [--skip-skills] [--skip-open-skills]
                      [--skip-skills-install] [--yes]
  --template            Distribution to apply (ref "persona/developer" or name "developer"). Default base/general.
  --skip-skills-install Do not auto-install the distribution's referenced skills.
  --yes                 Auto-confirm the referenced-skill install prompt (non-interactive).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --template) TEMPLATE="$2"; shift 2;;
    --hermes-home) HERMES_HOME_ARG="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    --force) FORCE=1; shift;;
    --skip-backup) SKIP_BACKUP=1; shift;;
    --skip-skills) SKIP_SKILLS=1; shift;;
    --skip-open-skills) SKIP_OPEN_SKILLS=1; shift;;
    --skip-skills-install) SKIP_SKILLS_INSTALL=1; shift;;
    --yes) ASSUME_YES=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "unknown option: $1" >&2; usage; exit 2;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_NAME="${TEMPLATE##*/}"
SOURCE_HOME="$REPO_ROOT/dist/$TEMPLATE_NAME"
ENV_EXAMPLE="$SOURCE_HOME/.env.EXAMPLE"

step() { printf '\n==> %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }
ok()   { printf '  + %s\n' "$1"; }
warn() { printf '  ! %s\n' "$1"; }
skip() { printf '  - %s\n' "$1"; }

HERMES_CLI="$(command -v hermes || true)"

resolve_home() {
  if [ -n "$HERMES_HOME_ARG" ]; then echo "$HERMES_HOME_ARG"; return; fi
  if [ -n "${HERMES_HOME:-}" ]; then echo "$HERMES_HOME"; return; fi
  if [ -n "$HERMES_CLI" ]; then
    local p; p="$("$HERMES_CLI" config path 2>/dev/null | head -n1 || true)"
    if [ -n "$p" ]; then dirname "$p"; return; fi
  fi
  echo "$HOME/.hermes"
}

env_keys() { [ -f "$1" ] && grep -E '^[[:space:]]*[^#[:space:]][^=]*=' "$1" | sed -E 's/[[:space:]]*=.*//' || true; }

copy_tree() { # src dst label
  local src="$1" dst="$2" label="$3"
  [ -d "$src" ] || return 0
  while IFS= read -r -d '' f; do
    local rel="${f#"$src"/}" dest="$dst/${f#"$src"/}"
    if [ "$DRY_RUN" = 1 ]; then info "[dry-run] $label -> $rel"; continue; fi
    mkdir -p "$(dirname "$dest")"; cp -f "$f" "$dest"; ok "$label: $rel"
  done < <(find "$src" -type f -print0)
}

echo "Hermes Agent — apply distribution '$TEMPLATE_NAME'"
[ "$DRY_RUN" = 1 ] && warn "DRY RUN — no changes will be written."
[ -d "$SOURCE_HOME" ] || { echo "Distribution '$SOURCE_HOME' not found. Compile it: python -m configurator compile $TEMPLATE" >&2; exit 1; }

TARGET="$(resolve_home)"
step "Target Hermes home"; info "$TARGET"
[ -n "$HERMES_CLI" ] && info "hermes CLI: $HERMES_CLI" || warn "hermes CLI not found on PATH."
[ "$DRY_RUN" = 1 ] || mkdir -p "$TARGET"
export HERMES_HOME="$TARGET"

step "Safety backup"
if [ "$SKIP_BACKUP" = 1 ]; then skip "skipped (--skip-backup)"
elif [ ! -f "$TARGET/config.yaml" ]; then skip "nothing to back up (fresh install)"
elif [ "$DRY_RUN" = 1 ]; then info "[dry-run] would run 'hermes backup' (or tar $TARGET)"
else
  done_bk=0
  if [ -n "$HERMES_CLI" ]; then "$HERMES_CLI" backup >/dev/null 2>&1 && { ok "hermes backup created"; done_bk=1; } || warn "hermes backup failed"; fi
  if [ "$done_bk" = 0 ]; then tarf="$(mktemp -t hermes-home-backup.XXXXXX).tar.gz"; tar -czf "$tarf" -C "$TARGET" . && ok "tar backup: $tarf"; fi
fi

step "config.yaml"
if [ -f "$TARGET/config.yaml" ]; then
  bak="$TARGET/config.yaml.bak.$(date +%Y%m%d_%H%M%S)"
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] backup existing -> $bak; then replace"; else cp -f "$TARGET/config.yaml" "$bak"; ok "backed up existing -> $(basename "$bak")"; fi
fi
if [ "$DRY_RUN" = 1 ]; then info "[dry-run] copy config.yaml"; else cp -f "$SOURCE_HOME/config.yaml" "$TARGET/config.yaml"; ok "wrote config.yaml"; fi

step "SOUL.md"
if [ -f "$SOURCE_HOME/SOUL.md" ]; then
  write_soul=1
  if [ -f "$TARGET/SOUL.md" ] && [ "$FORCE" = 0 ]; then grep -q '<!--\s*UNCONFIGURED\s*-->' "$TARGET/SOUL.md" || write_soul=0; fi
  if [ "$write_soul" = 1 ]; then
    if [ "$DRY_RUN" = 1 ]; then info "[dry-run] write SOUL.md"; else cp -f "$SOURCE_HOME/SOUL.md" "$TARGET/SOUL.md"; ok "wrote SOUL.md"; fi
  else skip "existing SOUL.md is customized — preserved (use --force to overwrite)"; fi
else skip "distribution ships no SOUL.md"; fi

step "Distribution assets (skills / skill-bundles / cron / mcp.json)"
if [ "$SKIP_SKILLS" = 1 ]; then skip "skills skipped (--skip-skills)"; else copy_tree "$SOURCE_HOME/skills" "$TARGET/skills" "skill"; fi
copy_tree "$SOURCE_HOME/skill-bundles" "$TARGET/skill-bundles" "bundle"
copy_tree "$SOURCE_HOME/cron" "$TARGET/cron" "cron"
if [ -f "$SOURCE_HOME/mcp.json" ]; then
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] copy mcp.json"; else cp -f "$SOURCE_HOME/mcp.json" "$TARGET/mcp.json"; ok "wrote mcp.json"; fi
fi

step "Optional shared skills (~/open-skills)"
if [ "$SKIP_OPEN_SKILLS" = 1 ]; then skip "skipped (--skip-open-skills)"
elif [ "$DRY_RUN" = 1 ]; then info "[dry-run] clone/pull https://github.com/dewdad/open-skills -> ~/open-skills"
elif ! command -v git >/dev/null 2>&1; then warn "git not found — skipping (a missing ~/open-skills is tolerated)"
else
  os_dir="$HOME/open-skills"
  if [ -d "$os_dir/.git" ]; then git -C "$os_dir" pull --ff-only >/dev/null 2>&1 && ok "pulled ~/open-skills" || warn "open-skills pull failed (tolerated)"
  else git clone --depth 1 https://github.com/dewdad/open-skills "$os_dir" >/dev/null 2>&1 && ok "cloned ~/open-skills" || warn "open-skills clone failed (tolerated)"; fi
fi

step ".env"
DST_ENV="$TARGET/.env"
if [ ! -f "$ENV_EXAMPLE" ]; then skip "distribution ships no .env.EXAMPLE (no keys required)"
elif [ ! -f "$DST_ENV" ]; then
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] create .env from .env.EXAMPLE"; else cp -f "$ENV_EXAMPLE" "$DST_ENV"; ok "created .env from template — EDIT IT to add your keys"; fi
else
  missing="$(comm -23 <(env_keys "$ENV_EXAMPLE" | sort -u) <(env_keys "$DST_ENV" | sort -u) || true)"
  if [ -n "$missing" ]; then warn "existing .env preserved. Template keys not present:"; echo "$missing" | sed 's/^/    /'; else ok "existing .env preserved; all template keys present"; fi
fi

# Parse skills.install.json (deterministic sorted keys: id, note, tap) without a jq dependency.
# Emits one "install <id>" or "tap <id>" line per referenced skill.
parse_installs() {
  local id=""
  while IFS= read -r line; do
    case "$line" in
      *'"id":'*) id="${line#*: \"}"; id="${id%\"*}";;
      *'"tap": true'*)  [ -n "$id" ] && echo "tap $id";;
      *'"tap": false'*) [ -n "$id" ] && echo "install $id";;
    esac
  done < "$1"
}

step "Referenced skills (auto-install)"
INSTALL_MANIFEST="$SOURCE_HOME/skills.install.json"
if [ "$SKIP_SKILLS_INSTALL" = 1 ]; then skip "skipped (--skip-skills-install)"
elif [ ! -f "$INSTALL_MANIFEST" ]; then skip "distribution references no skills"
elif [ -z "$HERMES_CLI" ]; then warn "hermes CLI not found — skipping skill install (run the README block later)"
else
  mapfile -t INSTALLS < <(parse_installs "$INSTALL_MANIFEST") || INSTALLS=()
  if [ "${#INSTALLS[@]}" = 0 ]; then skip "no referenced skills listed"
  else
    info "references ${#INSTALLS[@]} skill(s):"; printf '      %s\n' "${INSTALLS[@]}"
    proceed=1
    if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would run 'hermes skills install/tap add' for each (Hermes security-scans each)"; proceed=0
    elif [ "$ASSUME_YES" = 0 ]; then
      printf '    Install these referenced skills now (Hermes will security-scan each)? [y/N] '
      read -r ans; case "$ans" in y|Y|yes|YES) ;; *) proceed=0; skip "declined — install later via the README block";; esac
    fi
    if [ "$proceed" = 1 ]; then
      for entry in "${INSTALLS[@]}"; do
        kind="${entry%% *}"; sid="${entry#* }"
        if [ "$kind" = tap ]; then
          "$HERMES_CLI" skills tap add "$sid" >/dev/null 2>&1 && ok "tap add $sid" || warn "tap add $sid failed (tolerated)"
        else
          "$HERMES_CLI" skills install "$sid" --yes >/dev/null 2>&1 && ok "installed $sid" || warn "install $sid failed (tolerated)"
        fi
      done
    fi
  fi
fi

step "Verify"
if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would run: hermes config check"
elif [ -n "$HERMES_CLI" ]; then "$HERMES_CLI" config check || warn "config check reported issues (see above)."; info "Run 'hermes doctor' for a full health check."
else warn "hermes CLI not found — run 'hermes config check' after installing Hermes."; fi

printf '\nDone.\n'
info "Applied '$TEMPLATE_NAME'. Next: edit '$TARGET/.env' with your API keys, then run 'hermes'."
