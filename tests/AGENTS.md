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
  compiled distribution, then the same Tier-0 + `/finish-setup` + G1 assertions on a pristine home,
  then silently pre-provisions the Edge **WebView2 Runtime** (Windows Sandbox ships without it, and
  the Hermes Desktop hard-requires it), and finally installs **Hermes Desktop the layman way** by
  downloading the signed Tauri/NSIS bootstrap installer `Hermes-Setup.exe` and running it silently
  (`/S`) — so the manual Part B is reduced to launching the pre-installed app and onboarding (no
  browser download, no installer click-through in the VM). Both the WebView2 and Hermes-Setup.exe
  steps are network-tolerant (WARN, not FAIL — Part A's contract is the CLI) and idempotent;
  `PLAYBOOK.md` adds the manual Desktop-GUI steps. **This is the ONE harness exempt from the
  `cfgtest-*` / never-`default` naming rule** — its isolation is stronger (a whole throwaway OS with
  the host mapped read-only), so `provision.ps1` may install a profile named `general` and needs no
  teardown. It MUST run only inside Windows Sandbox; never run `provision.ps1` on the host.
  - **Hands-off host-log capture (default).** So the run needs **zero typing inside the VM** (no
    clipboard, no fighting the VM display), `run-sandbox.ps1` maps ONE extra, **log-only** host
    folder **writable** (`$LogDirHost` → `C:\hermes-logs`) and the logon command auto-runs
    `provision.ps1 -LogDir C:\hermes-logs` after a short settle delay. `provision.ps1` tees all
    output to `<LogDir>\provision.log` and writes `<LogDir>\DONE.txt` (`failures=N`) in a `finally`,
    so the host launcher tails the log and prints the real PASS/FAIL without touching the VM. **This
    does not weaken isolation:** the **repo mapping stays READ-ONLY**, `%LOCALAPPDATA%\hermes` is
    never mapped, and the only writable mount is a dedicated, throwaway log directory. `-NoLog`
    restores the strictly-read-only (results-visible-only-in-VM) behavior; `-NoWait` launches without
    tailing. The static `hermes-blank.wsb` fallback remains manual (`-File`, no host log).
  - **`-PersistHome` — DEV fast-iteration mode (opt-in; NOT blank-slate).** The full install (CLI
    toolchain + WebView2 + `Hermes-Setup.exe /S`) costs ~15 min; paying it every iteration is
    untenable. `-PersistHome` maps a SECOND writable host folder
    (`%LOCALAPPDATA%\hermes-sandbox-persist\<template>` → `C:\hermes-persist`) and passes
    `provision.ps1 -PersistRoot C:\hermes-persist`, which relocates **HERMES_HOME**, the **Playwright
    browser cache** (`PLAYWRIGHT_BROWSERS_PATH`), and the **Desktop-app dir** (`Hermes-Setup.exe
    /D=`) under it. First run installs into that persisted store; later runs **detect and reuse it**
    (`Resolve-Hermes` prefers `$env:HERMES_HOME`; step 2 skips an existing profile; step 9 skips an
    existing desktop exe) — seconds to a working env. Windows Sandbox itself CANNOT snapshot/save
    state; this mapped-folder persistence is the substitute (WebView2 still re-runs each time — it is
    registry/system state that does not persist, but it is cheap + idempotent). **This deliberately
    carries state across runs, so it is NOT the pristine G9/G10 gate** — the default
    (PersistHome-off) run remains the blank-slate gate; `-PersistHome` is only for iterating on
    Part B. Delete the host persist folder to reset to a clean slate. A true frozen-OS image
    (files + registry + shortcuts + WebView2) is a **Hyper-V checkpoint** job — see the Option B
    scaffold `hyperv-checkpoint.ps1` (provision a VM once → `-Action Checkpoint` → `-Action Run`
    reverts to the frozen post-install OS in seconds; needs a one-time manual VM setup, not yet run
    end-to-end).
  - **Dirty (default) vs `-ResetState`.** `-PersistHome` alone keeps a **lived-in "dirty" home**:
    mutable state (`sessions/`, `logs/`, `memories/`, the step-7 sentinel skill, the step-6 skill,
    profile drift) **accumulates** across runs — intentional, for testing how a distribution
    **update / version bump** lands on an existing user via `hermes profile update`. Adding
    `-ResetState` (run-sandbox.ps1 → `provision.ps1 -ResetState`) instead deletes+reinstalls the
    profile pristine from the mapped dist and clears `sessions/`/`logs/`/`memories/` **before** the
    checks — a fresh post-install slate each run while keeping the expensive install. `-ResetState`
    is a no-op without `-PersistHome` (a non-persist run is already a fresh VM every time).
  - **step 9 hardening** — `Hermes-Setup.exe /S` is a long (~8 min) real install that has been
    observed NOT to return promptly; step 9 launches it with `-PassThru` + `Wait-Process -Timeout 720`
    (12 min) rather than a bare `-Wait`, so a hung/slow installer can never block Part A's
    summary/`DONE.txt`.
  - **`-HostHermes` — DEV fast mode (CLI-only; NOT blank-slate).** Skips the ~15-min fresh install by
    mapping the HOST's already-installed Hermes CLI into the VM at IDENTICAL absolute paths, READ-ONLY,
    and putting its `venv\Scripts` on `PATH` — a working `hermes` in seconds. The venv is not
    self-contained, so `run-sandbox.ps1 -HostHermes` maps BOTH the install dir
    (`HERMES_HOME\hermes-agent`, a secret-free SUBFOLDER — the parent home with
    `.env`/`auth.json`/`config.yaml` is NEVER mapped) and the venv's base uv Python (`pyvenv.cfg`
    `home` — `python311.dll` + stdlib), because the `.exe` launchers bake in absolute paths.
    `provision.ps1 -HostHermes -HostInstallDir <dir>` sets `PYTHONDONTWRITEBYTECODE=1` (read-only tree)
    and resolves `hermes` from the map instead of installing; `HERMES_HOME` stays a FRESH VM-local dir
    so no host state is read or written. By default the Desktop steps (8/9) are SKIPPED — it proves the
    CLI, not the GUI. Like `-PersistHome`, it is a dev optimization, NOT the pristine G9/G10 gate.
  - **`-Desktop` — provision WebView2 + launch the native Electron app.** Provisions the WebView2
    Runtime (step 8) then replaces the `Hermes-Setup.exe` download (step 9) with `hermes desktop`, the
    native Electron app under `apps/desktop`. Combined with `-HostHermes` it passes `--skip-build` to
    launch the host's PREBUILT app (`apps/desktop/release/win-unpacked/Hermes.exe`, mapped read-only) —
    no `npm install`, no build, no write into the read-only tree (Electron writes userData under
    `HERMES_HOME`/`%APPDATA%`). The app is launched NON-BLOCKING so `provision.ps1` finishes + writes
    `DONE.txt` while the GUI stays up (the `-NoExit` logon shell keeps the VM alive). Also NOT the
    blank-slate gate — it reuses the host's prebuilt app. **Operational note:** never force-kill the
    WindowsSandbox client/server to close a run — that ORPHANS the utility VM (`vmmemWindowsSandbox` +
    `vmwp`), which holds the mapped log folder and blocks the next launch; close the VM window
    gracefully instead.
- **Blank-slate CLI E2E (`tests/blank-home/`)** — the fast, headless, cross-platform counterpart to
  the sandbox: `run-blank-home.ps1` / `run-blank-home.sh` relocate `HERMES_HOME` to a **throwaway
  temp dir** (a genuine brand-new-user state) and run the same Tier-0 + `/finish-setup` + G1
  assertions, then delete the temp home. **Host-safe by construction:** the `HERMES_HOME` export is
  **process-scoped** (never touches the machine/user env), and both scripts **hard-assert
  `hermes config path` resolves inside the temp home and is not the real home, aborting otherwise**.
  Like the sandbox, this is exempt from the `cfgtest-*` naming rule (the entire home is disposable).
  Covers G10 headless; the Desktop GUI (G9b) still requires the sandbox playbook.
- **Saved-state CLI E2E (`tests/factory-home/`)** — the fully agent-driveable, headless regime with a
  **snapshot/restore `HERMES_HOME`**: `factory-home.ps1` (Windows, primary bed) + `factory-home.sh`
  (POSIX sibling) mirror the same actions and assertions. The Hermes **Desktop app shares this exact
  `HERMES_HOME`** (`config.yaml`, `profiles/`, `auth.json`, `desktop.json`, `skills/`, `sessions/`), so
  driving it through the `hermes` CLI exercises the same state the GUI renders — this is the
  CLI-driveable Desktop surface (the actual GUI window still needs the sandbox playbook). A persistent
  host **store** holds two homes: `<store>/factory/` (a snapshot of a post-install home — a "freshly
  installed / factory-reset Desktop" with the compiled profile applied + Tier-0 skills) and
  `<store>/work/` (the live home). Actions:
  - **`Build`** (once) — fresh `profile install` + Tier-0 skill into `work/`, assert the Tier-0
    contract, then mirror `work/ -> factory/`. Pays the install cost a single time.
  - **`Reset`** (per run) — mirror `factory/ -> work/` (a fast robocopy/rsync `/MIR`, seconds, **NOT a
    reinstall**) and re-assert the pristine contract. This is the **saved-state "start from a
    factory-reset Desktop"** gate — the optimization that avoids reinstalling every turn.
  - **`Dirty`** (per run) — leave `work/` **as-is** (accumulated `sessions/`/skills/config drift) and
    run `hermes profile update` (and, with `-NewPersona` / `--new-persona <name>`, install ANOTHER
    compiled persona) against it; asserts the update lands, the **G1** user-skill-survival guard holds,
    and a newly-installed persona does not clobber the existing one. This is the **update/install
    personas on a dirty install** gate.
  - **`Status`** / **`Clean`** — inspect the store / remove it entirely.
  **Host-safe by the same construction as blank-home:** `HERMES_HOME` is set **process-scoped** and
  every action **hard-asserts `hermes config path` resolves inside the store** (and that the store is
  not the real home), aborting otherwise. Store default: `%LOCALAPPDATA%\hermes-e2e\<template>` (POSIX
  `${XDG_DATA_HOME:-$HOME/.local/share}/hermes-e2e/<template>`). Exempt from the `cfgtest-*` naming rule
  (the whole store is a throwaway home). Because the store deliberately persists across runs (that is
  the saved-state point), it is not auto-torn-down — `Clean` (or deleting the store) resets it.
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
