# Blank-Slate Desktop E2E Playbook (Windows Sandbox)

Test `hermes-setup` end-to-end the way a **brand-new layman** would — install Hermes fresh, install
the `general` distribution, run keyless browser/web, add one free key (or a Nous sign-in) to turn on
free chat, and run `/finish-setup` — on a **disposable, fully isolated Windows Sandbox** that
**cannot touch your real environment**.

> **Why this is safe.** Windows Sandbox is a throwaway VM. This repo is mapped **read-only**, and the
> entire sandbox OS — the Hermes install, the profile, any keys you type — is **discarded when you
> close the window**. Your real Hermes home (`%LOCALAPPDATA%\hermes`: `config.yaml`, `.env`, keys,
> `profiles/`, `auth.json`, `sessions/`) is **never read or written**.

---

## Trigger it (fresh session — paste this)

From the repo root on the **host**:

```powershell
python -m configurator compile general           # ensure dist/general is current
pwsh -File tests/sandbox/run-sandbox.ps1          # generates the .wsb, launches Sandbox, streams results
```

That's the whole trigger. Part A runs **hands-off** — nothing is typed inside the VM. `run-sandbox.ps1`
maps one extra **log-only** folder writable (the repo stays read-only), the sandbox auto-runs
`provision.ps1` and tees its output there, and the launcher **streams that log back to your host
terminal** and prints the final PASS/FAIL. So you never fight the VM's clipboard or display for Part A.

To test another persona: `pwsh -File tests/sandbox/run-sandbox.ps1 -Template il-citizen`. Flags:
`-NoWait` (launch without streaming), `-NoLog` (strict read-only; results then show only inside the VM),
`-GenerateOnly` (validate the `.wsb` without launching).

> **Agent prompt (paste into a fresh session):**
> *"Run the hermes-setup blank-slate Desktop E2E: from the repo root run
> `python -m configurator compile general` then `pwsh -File tests/sandbox/run-sandbox.ps1`. Windows
> Sandbox opens and auto-runs `tests/sandbox/provision.ps1`. Report Part A [PASS]/[FAIL] lines, then
> walk me through Part B (the manual Desktop GUI steps). Do NOT touch my host Hermes install."*

---

## Prerequisites (one-time)

1. **Windows 10/11 Pro, Enterprise, or Education** (Sandbox isn't on Home).
2. **Enable Windows Sandbox** (Admin PowerShell, then reboot):
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -All
   ```
3. `dist/general/` compiled (the trigger's first line does this).

`run-sandbox.ps1` preflights both (missing feature / missing dist → a clear error, nothing launches).

---

## What happens automatically — Part A (CLI, inside the sandbox)

At sandbox logon, `provision.ps1` runs automatically and asserts, printing `[PASS]` / `[WARN]` / `[FAIL]`.
By default that output is **teed to the writable host log folder and streamed back to your host
terminal** (the launcher tails it and prints the final PASS/FAIL count), so you read Part A on the
host — no clipboard or VM-display wrangling. The checks:

| # | Check | Pass criteria |
|---|---|---|
| 1 | Fresh Hermes install | official installer completes; `hermes` resolves |
| 2 | One-step distribution install | `hermes profile install C:\hermes-setup\dist\general` succeeds |
| 3 | Meta-skill carve-out | `meta-skills/finish-setup/SKILL.md` landed; `/finish-setup` registers |
| 4 | Config (no keys) | `config check` reports **no errors** with **no keys set** |
| 5 | Tier-0 chat probe | with **no** key, `hermes -p general -z "…"` returns an auth error (HTTP 403) — reported `[WARN]`, since free chat needs **one** free key or a `hermes auth` sign-in (this is expected, not a defect) |
| 6 | **Keyless** Tier-0 skill | `browser-automation-agent` installs and runs with **no key** |
| 7 | **G1 update-safety** | a planted user skill under `skills/` **survives** `hermes profile update`; `/finish-setup` refreshes |
| 8 | **Desktop prereq (WebView2)** | the Evergreen Edge WebView2 Runtime is silently pre-installed (Windows Sandbox ships without it) so the Desktop installs cleanly (WARN if the network blocks the download) |
| 9 | **Desktop app install (layman path)** | `Hermes-Setup.exe` (the signed Tauri/NSIS bootstrap installer) is downloaded and installed **silently** (`/S`), exactly as a non-technical user would, so Part B is just "launch Hermes and onboard" — no browser download, no installer click-through (WARN if the network blocks it or no Start-Menu entry is found) |

`WARN` = expected keyless-chat auth failure, or a network/provider hiccup (e.g. the WebView2 or Hermes-Setup.exe download) — not a `hermes-setup` defect. `FAIL` = a real contract violation. To confirm chat, set one free key in the sandbox and re-run.

---

## What you do by hand — Part B (Hermes Desktop GUI, inside the sandbox)

The GUI onboarding/chat is the one thing that can't be scripted. Part A already installed Hermes
Desktop for you via `Hermes-Setup.exe /S` (step 9) and the WebView2 runtime it needs (step 8), so
there's **no browser download and no installer click-through** — just the GUI steps a layman does:

1. Launch **Hermes** from the Start Menu (installed silently in step 9). If a first-launch setup
   runs, let it finish — it provisions the desktop runtime for you.
2. Import / install the profile from `C:\hermes-setup\dist\general` (or pick the `general` profile Part A already installed).
3. Run `/finish-setup` in the Desktop chat → set **one** free provider key (or `hermes auth`), and confirm it renders the tiered flow (the one chat key, Tier-0 vs Tier-1 skills, "discover more" catalogues).
4. Send `hi` in the Desktop chat → after that one key/sign-in, free chat replies. (Web search + browser automation work even before you add the key.)

When done, **close the Sandbox window** — everything is discarded.

---

## Fast dev iteration — `-PersistHome` (NOT a blank slate)

The full install (CLI toolchain + WebView2 + `Hermes-Setup.exe /S`) is ~15 min. Paying that on every
iteration while you work on Part B is untenable, and **Windows Sandbox cannot snapshot/save state**.
`-PersistHome` is the substitute: it maps a persistent writable host folder as the sandbox's
`HERMES_HOME` + Playwright cache + Desktop-app dir, so the install is paid **once** and **reused**.

```powershell
pwsh -File tests/sandbox/run-sandbox.ps1 -PersistHome
```

- **First run:** installs into `%LOCALAPPDATA%\hermes-sandbox-persist\<template>` on the host (~15 min).
- **Every later run:** `provision.ps1` detects the persisted install and **skips** the CLI toolchain
  (step 1), the profile install (step 2), and the desktop install (step 9) → **seconds** to a working
  env. WebView2 (step 8) still re-runs (~30 s — it is system/registry state that can't persist).
- **Reset the whole store:** delete `%LOCALAPPDATA%\hermes-sandbox-persist\<template>` (forces a full reinstall next run).

### Dirty (default) vs. reset-to-baseline (`-ResetState`)

`-PersistHome` alone keeps a **lived-in "dirty" home**: mutable Hermes state (`sessions/`, `logs/`,
`memories/`, the step-7 sentinel skill, the step-6 skill install, any profile drift) **accumulates**
across runs. That is intentional and useful — e.g. to test how a **hermes-setup distribution update /
version bump** lands on an *existing* user (bump the dist, re-run persisted, watch `hermes profile
update`).

Add **`-ResetState`** when you instead want a **fresh post-install slate every run** without paying
the install again:

```powershell
pwsh -File tests/sandbox/run-sandbox.ps1 -PersistHome -ResetState
```

It keeps the expensive install (toolchain, venv, Node, Playwright, Desktop app) but, before the
checks, **reinstalls the profile pristine from the mapped dist and clears `sessions/`/`logs/`/`memories/`**
— fast **and** clean each iteration. It is a **profile/session reset, not a full wipe**: the install,
the Playwright cache, and any keys already in `HERMES_HOME\.env` are preserved. (`-ResetState` has no
effect without `-PersistHome`; a normal run is already a fresh VM every time.)

> ⚠️ **Neither persist mode is the gate.** Because they carry the install across runs they are **not a
> blank slate** — always validate the real **G9/G10** gate with a normal (PersistHome-off) run. For a
> bulletproof frozen-OS image (files + registry + shortcuts + WebView2), use a **Hyper-V checkpoint**
> (`hyperv-checkpoint.ps1`), whose `-Action Run` reverts to a fresh post-install OS every time.

---

## Pass criteria (overall)

- **Part A:** rows 1-4, 6, 7 all `[PASS]`; row 5 is a `[WARN]` by design (keyless chat returns HTTP 403 — free chat needs one key). Set one free key and re-run to see chat succeed.
- **Part B:** Desktop imports the profile, keyless web/browser work, and after one free key (or `hermes auth`) free chat replies and `/finish-setup` drives the flow.
- Together these close the **G9** (Desktop shell-exec + in-UI import) and **G10** (free Tier-0 — keyless web/browser + one-key chat) gates on a true blank slate.

---

## Troubleshooting

- **"WindowsSandbox.exe missing"** → enable the feature (Prerequisites) and reboot.
- **Sandbox has no internet** → set `<Networking>Default</Networking>` (the generated `.wsb` already does); check host network/VPN policy.
- **Logon command didn't auto-run / no terminal window** → known Windows Sandbox flakiness (the logon command can fire before the desktop is ready). The generated `.wsb` mitigates it with a `Start-Sleep` settle delay; if it still doesn't run, open PowerShell in the VM and run `powershell -ExecutionPolicy Bypass -File C:\hermes-setup\tests\sandbox\provision.ps1 -LogDir C:\hermes-logs`.
- **Installer prompts** → answer them in the sandbox window; then re-run the `provision.ps1` line above.
- **`hermes` not found after install** → `provision.ps1` refreshes PATH and falls back to `%LOCALAPPDATA%\hermes\hermes-agent\venv\Scripts\hermes.exe`; if it still fails, open a new PowerShell in the sandbox and re-run the script.
- **Where are the results on the host?** By default `run-sandbox.ps1` maps one **log-only** folder writable (`%TEMP%\hermes-sandbox-logs\<template>` → `C:\hermes-logs`) and streams `provision.log` back to your terminal; `DONE.txt` holds the final `failures=N`. The **repo mapping stays read-only** and `%LOCALAPPDATA%\hermes` is never mapped. Use `-NoLog` for strictly-read-only (results visible only inside the VM).

---

## Files

- `run-sandbox.ps1` — host launcher: preflight, generate `.wsb` (repo read-only + one writable log-only mount), launch, and stream the host log to completion. Flags: `-GenerateOnly` (validate without launching), `-NoWait` (launch without streaming), `-NoLog` (strict read-only, no host log), `-PersistHome` (fast dev re-runs, **not** blank-slate — see "Fast dev iteration" above), `-ResetState` (with `-PersistHome`: fresh post-install slate each run instead of an accumulating "dirty" home).
- `provision.ps1` — runs inside the sandbox: install + assertions (Part A). Takes `-LogDir` to tee output + write `DONE.txt` to the writable log mount, `-PersistRoot` to reuse a persisted HERMES_HOME/cache/desktop across runs, and `-ResetState` to wipe mutable state to the post-install baseline each persisted run. Never run on the host.
- `hermes-blank.wsb` — static reference config (edit `__REPO_ROOT__`) if you prefer double-clicking over the launcher (manual fallback: `-File`, no host log stream).
- `hyperv-checkpoint.ps1` — **Option B (scaffold):** the heavier, TRUE-saved-state alternative. Wraps Hyper-V checkpoint/revert around a VM you provision once, so each revert is a byte-identical post-install OS. Requires a one-time manual VM setup (your Windows ISO/license); not yet run end-to-end here.
