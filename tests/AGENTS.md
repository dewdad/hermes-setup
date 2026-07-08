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
  - Every harness run tears the profile down in a `finally` block (`livetest.ps1`) / `EXIT` trap
    (`livetest.sh`) with `hermes profile delete <name> --yes` so a failed assertion still cleans up.
  - Missing provider API keys and a missing `~/open-skills` checkout are **expected** and
    tolerated — the harness skips those assertions, it does not fail. Network-only checks
    (`-InstallSkills` / `--install-skills`, `-ResolveIds` / `--resolve-ids`) are **opt-in** so the
    default run stays offline-safe.
- **Live harness scripts** — `livetest.ps1` (Windows, primary bed) and `livetest.sh` (POSIX sibling)
  mirror the same assertions: the reference-only contract (distribution ships **no `skills/`**), the
  meta-skill carve-out (`meta-skills/finish-setup/SKILL.md` lands and `/finish-setup` registers), and
  the **G1 update-safety regression** — plant a user skill under the profile's `skills/`, run
  `hermes profile update`, and assert it **survives** (Hermes' updater wholesale-replaces shipped
  top-level dirs, so a stray `skills/` payload would wipe user skills). This guard turns the manual
  probe that first caught G1 into a permanent gate; keep it in both scripts.
- **Blank-slate Desktop E2E (`tests/sandbox/`)** — the layman/Desktop path (Feature 5, gates G9/G10)
  is tested in **Windows Sandbox**, a disposable VM. `run-sandbox.ps1` (host launcher) maps the repo
  **read-only** and auto-runs `provision.ps1` inside the sandbox: fresh Hermes install, install the
  compiled distribution, then the same Tier-0 + `/finish-setup` + G1 assertions on a pristine home;
  `PLAYBOOK.md` adds the manual Desktop-GUI steps. **This is the ONE harness exempt from the
  `cfgtest-*` / never-`default` naming rule** — its isolation is stronger (a whole throwaway OS with
  the host mapped read-only), so `provision.ps1` may install a profile named `general` and needs no
  teardown. It MUST run only inside Windows Sandbox; never run `provision.ps1` on the host.
- **Blank-slate CLI E2E (`tests/blank-home/`)** — the fast, headless, cross-platform counterpart to
  the sandbox: `run-blank-home.ps1` / `run-blank-home.sh` relocate `HERMES_HOME` to a **throwaway
  temp dir** (a genuine brand-new-user state) and run the same Tier-0 + `/finish-setup` + G1
  assertions, then delete the temp home. **Host-safe by construction:** the `HERMES_HOME` export is
  **process-scoped** (never touches the machine/user env), and both scripts **hard-assert
  `hermes config path` resolves inside the temp home and is not the real home, aborting otherwise**.
  Like the sandbox, this is exempt from the `cfgtest-*` naming rule (the entire home is disposable).
  Covers G10 headless; the Desktop GUI (G9b) still requires the sandbox playbook.
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
