# locks/ — DOX child

## Purpose

Own the lockfiles that pin every vendored (bucket 1) skill *genuinely fetched* by a template, so a
compile on any machine reproduces byte-identical `dist/<name>/` output offline. Locks are the
provenance record for anything the compiler copies into a distribution.

**Under the reference-only model this directory is normally empty** (only `AGENTS.md`): personas
reference skills post-install (bucket 3) and vendor nothing, so there are no lock entries. Lockfiles
reappear only if a template ever uses a `github`/`url`/`well-known` fetch for offline pinning.

## Ownership

- `locks/<template>.lock.json` — one lockfile per top-level template that vendors skills (none today).
- Nothing under `templates/`, `configurator/`, `dist/`, or `tests/`.

## Local Contracts

- **Entry shape** — each vendored skill entry contains exactly:
  - `source_id` — stable identifier for the SkillRef (source + id).
  - `resolved` — content hash, formatted `sha256:<hex>`.
  - `fetched_at` — ISO-8601 UTC timestamp of the fetch that produced `resolved`.
  - `license` — SPDX identifier (or `UNKNOWN` when upstream declares none).
  - `redistributable` — boolean.
- **Single writer** — `python -m configurator update-locks` is the ONLY tool permitted to
  write, add, or remove entries. Hand-edits are forbidden and treated as tampering. When a template
  vendors nothing, `update-locks` **prunes** its orphan lockfile (deletes it) instead of writing an
  empty one — so a clean reference-only repo has no lockfiles at all.
- **Compile is offline + strict** — `python -m configurator compile` reads locks read-only.
  Any drift between a skill's current content hash and its `resolved` value fails the build;
  the fix is to run `update-locks` and review the diff, never to edit the file.
- **Redistribution gate** — a vendored entry with `redistributable: false` fails the build.
  Such skills MUST move to `post_install[]` (bucket 3) in the template instead of being
  vendored.
- **Secret hygiene** — lockfiles never contain credentials, tokens, or URLs with embedded
  secrets. Only public source identifiers and hashes.

## Work Guidance

- After changing a `SkillRef` in any `template.yaml` (add, remove, upgrade a pin), run
  `python -m configurator update-locks` and commit the lockfile diff **in the same commit**
  as the template change.
- Review every `update-locks` diff: unexpected `license` shifts or a new
  `redistributable: false` entry mean the skill must be re-classified before merge.
- Do not delete a lockfile to "reset" state — remove the referencing template first, then run
  `update-locks`, which will prune orphan entries.

## Verification

- `python -m configurator update-locks` followed by `git diff --exit-code locks/` — clean
  (no unrecorded fetches).
- `python -m configurator verify` — passes the drift check and the
  `redistributable: false` gate for every entry.
- `python -m configurator compile --all` succeeds offline against the committed locks.

## Child DOX Index

None.
