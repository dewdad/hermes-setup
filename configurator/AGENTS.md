# configurator/ — DOX child

## Purpose

Own the template compiler: resolve layered `template.yaml` inputs into native Hermes profile
distributions under `dist/<persona>/`. Pure library + CLI; no installer behavior, no Hermes calls.

## Ownership

- All Python under `configurator/` and its CLI entrypoint `python -m configurator`.
- Nothing under `templates/`, `dist/`, `locks/`, `tests/`, or `skills-vendor/`.

## Local Contracts

- **Runtime dependencies**: stdlib + PyYAML **only**. No other runtime dep may be added — the
  package must run anywhere Hermes runs.
- **Secret hygiene (HARD, inherited from root)** — `secretscan.py` FAILS the build on any
  key-shaped literal in emitted `config.yaml` / `mcp` / SOUL / bundles. Secrets appear only as
  `${VAR}` / `key_env`.
- **`ingest.py` scope** — reads the live `config.yaml` **only**. It MUST NOT read `.env`,
  `auth.json`, `models.json`, `desktop.json`, `state.db*`, `sessions/`, `memories/`, or any other
  desktop state.
- **Deterministic emit** — YAML/JSON writers sort keys and use stable list ordering so `dist/`
  diffs cleanly in git across machines.
- **Config schema** — compiler injects `_config_version: 33`; unknown keys are warned, not failed.
- **Per-module responsibility** (do not blur boundaries):
  - `model.py` — schema types (frozen slotted dataclasses / `Literal` variants).
  - `parse.py` — validate raw YAML → `Template`.
  - `merge.py` — inheritance + deep-merge (`!remove`, include/exclude, base→locale→persona).
  - `profile_merge.py` — the APPLY-time `config.yaml` merge for the EXTEND path (distinct from
    `merge.py`'s compile-time child-over-parent): EXISTING-preserving additive merge — adds new
    keys/sub-keys, keeps existing scalar values on conflict (reported for the installer to prompt),
    unions known lists (`skills.external_dirs` by string, `fallback_providers`/`auxiliary.vision.
    fallback_chain` by `(provider,model)`), reconciles `_config_version`, and detects a pristine
    target by exact normalized-hash equality (provenance / incoming / `dist/general`) — never fuzzy.
    Pure: no Hermes calls, never reads `.env`; the installer scripts own prompting/`.env`/provenance.
  - `soul.py` — fragment compose + 20000-char cap.
  - `manifest.py` — flat `distribution.yaml` (owns `meta-skills`, never `skills`; owns
    `setup.steps.{sh,ps1}` when `setup_steps[]` present) + `.env.EXAMPLE`.
  - `readme.py` — per-distribution README (includes the `hermes skills install …` post-install block).
  - `setup_skill.py` — build the generated `finish-setup` meta-skill body (the reference-only
    carve-out): tiered skill list, provider-key guidance, `setup_steps[]` local-tools block,
    `discovery[]` block. Pure function. When the template's `portal_auth` is set (paid
    `base/general-pro`), section 1 renders the `hermes setup --portal` OAuth login instead of the
    provider-key walkthrough.
  - `setup_scripts.py` — build the generated per-platform `setup.steps.{sh,ps1}` from `setup_steps[]`
    (local-tool provisioning, e.g. RTK). Pure functions; POSIX/PowerShell single-quote escaping;
    each step is idempotent (check-gated) + failure-tolerant. Emitted text is secret-scanned.
  - `emit.py` — orchestrate emission of one `dist/<name>/`; writes the `finish-setup` meta-skill to
    `meta-skills/finish-setup/SKILL.md` (secret-scanned first) and prepends TWO `skills.external_dirs`
    entries to `config.yaml` so Hermes registers `/finish-setup` on every surface: the profile-relative
    `meta-skills` dir FIRST (authoritative under `hermes -p <name>`), then the stable `~`-anchored
    fallback `~/.hermes-setup/meta-skills` (resolves regardless of `HERMES_HOME`; the apply flow copies
    the skill there). Also secret-scans the generated `skills.sh.json` / `skills.install.json` before
    writing them, and writes `setup.steps.{sh,ps1}` (secret-scanned) iff the template declares
    `setup_steps[]`.
  - `secretscan.py` — secret-literal gate (fails build; also scans the generated meta-skill text).
  - `loader.py` — discover templates + resolve `extends` chain.
  - `sources.py` + `fetch.py` + `locks.py` — vendoring + lockfile IO.
  - `ingest.py` — drift detection from live `config.yaml`.
  - `catalog.py` — build the repo-root `profiles.json` catalogue: every installable profile's
    name / description / version / `apply_modes` / `dist/<name>` path + ready-to-run
    `local_posix_command` / `local_windows_command` / `standalone_*_command` (all routed through the
    bundled `install.sh` / `install.ps1` — never a bare `hermes profile install`, so the
    `~/.hermes-setup/meta-skills` fallback + new-vs-extend choice are not bypassed), plus an
    `agent_instructions` recipe. `apply_modes` is `["pro"]` for a
    `portal_auth` base and `["free","pro"]` otherwise (free default, paid Portal via the `--pro` /
    `--portal` apply flag). Pure function; embeds NO repo URL (deterministic across forks).
  - `verify.py` — aggregate quality gates (also secret-scans the repo-root `profiles.json`).
  - `compile.py` — CLI (`compile`, `verify`, `update-locks`, `ingest`, `merge-config`); on every
    non-dry-run compile writes the repo-root `profiles.json` from the FULL registry (secret-scanned
    first), so the catalogue never drifts from `dist/` even after a single-template compile.
    `merge-config {plan,apply-decisions}` is the pure `config.yaml` merge the `bootstrap.*` EXTEND
    flow shells out to (file IO here; the engine lives in `profile_merge.py`).

## Work Guidance

- 250 pure-LOC ceiling per module; split before exceeding.
- TDD with stdlib `unittest` — add or update a `tests/test_*.py` before touching behavior.
- Frozen slotted dataclasses for schema types; `match` + `assert_never` for variant exhaustion.
- No `Any`, no `cast`, no `# type: ignore`, no broad `except Exception:`.
- Parse-don't-validate: convert raw dicts into typed models at the boundary, then work in types.
- Any new emitted field must be sorted-stable and covered by a secret-scan test.

## Verification

- `python -m unittest discover -s tests -p "test_*.py"` — all tests pass.
- `python -m configurator verify` — schema, merge, SOUL cap, secret gate, and lock drift clean.
- `python -m configurator compile --all` then `git diff --exit-code dist/` — no incidental diff.

## Child DOX Index

None.
