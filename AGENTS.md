# hermes-setup — DOX root rail

This repository follows [DOX](https://raw.githubusercontent.com/agent0ai/dox/refs/heads/main/AGENTS.md): the `AGENTS.md`
hierarchy is a set of **binding work contracts** for their subtrees. Any agent (including
Hermes editing itself) must obey them.

## Read Before Editing

1. Read this root `AGENTS.md`.
2. Identify every file/folder you will touch.
3. Walk from repo root to each target; read every `AGENTS.md` along the route.
4. If a parent lists a child `AGENTS.md` whose scope contains the path, read that child too.
5. Nearest doc controls local details; parent docs control repo-wide rules. **No child may weaken the secret-hygiene rule below.**

Do not rely on memory — re-read the applicable chain in the current session.

## Update After Editing

Every meaningful change requires a DOX pass before the task is done. Update the closest owning
`AGENTS.md` (and affected parents/children + their Child DOX Index) when a change affects purpose,
scope, ownership, durable structure, contracts, workflows, inputs/outputs, constraints, artifacts,
user preferences, or the existence/index of any `AGENTS.md`. Remove stale text immediately.

## Closeout

Re-check changed paths against the DOX chain, update nearest owning docs + affected parents/children,
refresh every affected Child DOX Index, delete stale text, run `python -m configurator verify`, and
report any docs intentionally left unchanged and why.

---

## What this repo is

`hermes-setup` is a **template compiler**, not an installer. Layered declarative templates
(`base → locale → persona`, single inheritance) are resolved by the `configurator/` Python package
and emitted as native [Hermes](https://hermes-agent.nousresearch.com/docs) **profile distributions**
into `dist/<persona>/`. Hermes' own `hermes profile install/update` then handles apply, updates,
env-var checks, secret hygiene, and skill security scanning — we never reinvent that machinery.

## Project-wide contracts (binding)

- **Guiding principle** — a user must be able to *quickly* apply a persona and *affordably* run it.
  Curated skills stay **free-to-run and local** (no per-call paid services on the default path).
- **Reference-only skills (HARD RULE)** — this repo **authors no skill content**. Personas only
  *reference* verified-real skill ids from trusted registries; `dist/<persona>/` ships **no**
  `skills/` directory. Every referenced id MUST be confirmed real with `hermes skills search` /
  `hermes skills inspect` before shipping — no fabricated or placeholder ids. Where no trusted
  registry skill exists for a capability, reference the closest real one or omit it (SOUL still
  shapes behavior) — never author one.
- **Auto-install at apply** — referenced skills are emitted machine-readably to
  `dist/<persona>/skills.install.json` (and to the README). The apply flow
  (`bootstrap.ps1`/`bootstrap.sh`) auto-runs `hermes skills install <id>` / `hermes skills tap add
  <tap>` for each, gated by the user's confirmation and tolerant of individual failures, so applying
  a persona lands its skills installed **and** Hermes-security-scanned.
- **Secret hygiene (HARD RULE — no child may weaken it)** — never commit or emit `.env`, `auth.json`,
  `models.json`, `desktop.json`, `state.db*`, `sessions/`, `memories/`, or any literal secret. Emitted
  `config.yaml` references secrets only as `${VAR}` / `key_env`. The compiler **fails the build** on any
  key-shaped literal in emitted output. `ingest` reads the live `config.yaml` **only** — never secrets
  or desktop state.
- **Three-bucket source model** (details in `templates/AGENTS.md` + `locks/AGENTS.md`):
  1. **Vendored + locked (dormant capability)** — retained github/url/well-known fetch + `locks/`
     pinning for genuinely *fetched* real skills if offline reproducibility is ever needed. `local`
     (author-in-repo) is removed. No template uses this today, so `locks/` is empty.
  2. **Referenced live via `skills.external_dirs`** — fast-moving shared checkouts (e.g. `~/open-skills`),
     never copied into `dist/`; Hermes silently skips them if absent.
  3. **Referenced post-install (the DEFAULT path)** — `post_install[]` ids from trusted registries:
     default taps (openai, anthropics, huggingface, NVIDIA, garrytan/gstack), `obra/superpowers`,
     `official/…`, and source-available skills (Anthropic docx/pdf/pptx/xlsx). Never vendored
     (preserves trust + `NVIDIA/skills` signatures, sidesteps redistribution-license issues); the
     apply flow auto-installs them from `skills.install.json`.
- **Determinism & portability** — emit with stable key ordering so `dist/` diffs cleanly in git.
  Windows-first correctness (paths, UTF-8 with Hebrew content) since this machine is the primary test bed.
- **Config schema** — target `_config_version: 33` (Hermes v0.18.x / 2026.7.x). Custom providers use
  `key_env` (not `api_key_env`). Unknown config keys are **warned, not failed** (live Hermes `config check`
  is lenient). After a Hermes upgrade, run `hermes config check` / `hermes config migrate`.
- **Toolchain** — the `configurator/` package is **stdlib + PyYAML only** so it runs anywhere Hermes runs.
  Tests use stdlib `unittest`; run them with `python -m unittest discover -s tests -p "test_*.py"`
  (bare `python -m unittest` from the repo root discovers nothing — `tests/` is not a top-level
  package). No runtime dependency beyond PyYAML.
- **Live testing safety** — harness runs ONLY against throwaway named profiles; never `default`, never
  empty `-p`, never writes `%LOCALAPPDATA%\hermes\config.yaml`. See `tests/AGENTS.md`.

## User Preferences

- Deliver full, working implementations — no demos, no "extend later", no scope reduction.
- Commit messages carry no AI attribution or `Co-Authored-By` lines.
- Prefer editing existing files over creating new ones; never create docs unless required by the plan.

## Child DOX Index

- `templates/AGENTS.md` — template authoring contract: `template.yaml` schema, single-inheritance + merge
  semantics (`include`/`exclude`, `!remove`, base→locale→persona ordering), SOUL fragment composition + 20k
  cap, skill-bucket rules, `env` keys `required: false`.
- `configurator/AGENTS.md` — compiler code contract: stdlib + PyYAML only, secret-literal detection fails the
  build, `ingest.py` reads `config.yaml` only, deterministic emit, per-module responsibility boundaries.
- `dist/AGENTS.md` — generated-output contract: never hand-edit (regenerate via `compile`); committed but
  contains no secrets and no `skills/` content (reference-only); ships `skills.install.json` for auto-install.
- `locks/AGENTS.md` — lockfile provenance contract: `source_id`, `resolved_commit_or_hash`, `fetched_at`,
  `license`, `redistributable`; `--update-locks` is the only writer.
- `tests/AGENTS.md` — harness safety contract: throwaway named profiles only; never target `default`/empty
  `-p`; never write `%LOCALAPPDATA%\hermes\config.yaml`; teardown via try/finally.
