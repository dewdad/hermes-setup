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
pwsh -File tests/sandbox/run-sandbox.ps1          # generates the .wsb and launches Sandbox
```

That's the whole trigger. To test another persona: `pwsh -File tests/sandbox/run-sandbox.ps1 -Template il-citizen`.

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

At sandbox logon, `provision.ps1` runs and asserts, printing `[PASS]` / `[WARN]` / `[FAIL]`:

| # | Check | Pass criteria |
|---|---|---|
| 1 | Fresh Hermes install | official installer completes; `hermes` resolves |
| 2 | One-step distribution install | `hermes profile install C:\hermes-setup\dist\general` succeeds |
| 3 | Meta-skill carve-out | `meta-skills/finish-setup/SKILL.md` landed; `/finish-setup` registers |
| 4 | Config (no keys) | `config check` reports **no errors** with **no keys set** |
| 5 | Tier-0 chat probe | with **no** key, `hermes -p general -z "…"` returns an auth error (HTTP 403) — reported `[WARN]`, since free chat needs **one** free key or a `hermes auth` sign-in (this is expected, not a defect) |
| 6 | **Keyless** Tier-0 skill | `browser-automation-agent` installs and runs with **no key** |
| 7 | **G1 update-safety** | a planted user skill under `skills/` **survives** `hermes profile update`; `/finish-setup` refreshes |

`WARN` = expected keyless-chat auth failure, or a network/provider hiccup — not a `hermes-setup` defect. `FAIL` = a real contract violation. To confirm chat, set one free key in the sandbox and re-run.

---

## What you do by hand — Part B (Hermes Desktop GUI, inside the sandbox)

The GUI import/chat is the one thing that can't be scripted. Still inside the sandbox:

1. Download **Hermes Desktop**: <https://hermes-agent.nousresearch.com/>
2. Install and launch it.
3. Import / install the profile from `C:\hermes-setup\dist\general` (or pick the `general` profile Part A already installed).
4. Run `/finish-setup` in the Desktop chat → set **one** free provider key (or `hermes auth`), and confirm it renders the tiered flow (the one chat key, Tier-0 vs Tier-1 skills, "discover more" catalogues).
5. Send `hi` in the Desktop chat → after that one key/sign-in, free chat replies. (Web search + browser automation work even before you add the key.)

When done, **close the Sandbox window** — everything is discarded.

---

## Pass criteria (overall)

- **Part A:** rows 1-4, 6, 7 all `[PASS]`; row 5 is a `[WARN]` by design (keyless chat returns HTTP 403 — free chat needs one key). Set one free key and re-run to see chat succeed.
- **Part B:** Desktop imports the profile, keyless web/browser work, and after one free key (or `hermes auth`) free chat replies and `/finish-setup` drives the flow.
- Together these close the **G9** (Desktop shell-exec + in-UI import) and **G10** (free Tier-0 — keyless web/browser + one-key chat) gates on a true blank slate.

---

## Troubleshooting

- **"WindowsSandbox.exe missing"** → enable the feature (Prerequisites) and reboot.
- **Sandbox has no internet** → set `<Networking>Default</Networking>` (the generated `.wsb` already does); check host network/VPN policy.
- **Installer prompts** → answer them in the sandbox window; then re-run `powershell -File C:\hermes-setup\tests\sandbox\provision.ps1`.
- **`hermes` not found after install** → `provision.ps1` refreshes PATH and falls back to `%LOCALAPPDATA%\hermes\hermes-agent\venv\Scripts\hermes.exe`; if it still fails, open a new PowerShell in the sandbox and re-run the script.
- **Want the run's artifacts on the host?** Add a second, writable `<MappedFolder>` to the `.wsb` and have the script copy its log there. Left out by default so the host stays strictly read-only.

---

## Files

- `run-sandbox.ps1` — host launcher: preflight, generate `.wsb`, launch (`-GenerateOnly` to validate without launching).
- `provision.ps1` — runs inside the sandbox: install + assertions (Part A). Never run on the host.
- `hermes-blank.wsb` — static reference config (edit `__REPO_ROOT__`) if you prefer double-clicking over the launcher.
