# Blank-Slate CLI E2E Playbook (Relocated HERMES_HOME)

Test `hermes-setup` end-to-end from a genuine **brand-new-user state** — no keys, no profiles, no
`auth.json` — **fast, fully scriptable, and host-safe**, with **no VM and no GUI**. This is the quick
counterpart to the [Windows Sandbox playbook](../sandbox/PLAYBOOK.md): use this for rapid, repeatable
CLI/headless runs; use the Sandbox one when you specifically need the **Desktop GUI**.

> **Why this is safe.** Everything a Hermes user has lives under `HERMES_HOME`
> (`config.yaml`, `.env`+keys, `profiles/`, `auth.json`, `sessions/`). The script points
> `HERMES_HOME` at a **throwaway temp directory** — and the env change is **process-scoped** (it
> only affects the script's own `hermes` calls, never your shell, user, or machine environment).
> Before doing anything it **hard-asserts** that `hermes config path` resolves *inside* the temp dir
> and is *not* your real home, aborting otherwise. The temp home is deleted on exit. Your real
> `%LOCALAPPDATA%\hermes` (POSIX `~/.hermes`) is never read or written.

---

## Trigger it (fresh session — paste this)

From the repo root:

```powershell
python -m configurator compile general                 # ensure dist/general is current
pwsh -File tests/blank-home/run-blank-home.ps1          # Windows
```

```bash
python -m configurator compile general
bash tests/blank-home/run-blank-home.sh                 # Linux / macOS / WSL / Git-Bash
```

Other personas: add `-Template il-citizen` (PS) / `--template il-citizen` (bash). Keep the temp home
for inspection with `-KeepHome` / `--keep-home`.

> **Agent prompt (paste into a fresh session):**
> *"Run the hermes-setup blank-slate CLI E2E: from the repo root run
> `python -m configurator compile general` then `pwsh -File tests/blank-home/run-blank-home.ps1`
> (or the .sh on POSIX). It relocates HERMES_HOME to a disposable temp dir, so my real Hermes install
> must not be touched. Report the [PASS]/[FAIL] lines and confirm the temp home was removed."*

---

## What it does (automated)

| # | Step | Pass criteria |
|---|---|---|
| 0 | Relocate `HERMES_HOME` to a temp dir + **isolation guard** | `hermes config path` resolves inside the temp dir (else it aborts) |
| 1 | One-step install | `hermes profile install ./dist/<t> --name blankslate` succeeds |
| 2 | Meta-skill carve-out | `meta-skills/finish-setup/SKILL.md` landed; **no `skills/`** shipped; `/finish-setup` registers |
| 3 | Config (no keys) | `config check` reports **no errors** with **no keys set** |
| 4 | Tier-0 chat probe | with **no** key, `hermes -p blankslate -z "…"` returns an auth error (HTTP 403) — reported `[WARN]`, since free chat needs **one** free key or a `hermes auth` sign-in (expected, not a defect) |
| 5 | **Keyless** Tier-0 skill | `browser-automation-agent` installs and runs with **no key** |
| 6 | **G1 update-safety** | a planted user skill under `skills/` **survives** `hermes profile update`; `/finish-setup` refreshes |
| 7 | Teardown | temp home removed; `HERMES_HOME` unset (skipped with `-KeepHome`) |

`WARN` = the expected keyless-chat auth failure (free chat needs one key), or a transient network/provider hiccup — not a `hermes-setup` defect. `FAIL` = a real contract violation; the script exits non-zero so CI catches it.

---

## Pass criteria (overall)
- Steps 1–3, 5, 6 all `[PASS]`; step 4 is a `[WARN]` by design (keyless chat returns HTTP 403 — free chat needs one key). Set one free key (or `hermes auth`) and re-run to see chat succeed.
- Script exits `0`. The temp home no longer exists (unless `-KeepHome`).
- Proves **free Tier-0** on a true blank slate, headless: keyless web/browser work immediately, and chat is one free key / sign-in away (**G10**). It does **not** cover the Desktop GUI (**G9b**) — for that, use the [Sandbox playbook](../sandbox/PLAYBOOK.md).

---

## Notes & scope

- **This is the CI-friendly path.** Pure CLI, cross-platform, disposable — wire it into a nightly/live lane (it's network-dependent for steps 4–5, so keep it out of the offline PR gate).
- **Bonus a named profile can't give:** because the *whole home* is throwaway, you can also safely exercise the **default-profile / bootstrap** flow here — e.g. `-KeepHome`, then `HERMES_HOME=<that dir> ./bootstrap.ps1 -Template general` — without any risk to your real default profile.
- **Desktop caveat:** a GUI launched from the Start Menu inherits the *system* env, not this script's process-scoped `HERMES_HOME`, so it would use your real home. To exercise the Desktop app on a blank slate, use Windows Sandbox instead.

---

## Files
- `run-blank-home.ps1` — Windows E2E (relocate → assert isolation → install → assert → teardown).
- `run-blank-home.sh` — POSIX sibling (same flow; `mktemp` home + `EXIT` trap cleanup).
