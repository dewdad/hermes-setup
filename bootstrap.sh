#!/usr/bin/env bash
# =============================================================================
# Reproducible Hermes Agent setup (Linux / macOS / WSL2 / Termux)
#
# Copies managed config.yaml, SOUL.md and custom skills from this repo into your
# Hermes home. Safe on a fresh install or to extend an existing one.
#
# Merge semantics (never destructive to your data):
#   * config.yaml -> existing backed up to config.yaml.bak.<timestamp>, then replaced
#   * SOUL.md     -> only written if missing, still default (<!-- UNCONFIGURED -->),
#                    or --force is given; a customized SOUL.md is preserved
#   * skills/     -> managed skills merged in; your other skills are untouched
#   * .env        -> created from .env.example ONLY if missing; an existing .env
#                    is never overwritten (missing keys are reported instead)
# A full backup (hermes backup, or a tar fallback) runs first unless --skip-backup.
#
# Usage:
#   ./bootstrap.sh [--dry-run] [--force] [--skip-backup] [--skip-skills]
#                  [--hermes-home PATH]
# =============================================================================
set -euo pipefail

DRY_RUN=0; FORCE=0; SKIP_BACKUP=0; SKIP_SKILLS=0; HERMES_HOME_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)      DRY_RUN=1 ;;
    --force)        FORCE=1 ;;
    --skip-backup)  SKIP_BACKUP=1 ;;
    --skip-skills)  SKIP_SKILLS=1 ;;
    --hermes-home)  HERMES_HOME_ARG="${2:-}"; shift ;;
    -h|--help)      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_HOME="$REPO_ROOT/hermes-home"
ENV_EXAMPLE="$REPO_ROOT/.env.example"

# ----- colors / logging ------------------------------------------------------
if [ -t 1 ]; then C='\033[36m'; G='\033[32m'; Y='\033[33m'; D='\033[90m'; N='\033[0m'; else C=''; G=''; Y=''; D=''; N=''; fi
step() { printf "\n${C}==> %s${N}\n" "$1"; }
info() { printf "    %s\n" "$1"; }
ok()   { printf "${G}  + %s${N}\n" "$1"; }
warn() { printf "${Y}  ! %s${N}\n" "$1"; }
skip() { printf "${D}  - %s${N}\n" "$1"; }

HERMES_CLI="$(command -v hermes || true)"

resolve_home() {
  if [ -n "$HERMES_HOME_ARG" ]; then echo "$HERMES_HOME_ARG"; return; fi
  if [ -n "${HERMES_HOME:-}" ]; then echo "$HERMES_HOME"; return; fi
  if [ -n "$HERMES_CLI" ]; then
    local cfg; cfg="$("$HERMES_CLI" config path 2>/dev/null | head -n1 || true)"
    if [ -n "$cfg" ]; then dirname "$cfg"; return; fi
  fi
  if [ -d "$HOME/.hermes" ]; then echo "$HOME/.hermes"; return; fi
  if [ -n "${LOCALAPPDATA:-}" ] && [ -d "$LOCALAPPDATA/hermes" ]; then echo "$LOCALAPPDATA/hermes"; return; fi
  echo "$HOME/.hermes"   # sensible default for the shell installer
}

run() { if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] $*"; else eval "$@"; fi; }

env_keys() { # $1=file -> prints KEY names
  [ -f "$1" ] || return 0
  grep -E '^[[:space:]]*[^#[:space:]][^=]*=' "$1" | sed -E 's/^[[:space:]]*([^=]+)=.*/\1/' | sed -E 's/[[:space:]]+$//'
}

printf "${N}Hermes Agent — reproducible bootstrap\n"
[ "$DRY_RUN" -eq 1 ] && warn "DRY RUN — no changes will be written."
[ -d "$SOURCE_HOME" ] || { echo "Source '$SOURCE_HOME' not found. Run from inside the repo." >&2; exit 1; }

TARGET="$(resolve_home)"
step "Target Hermes home"; info "$TARGET"
if [ -n "$HERMES_CLI" ]; then info "hermes CLI: $HERMES_CLI"; else warn "hermes CLI not found on PATH (files will be staged for when it is)."; fi
run "mkdir -p \"$TARGET\""
# Pin every subsequent CLI call (backup, verify) to the home we're configuring,
# so a custom --hermes-home doesn't back up / check the default home by mistake.
export HERMES_HOME="$TARGET"

# ----- 1. backup -------------------------------------------------------------
step "Safety backup"
if [ "$SKIP_BACKUP" -eq 1 ]; then
  skip "skipped (--skip-backup)"
elif [ ! -f "$TARGET/config.yaml" ]; then
  skip "nothing to back up (fresh install)"
elif [ "$DRY_RUN" -eq 1 ]; then
  info "[dry-run] would run 'hermes backup' (or tar $TARGET)"
else
  if [ -n "$HERMES_CLI" ] && "$HERMES_CLI" backup >/dev/null 2>&1; then
    ok "hermes backup created"
  else
    STAMP="$(date +%Y%m%d_%H%M%S)"; TARBALL="${TMPDIR:-/tmp}/hermes-home-backup-$STAMP.tar.gz"
    tar -czf "$TARBALL" -C "$TARGET" . && ok "tar backup: $TARBALL"
  fi
fi

# ----- 2. config.yaml --------------------------------------------------------
step "config.yaml"
if [ -f "$TARGET/config.yaml" ]; then
  BAK="$TARGET/config.yaml.bak.$(date +%Y%m%d_%H%M%S)"
  run "cp -p \"$TARGET/config.yaml\" \"$BAK\"" && [ "$DRY_RUN" -eq 0 ] && ok "backed up existing -> $(basename "$BAK")" || true
fi
run "cp -f \"$SOURCE_HOME/config.yaml\" \"$TARGET/config.yaml\"" && [ "$DRY_RUN" -eq 0 ] && ok "wrote config.yaml" || true

# ----- 3. SOUL.md ------------------------------------------------------------
step "SOUL.md"
WRITE_SOUL=1
if [ -f "$TARGET/SOUL.md" ] && [ "$FORCE" -eq 0 ]; then
  if ! grep -qiE '<!--[[:space:]]*UNCONFIGURED[[:space:]]*-->' "$TARGET/SOUL.md"; then WRITE_SOUL=0; fi
fi
if [ "$WRITE_SOUL" -eq 1 ]; then
  run "cp -f \"$SOURCE_HOME/SOUL.md\" \"$TARGET/SOUL.md\"" && [ "$DRY_RUN" -eq 0 ] && ok "wrote SOUL.md" || true
else
  skip "existing SOUL.md is customized — preserved (use --force to overwrite)"
fi

# ----- 4. skills -------------------------------------------------------------
step "Custom skills"
if [ "$SKIP_SKILLS" -eq 1 ]; then
  skip "skipped (--skip-skills)"
else
  run "mkdir -p \"$TARGET/skills\""
  while IFS= read -r skillmd; do
    sd="$(dirname "$skillmd")"
    rel="${sd#"$SOURCE_HOME/skills/"}"
    dest="$TARGET/skills/$rel"
    if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] merge skill -> $rel"; continue; fi
    mkdir -p "$(dirname "$dest")"
    cp -Rf "$sd" "$(dirname "$dest")/"
    ok "skill: $rel"
  done < <(find "$SOURCE_HOME/skills" -name SKILL.md -type f)
fi

# ----- 5. .env ---------------------------------------------------------------
step ".env"
if [ ! -f "$TARGET/.env" ]; then
  run "cp -f \"$ENV_EXAMPLE\" \"$TARGET/.env\"" && [ "$DRY_RUN" -eq 0 ] && ok "created .env from template — EDIT IT to add your keys" || true
else
  missing=""
  for k in $(env_keys "$ENV_EXAMPLE"); do
    if ! env_keys "$TARGET/.env" | grep -qx "$k"; then missing="$missing $k"; fi
  done
  if [ -n "$missing" ]; then
    warn "existing .env preserved. Keys in template not present in your .env:"
    for k in $missing; do info "$k"; done
  else
    ok "existing .env preserved; all template keys present"
  fi
fi

# ----- 6. verify -------------------------------------------------------------
step "Verify"
if [ "$DRY_RUN" -eq 1 ]; then
  info "[dry-run] would run: hermes config check ; hermes doctor"
elif [ -n "$HERMES_CLI" ]; then
  "$HERMES_CLI" config check || warn "config check reported issues (see above)."
  info "Run 'hermes doctor' for a full health check."
else
  warn "hermes CLI not found — install Hermes, then run 'hermes config check' && 'hermes doctor'."
fi

printf "\n${G}Done.${N}\n"
info "Next: edit '$TARGET/.env' with your API keys, then run 'hermes'."
