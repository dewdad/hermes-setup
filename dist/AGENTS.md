# dist/ — DOX child

## Purpose

Own the generated Hermes profile distributions — one directory per persona
(`dist/<name>/`) — that `hermes profile install` / `update` consume directly.
This tree is a *build output*, not a source of truth.

## Ownership

- Every `dist/<name>/` directory and its contents.
- Nothing under `templates/`, `configurator/`, `locks/`, `tests/`, or `skills-vendor/`.

## Local Contracts

- **Never hand-edit.** Any change must come from `python -m configurator compile <name>`
  (or `python -m configurator compile --all`). Edits made here are overwritten by the next
  compile and are treated as bugs in the template, not fixes in `dist/`.
- **Committed, but secret-free.** The tree is checked into git so `dist/` diffs review-cleanly,
  but it MUST contain no literal secrets — `secretscan.py` fails the build otherwise.
- **Reference-only — no `skills/` content.** Personas author no skills; distributions ship NO
  `skills/` directory. Skills are *referenced* (bucket 3) and auto-installed on apply via
  `hermes skills install`. `distribution_owned` never lists `skills`. **Why this matters (proven):**
  Hermes v0.18.x `profile_distribution.py` copies distribution payload with a **denylist**
  (`USER_OWNED_EXCLUDE`), NOT the `distribution_owned` allowlist (which is advisory/dead code there).
  `skills` is not in the denylist, so shipping a `skills/` dir makes `hermes profile update`
  `rmtree()`+replace the profile's entire `skills/` — **wiping the user's installed skills**.
- **The ONE generated skill lives under `meta-skills/`, never `skills/`.** The compiler emits exactly
  one authored skill — `meta-skills/finish-setup/SKILL.md` (the reference-only carve-out; registered
  as `/finish-setup`). It sits in a top-level `meta-skills/` dir (distribution-owned, refreshed on
  update) referenced via a profile-relative `skills.external_dirs` entry in `config.yaml`. Because it
  is NOT under `skills/`, `hermes profile update` refreshes it without ever touching user skills.
  `config.yaml`'s `skills.external_dirs` lists TWO discovery entries so `/finish-setup` registers on
  every surface: `meta-skills` FIRST (profile-relative — authoritative under `hermes -p <name>`), then
  the stable `~`-anchored fallback `~/.hermes-setup/meta-skills`. Hermes resolves a relative entry
  against `HERMES_HOME` (the profile dir only for `hermes -p <name>`; the root/default home on Desktop,
  the gateway, and subprocesses), so the relative entry alone would leave `/finish-setup` invisible
  there; the fallback `expanduser`s to an absolute path that resolves regardless of `HERMES_HOME`. The
  apply flow (`install.*` / `bootstrap.*`) copies the meta-skill into that shared dir (and `bootstrap.*`
  also copies `meta-skills/` into the target home so the relative entry resolves for the default
  profile). The shared copy is "last-installed-persona wins" and not auto-refreshed by `profile
  update`.
- **Distribution layout** (per persona) — the compiler emits:
  - `distribution.yaml` — flat Hermes distribution manifest.
  - `config.yaml` — Hermes config fragment (uses `${VAR}` / `key_env`; never literal secrets;
    no `_config_version` from templates — compiler stamps `33`). The paid `dist/general-pro/` variant
    sets `model.provider: nous` + the four Tool Gateway tools `use_gateway: true` (the only base
    allowed to); its credential is the Portal OAuth token, not a key, so it declares no `env`.
  - `SOUL.md` — composed SOUL (≤ 20000 chars).
  - `cron/` — scheduled task definitions (script jobs like `open-skills-sync`, and agent-prompt
    jobs like the personal-assistant `morning-brief` / `followup-sweep`, all shipped `enabled:false`).
  - `skill-bundles/` — declared bundles (skill *names* only, no content).
  - `skills.install.json` — machine-readable referenced-skill list the apply flow auto-installs
    (present iff the persona declares `post_install[]`).
  - `skills.sh.json` — Skills-Hub category-label manifest (schema `skills.sh/schemas/skills.sh.schema.json`):
    its `groupings` become the labels a published persona tap presents. Built by
    `manifest.build_skills_sh` from the persona's vendored skill categories + declared bundles;
    present iff the persona declares vendored `skills.include[]` OR `bundles[]` (so it is ABSENT for
    the reference-only free personas that vendor nothing). Distinct from `skills.install.json`
    (which lists post-install skill ids the apply flow installs); this one only carries hub labels,
    installs nothing. Distribution-owned and secret-scanned at emit (like every generated manifest)
    and again by the `dist/`-wide `verify` gate.
  - `setup.steps.sh` / `setup.steps.ps1` — generated per-platform local-tool provisioning scripts
    (present iff the persona declares `setup_steps[]`); the apply flow runs the matching one
    (gated, idempotent, failure-tolerant). Generated infrastructure like the meta-skill —
    distribution-owned, secret-scanned, never hand-edited. `base/general` ships the RTK step and a
    Tier-0 `voice-deps` step (ffmpeg + faster-whisper/piper-tts for free voice).
  - `meta-skills/finish-setup/SKILL.md` — the one generated skill (the carve-out), always emitted;
    registered as `/finish-setup`. Distribution-owned; never under `skills/`.
  - `.env.EXAMPLE` — every env var the config references, no secrets (absent when the template
    declares no `env`, e.g. the OAuth-only `general-pro` base).
  - `.gitignore` — keeps runtime state out of git.
  - `README.md` — per-distribution readme with the auto-installed referenced-skill block.
  - `.no-bundled-skills` — present iff the persona sets `skills.bundled: none`.
- **Determinism** — emitted files use sorted keys / stable list ordering; a re-compile on
  another machine must produce byte-identical output (given the same locks).

## Work Guidance

- To change `dist/<name>/`, edit the corresponding `templates/<name>/template.yaml` (and any
  parent) and re-run `python -m configurator compile <name>`.
- To refresh every distribution after a compiler or template change, run
  `python -m configurator compile --all` and commit the resulting diff in one atomic commit.
- Never resolve a merge conflict inside `dist/` by hand — re-run `compile --all`.

## Verification

- `python -m configurator compile --all` completes without error.
- `git diff --exit-code dist/` is clean immediately after `compile --all`.
- `python -m configurator verify` — passes the secret gate and the
  `redistributable: false` gate for every emitted skill.

## Child DOX Index

None.
