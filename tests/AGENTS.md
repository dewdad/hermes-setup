# tests/ — DOX child

## Purpose

Own the compiler test suite and the live Hermes harness. Tests must lock the contracts in
the root and sibling `AGENTS.md` files (schema, merge, SOUL cap, secret gate, lock drift,
deterministic emit) and must never damage the developer's live Hermes install.

## Ownership

- All files under `tests/` — unit, integration, and live-harness modules.
- Nothing under `templates/`, `configurator/`, `dist/`, `locks/`, or `skills-vendor/`.

## Local Contracts

- **Live harness safety (HARD)**:
  - Runs ONLY against throwaway named profiles (e.g. `cfgtest-<t>` with a unique suffix).
  - NEVER targets `default`. NEVER invokes Hermes with an empty `-p`. NEVER writes
    `%LOCALAPPDATA%\hermes\config.yaml` (or the POSIX equivalent under `$HERMES_HOME`).
  - Every harness test uses `try` / `finally` with
    `hermes profile delete <name> --yes` in `finally` so a failed assertion still cleans up.
  - Missing provider API keys and a missing `~/open-skills` checkout are **expected** and
    tolerated — the harness skips those assertions, it does not fail.
- **Unit tests** — stdlib `unittest` only (no pytest, no third-party runners). File layout:
  `tests/test_<module>.py` mirroring `configurator/<module>.py`.
- **Secret hygiene (inherited from root)** — tests MUST NOT commit real secrets, real
  `.env` fragments, or real `auth.json` payloads. Fixtures use obvious placeholders like
  `${TEST_KEY}` and are covered by `secretscan.py`.
- **Determinism** — snapshot-style tests compare against sorted-key output; any test that
  depends on filesystem ordering is a bug.
- **Isolation** — every test that touches the filesystem uses `tempfile.TemporaryDirectory`
  (or equivalent) and cleans up on failure.

## Work Guidance

- Add a failing test before changing compiler behavior (TDD, per `configurator/AGENTS.md`).
- New emitted field → new secret-scan test + new determinism test covering it.
- New template merge rule → new merge test with base, locale, and persona layers.
- Never add a live-harness test that skips the throwaway-profile guard, even temporarily.
- When a harness test needs a Hermes subcommand not yet used, add it to the harness helper
  (not inline) so the safety wrapper stays centralized.

## Verification

- `python -m unittest discover -s tests -p "test_*.py"` — all tests pass.
- `python -m configurator verify` — passes after the suite runs (no residue in
  `templates/`, `dist/`, or `locks/`).
- Post-run check: `hermes profile list` shows no leftover `cfgtest-*` profiles.

## Child DOX Index

None.
