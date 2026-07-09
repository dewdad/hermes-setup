# templates/ — DOX child

## Purpose

Own `template.yaml` authoring: the layered declarative inputs (`base → locale → persona`, single
inheritance) the `configurator/` compiler resolves into native Hermes profile distributions under
`dist/<persona>/`. Templates never emit runtime state; they describe *intent*.

## Ownership

- `templates/<name>/template.yaml` and its sibling `soul/*.md` fragments.
- Nothing under `dist/`, `configurator/`, `locks/`, or `tests/`.
- **Reference-only (HARD)** — this repo authors NO skill content. Templates only *reference*
  verified-real skill ids from trusted registries. There is no in-repo `skills-vendor/` of
  hand-written skills; every referenced id must be confirmed with `hermes skills search` /
  `hermes skills inspect` before it ships. No fabricated/placeholder ids.

## Local Contracts

- **`template.yaml` schema** (fields):
  - `name` (required), `kind` ∈ {`base`, `locale`, `persona`}.
  - `extends`: single inheritance. `base` MUST NOT extend; `locale` and `persona` MUST extend.
  - `distribution`: `{description, version, license, author}`.
  - `config`: deep-merged Hermes config fragment. **Never** set `_config_version` — the compiler
    injects `33`. Custom providers use `key_env` (not `api_key_env`).
  - `env[]`: each `{name, description, required (default false), default}`. **All** provider and
    fallback keys are `required: false` so any single key yields a working agent.
  - `soul.fragments[]`: ordered list. Child fragments append; a child fragment with the same
    filename as an ancestor's overrides in place. Fragments resolve at `<template-dir>/soul/<file>`.
    Composed SOUL MUST stay ≤ 20000 chars.
  - `skills`: `{bundled: none|all|[allowlist], external_dirs[], include[SkillRef], exclude[names]}`.
    Under the reference-only model `include[]` is normally empty (nothing is vendored); it exists
    only for the retained github/url/well-known fetch capability if offline pinning is ever needed.
  - `bundles[]`: `{name, skills, description, instruction}`. `skills` names must match the local
    names the referenced skills install as (e.g. `docx`, not a fabricated id).
  - `mcp`: object (deep-merged).
  - `cron[]`: list of scheduled tasks.
  - `post_install[]`: `{id, note, tap, tier}` — the primary skill-sourcing surface. Emitted to the
    distribution README **and** to a machine-readable `skills.install.json`; the apply flow
    (`bootstrap.ps1`/`bootstrap.sh`) auto-runs `hermes skills install <id>` / `tap add <id>` from it.
    `tier` (int, default 0) splits capabilities by auth friction: **0** = free-to-run, on the
    critical path (a working agent depends only on these; browser/web keyless, free chat needs one
    free-tier key or a Nous sign-in); **1** = guided opt-in (build/OAuth/app), never required. `/finish-setup` groups the list by tier. Tier-0 open-skills flagship ids
    (`skills-sh/dewdad/open-skills/*`) and IL ids (`skills-sh/skills-il/<category-repo>/<skill>`)
    live here; payment-gateway / bank-connector (`tax-and-finance`) IL skills are excluded.
  - `discovery[]`: each `{label, url, note}` — "discover more skills" catalogue links (URLs only,
    no secrets) rendered into `/finish-setup`. `base` carries general entries (skills.sh); `locale/il`
    appends IL catalogues (agentskills.co.il, Claude-Israel). Merged base→locale by set-union on url.
  - `setup_steps[]`: each `{id, label, note, tier, posix_check, posix_run, windows_check,
    windows_run}` — local-tool provisioning that is **not** a `hermes skills install` (e.g. RTK's
    binary + `rtk init --agent hermes`). The compiler generates per-platform `setup.steps.{sh,ps1}`
    from these; the apply flow (`bootstrap.*`) runs the matching one (gated, idempotent — the
    `*_run` command runs only when the `*_check` reports the tool not yet set up — and
    failure-tolerant), and `/finish-setup` shows the manual commands. `tier` mirrors `post_install`
    (0 = free/on the apply path; 1 = guided opt-in). Commands carry no secrets (secret-scanned on
    emit). `base/general` ships the RTK step and a Tier-0 `voice-deps` step (ffmpeg +
    faster-whisper/piper-tts, enabling free local STT + keyless Edge TTS by default); `locale/il`
    overrides the voice config to Hebrew (ivrit.ai STT model + a `he-IL` Edge voice).
  - `portal_auth` (bool, default `false`) — marks a base as **paid Nous Portal** (`base/general-pro`
    only). When true, the generated `/finish-setup` renders the `hermes setup --portal` OAuth login
    step instead of the provider-key walkthrough, because the credential is the Portal OAuth token
    (`~/.hermes/auth.json`), not a `${VAR}` key. A portal base therefore carries `env: []` (an empty
    env list is valid). It merges by OR (once any layer sets it, it stays true), so a persona that
    `extends: base/general-pro` inherits it.
- **The two base rails** (root contract) — `base/general` is the free default; `base/general-pro` is
  the paid Portal sibling. `general-pro` intentionally sets `use_gateway: true` for
  `web`/`browser`/`image_gen`/`tts` and `model.provider: nous` — the one base allowed to. Personas
  are **never** re-parented onto it; the free↔paid choice is made at apply time (`bootstrap --portal`
  / `install --pro`), which splices the base-layer keys (`model.{provider,default,base_url,max_tokens}`,
  the four gateway tools, `delegation.{provider,model}`, `auxiliary.vision.*`) from
  `dist/general-pro/config.yaml` onto the target profile via `hermes config set`. Keep that
  base-layer key set in sync between the template and the apply scripts.
- **Merge semantics**:
  - Maps deep-merge child-over-parent; scalars override.
  - Config lists set-union across layers; use `{"!remove": <value>}` markers to drop an inherited
    entry.
  - Skills: `include` dedupes by `(source, id)`; `exclude` matches by skill name (last path
    segment) and prunes **both** inherited `include[]` skills **and** inherited `post_install[]`
    references (e.g. `il-therapist` excludes `duckduckgo-search` to drop the inherited web search).
  - `post_install[]` dedupes by `id` (child overrides, carrying its `tier`); `discovery[]` set-unions
    by `url` (child overrides an entry with the same url); both preserve base→locale→persona order.
  - `setup_steps[]` set-unions by `id` (child overrides), preserving base→locale→persona order;
    `skills.exclude` prunes a step by its `id` (like it prunes `post_install[]`).
  - Layer order is `base → locale → persona`; cycles are rejected by the loader.
- **Skill buckets** (root contract) — reference-only: personas ship no `skills/` content.
  - **Bucket 3 (default path)** — `post_install[]` ids referenced from trusted registries; the apply
    flow auto-installs them (`hermes skills install` / `tap add`). Every id must be verified real.
  - **Bucket 2** — live shared checkouts via `skills.external_dirs` (e.g. `~/open-skills/skills`);
    never copied into `dist/`. **Trust model (by design):** external-dir skills load with **`local`
    trust and are NOT run through Hermes' per-skill hub security scan** — the whole checkout is
    trusted as a unit because it comes from a source the persona author vetted. This is the
    seamless "trust the whole catalogue" path; the scanned, per-skill path is Bucket 3
    (`post_install[]`). Consequence (verified 2026-07 via the factory-home E2E): a skill the hub
    scanner would BLOCK on a community-source install (e.g. `crawl-websites-at-scale`, whose
    `SKILL.md` uses `sudo apt-get`/`pip`) still loads via the external dir. So a skill that a
    Bucket-3 install would block should NOT also be listed in `post_install[]` (it just emits a
    scary BLOCK during apply for no gain) — rely on the Bucket-2 catalogue for it instead.
  - **Bucket 1 (dormant capability)** — `SkillRef.source` ∈ {`github`, `url`, `well-known`} still
    exists for genuinely *fetched* real skills pinned in `locks/` if offline reproducibility is ever
    needed. `source: local` is REMOVED — authoring skill content in-repo is forbidden.
- **Secret hygiene** — never inline a literal secret in `config`, `mcp`, or any fragment.
  Secrets appear only as `${VAR}` / `key_env` and are declared in `env[]`.

## Work Guidance

- Read this file, the root `AGENTS.md`, and any parent template before editing a `template.yaml`.
- Keep persona SOUL fragments small and additive; rely on inherited fragments — do not restate them.
- New provider or fallback env var → append to `env[]` with `required: false` and a default
  matching Hermes' own key name.
- To retire an inherited config list entry, use `{"!remove": <value>}`; do not shadow-copy the
  entire list.
- Bucket-3 skills go in `post_install[]`, never `skills.include[]`.

## Verification

- `python -m configurator verify` (runs schema, merge, SOUL cap, and secret gate over templates).
- `python -m configurator compile <name>` reproduces `dist/<name>/` cleanly for each affected
  persona.

## Child DOX Index

None.
