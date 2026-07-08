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
  `hermes skills install`. `distribution_owned` therefore does NOT list `skills`, so a
  `hermes profile update` never touches the user's installed skills. (`skills` is only re-added to
  the owned set in the rare case a template genuinely vendors a fetched github/url/well-known skill.)
- **Distribution layout** (per persona) — the compiler emits:
  - `distribution.yaml` — flat Hermes distribution manifest.
  - `config.yaml` — Hermes config fragment (uses `${VAR}` / `key_env`; never literal secrets;
    no `_config_version` from templates — compiler stamps `33`).
  - `SOUL.md` — composed SOUL (≤ 20000 chars).
  - `cron/` — scheduled task definitions.
  - `skill-bundles/` — declared bundles (skill *names* only, no content).
  - `skills.install.json` — machine-readable referenced-skill list the apply flow auto-installs
    (present iff the persona declares `post_install[]`).
  - `.env.EXAMPLE` — every env var the config references, no secrets.
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
