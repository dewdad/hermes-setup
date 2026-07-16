# Agent Runbook — Install a Hermes persona from this repo

This file is a **prompt any capable coding agent** (Hermes itself, Claude, Codex, etc.) can follow to install one of the compiled personas in `dist/<persona>/` onto the current machine.

It contains two independent runbooks. Pick one:

- **Runbook A — Named profile** (recommended, isolated): install a distribution as its own Hermes profile via `hermes profile install`. Cleanest, fully sandboxed, easy to delete.
- **Runbook B — Default profile via bootstrap**: apply a distribution *into the default profile* by running `bootstrap.ps1` / `bootstrap.sh`. Idempotent and non-destructive: backs up, preserves customisation, never overwrites `.env`.

Both runbooks assume `dist/<persona>/` already exists. If it does not, run `python -m configurator compile <persona>` first (or `python -m configurator compile --all`).

**Free (default) or paid Nous Portal.** Every persona runs on the free chain by default. To run it on a **paid Nous Portal** subscription instead (frontier agentic models + the Nous Tool Gateway), add the paid-mode flag — `install.sh <name> --pro` / `install.ps1 <name> -Pro` (Runbook A) or `bootstrap.sh --template <name> --portal` / `bootstrap.ps1 -Template <name> -Portal` (Runbook B). It installs the persona's free distribution, then splices the `general-pro` base-layer config (`hermes config set`) and runs the Portal OAuth login (`hermes auth add nous`). Requires a **paid** Portal plan and `dist/general-pro/` compiled; the free path never needs it. Inside the agent, `/finish-setup` offers the same upgrade via `hermes setup --portal`.

> **Prerequisites first.** Before either runbook, the host needs the one-time setup in
> [`PREREQUISITES.md`](PREREQUISITES.md): Hermes installed, the **free Nous Portal subscription** +
> `hermes setup --portal` login (the baseline that powers free chat), and **Node.js + git** (the
> bootstrap flow clones + builds the Google Workspace CLI). Beeper Desktop and a Google account are
> optional Tier-1 extras. All free to run.

---

## Ground truth every agent must respect

Before doing anything, read these facts. They apply to **both** runbooks.

- **`HERMES_HOME` is resolved dynamically — never hardcode a path.** In order:
  1. `$HERMES_HOME` environment variable, if set.
  2. `hermes config path` → the *parent directory* of the printed path.
  3. Platform default: Windows Desktop installer → `%LOCALAPPDATA%\hermes`; shell installer → `~/.hermes`.

  Confirm with `hermes config path` and `hermes config env-path` before touching files. Named profiles live under `HERMES_HOME/profiles/<name>/`; the default profile is `HERMES_HOME/` itself.

- **Secrets are never in `config.yaml`.** The distribution's `config.yaml` uses only `${VAR}` / `key_env` references, resolved from `HERMES_HOME/.env` (or `HERMES_HOME/profiles/<name>/.env`). That is why `config.yaml` is safe to version-control and safe to ship in `dist/`.

- **`.env.EXAMPLE` is a template, never a secret store.** Copy it to `.env` and fill in real keys **only inside `HERMES_HOME`**. Never write a real key into anything under this repo, and never overwrite an existing `.env`.

- **`base/general` provider keys are all optional.** Any single key (`ZENMUX_API_KEY`, `OPENCODE_ZEN_API_KEY`, `NVIDIA_API_KEY`, or `GOOGLE_API_KEY`) yields a working agent. Missing keys log warnings, not errors.

- **Distributions ship `cron/*.json` but Hermes never auto-schedules them.** Enabling cron is an explicit user action per profile.

---

## open-skills provisioning (both runbooks)

`base/general` and its descendants emit `skills.external_dirs: [~/open-skills/skills]`. Both apply paths provision this checkout by default — the `bootstrap` scripts clone/pull it (skip with `-SkipOpenSkills` / `--skip-open-skills`), and `/finish-setup` runs the same clone. It stays fully tolerated: Hermes silently skips a missing external dir, so runbook success never depends on it. The provisioning command (safe to run manually or re-run):

```powershell
if (Test-Path "$HOME\open-skills") {
  git -C "$HOME\open-skills" pull --ff-only
} else {
  git clone --depth 1 https://github.com/dewdad/open-skills "$HOME\open-skills"
}
```

```bash
if [ -d "$HOME/open-skills" ]; then
  git -C "$HOME/open-skills" pull --ff-only
else
  git clone https://github.com/dewdad/open-skills "$HOME/open-skills"
fi
```

A git or network failure here must not block either runbook.

---

## Getting the repo onto the machine (shell choice + clone-failure fallback)

Both runbooks assume a local checkout with `dist/<persona>/`. The `install.ps1` / `install.sh` entry points create that checkout for you when run standalone (`-Repo` / `--repo`), and they are resilient: each **validates any cached clone** (a half-finished clone is nuked and refetched), **retries** the clone with a low-speed abort, and, if git transport itself is broken, **falls back to downloading the repo archive** (GitHub ZIP on Windows, tarball on POSIX) — the archive URL is derived from the `-Repo` / `--repo` value you pass, never hardcoded.

**Pick the entry point that matches your shell:**

- **Windows PowerShell** — `install.ps1` and the `irm <RAW_REPO_URL>/install.ps1 | iex` one-liner require PowerShell (`powershell.exe` / `pwsh`).
- **Git Bash (Hermes' in-app terminal on Windows), WSL, GitHub Codespaces, macOS/Linux** — use `install.sh`. `powershell.exe` is often **not** on `PATH` inside these shells, so do **not** reach for the `.ps1` one-liner there:

  ```bash
  curl -fsSL <RAW_REPO_URL>/install.sh | bash -s -- <persona> --repo <REPO_GIT_URL> --yes
  ```

**Manual archive fallback (if every automatic path fails).** Download the repo archive in a browser (for a GitHub repo, `<repo-url>/archive/HEAD.zip` or `.../HEAD.tar.gz`), extract it, then point the installer at the extracted folder with `-Repo` / `--repo` (both installers accept a **local folder** there, not just a git URL). Use forward slashes so the path works from Git Bash too:

```powershell
# Windows PowerShell — extracted to C:\Users\me\Downloads\hermes-setup-main
.\install.ps1 il-citizen -Repo 'C:/Users/me/Downloads/hermes-setup-main' -Yes
```

```bash
# Git Bash / WSL / macOS / Linux — extracted folder, forward-slash path
./install.sh il-citizen --repo '/c/Users/me/Downloads/hermes-setup-main' --yes
```

The installer then runs `hermes profile install <extracted-folder>/dist/<persona>` locally — no network needed once the archive is extracted.

---

## Runbook A — Install as a named profile

Use this when you want the persona isolated from the default profile. Every named profile has its own `config.yaml`, `SOUL.md`, `skills/`, and `.env` under `HERMES_HOME/profiles/<name>/`.

### Prompt (paste to the agent)

> You are installing a Hermes profile distribution from `dist/<persona>/` in the current repo as a **named profile**. Do it non-destructively: never overwrite an existing `.env`, never write real secrets into this repo, and resolve `HERMES_HOME` dynamically. After finishing, verify with `hermes -p <profile> config check` and report exactly what changed.

### Steps

1. **Pick the persona** and the profile name. Example: persona `general`, profile name `my-general`. Confirm the persona directory exists:

   ```powershell
   Test-Path .\dist\general\distribution.yaml
   ```

   ```bash
   test -f ./dist/general/distribution.yaml && echo ok
   ```

2. **Run the optional external-skills prep step above** (best-effort, ignore failure).

3. **Install the profile.** `hermes profile install` copies the distribution into `HERMES_HOME/profiles/<name>/`, runs Hermes' own env-var check, skill security scan, and generates `.env.EXAMPLE` inside the new profile:

   ```powershell
   hermes profile install .\dist\general --name my-general --yes
   ```

   ```bash
   hermes profile install ./dist/general --name my-general --yes
   ```

4. **Locate the profile's `.env`.**

   ```powershell
   hermes -p my-general config env-path
   ```

   ```bash
   hermes -p my-general config env-path
   ```

   That is the **only** place real secrets go — never back into the repo.

5. **Create the profile's `.env` from its `.env.EXAMPLE`, only if it does not already exist.** In PowerShell:

   ```powershell
   $envPath = hermes -p my-general config env-path
   $examplePath = Join-Path (Split-Path $envPath) ".env.EXAMPLE"
   if (-not (Test-Path $envPath)) {
     Copy-Item $examplePath $envPath
     Write-Host "Created $envPath — fill in the keys you need."
   } else {
     Write-Host "$envPath already exists — leaving it alone. Diff .env.EXAMPLE against it and report any missing keys."
   }
   ```

   In bash:

   ```bash
   env_path="$(hermes -p my-general config env-path)"
   example_path="$(dirname "$env_path")/.env.EXAMPLE"
   if [ ! -f "$env_path" ]; then
     cp "$example_path" "$env_path"
     echo "Created $env_path — fill in the keys you need."
   else
     echo "$env_path already exists — leaving it alone. Diff .env.EXAMPLE against it and report any missing keys."
   fi
   ```

6. **Verify.** Report the output of both:

   ```powershell
   hermes -p my-general config check
   hermes -p my-general doctor
   ```

   ```bash
   hermes -p my-general config check
   hermes -p my-general doctor
   ```

   Missing provider keys are **warnings, not errors** — they are expected until the user fills in `.env`. Any *config-level* error must be reported and stopped on.

7. **Referenced skills — prefer `/finish-setup`.** This persona authors no skills except one generated onboarding skill: `hermes profile install` lands `meta-skills/finish-setup/SKILL.md`, which Hermes registers as the **`/finish-setup`** slash command. Because `hermes profile install` does **not** auto-install the *referenced* skills, the recommended completion path is to open the profile (`hermes -p my-general`) and run **`/finish-setup`** — it (re)installs everything in `dist/<persona>/skills.install.json` (grouped Tier-0 vs Tier-1), offers optional keys + Tier-1 extras, and health-checks. Alternatively run each `hermes skills install …` / `hermes skills tap add …` line from the README block as-is, or use Runbook B's bootstrap (which auto-installs them). Do **not** invent new skill IDs.

   > **Tier 0 is free to run.** Once the Tier-0 skills install, browser automation + web research/scraping work **keyless**. Free chat runs on the free Nous Portal baseline — the one-time `hermes setup --portal` login (see `PREREQUISITES.md`) **is** the required free baseline. Adding **any one** free-tier provider key is an optional upgrade for higher-quality free models; with no Portal login **and** no key the chain returns HTTP 403. `/finish-setup` walks you through both. Tier-1 (Google Workspace, messaging) is a guided opt-in and never required.

8. **Updates later.** To pick up template changes without touching user-owned files:

   ```powershell
   python -m configurator compile <persona>
   hermes profile update my-general
   ```

   ```bash
   python -m configurator compile <persona>
   hermes profile update my-general
   ```

9. **Report** what changed: profile name, resolved `HERMES_HOME`, whether `.env` was created or preserved, which keys still need values, and both verification outputs.

### Must NOT do (Runbook A)

- Do **not** write real secret values into this repo (not into `dist/`, not into any file under the repo root).
- Do **not** overwrite an existing `.env` in the target profile.
- Do **not** target the profile name `default` — that is Runbook B.
- Do **not** hardcode `HERMES_HOME` — always resolve it via `hermes config path` or the env var.

---

## Runbook B — Apply a persona to the default profile via bootstrap

Use this when you want the persona to *become* your default Hermes install (single-profile setups). The bootstrap script does the same safe merge as Runbook A but targets the default `HERMES_HOME` root instead of a named profile.

### Prompt (paste to the agent)

> You are applying a Hermes profile distribution to the **default** profile using this repo's `bootstrap` script. Preview with `-DryRun` / `--dry-run` first, then apply. Never overwrite an existing `.env`, never write real secrets into this repo. After finishing, verify with `hermes config check` and `hermes doctor` and report exactly what changed.

### Steps

1. **Pick the persona.** Default template is `base/general`; any leaf under `dist/` is valid. Confirm the persona directory exists:

   ```powershell
   Test-Path .\dist\general\distribution.yaml
   ```

   ```bash
   test -f ./dist/general/distribution.yaml && echo ok
   ```

2. **Run the optional external-skills prep step above** (best-effort, ignore failure).

3. **Preview.**

   ```powershell
   .\bootstrap.ps1 -Template general -DryRun
   ```

   ```bash
   chmod +x bootstrap.sh
   ./bootstrap.sh --template general --dry-run
   ```

   The output lists every file that would be written, replaced, or preserved. Read it before proceeding.

4. **Apply.**

   ```powershell
   .\bootstrap.ps1 -Template general
   ```

   ```bash
   ./bootstrap.sh --template general
   ```

   Bootstrap is idempotent and non-destructive. Its guarantees:

   | Target file | Fresh install | Existing install |
   | --- | --- | --- |
   | Safety backup | skipped | `hermes backup` (or zip/tar fallback) |
   | `config.yaml` | written | existing → `config.yaml.bak.<timestamp>`, then replaced |
   | `SOUL.md` | written | **preserved** unless it still contains the unconfigured marker |
   | `skills/` | copied only if the dist ships one | **merged** — other skills never deleted (reference-only personas ship no `skills/`, so this is normally a no-op) |
   | Referenced skills | auto-installed from `skills.install.json` (with your confirmation) | same — `hermes skills install` / `tap add`, failure-tolerant |
   | `~/open-skills` | cloned (bonus catalogue; needs git) | fast-forward pull |
   | `~/multi-gws-cli` | cloned + `npm install` + `npm run build` (Google Workspace CLI; needs Node.js + git) | fast-forward pull + rebuild |
   | `.env` | created from generated `.env.EXAMPLE` | **never overwritten**; missing keys are reported |

   Flags: `-DryRun` / `--dry-run`, `-Force` / `--force`, `-SkipBackup` / `--skip-backup`, `-SkipSkills` / `--skip-skills`, `-SkipOpenSkills` / `--skip-open-skills`, `-SkipGws` / `--skip-gws` (skip the `~/multi-gws-cli` Google Workspace clone+build), `-SkipSkillsInstall` / `--skip-skills-install`, `-Yes` / `--yes` (auto-confirm the referenced-skill install prompt), `-HermesHome PATH` / `--hermes-home PATH`. The template flag is `-Template <name>` / `--template <name>` and defaults to `base/general` — do **not** invent other flag names.

5. **Fill in `.env`.** Bootstrap prints the resolved path. Open it and fill in the keys you need. All `base/general` provider keys are optional — any one is enough.

   ```powershell
   hermes config env-path
   ```

   ```bash
   hermes config env-path
   ```

   Never write real key values anywhere under this repo.

6. **Verify.** Report the output of both:

   ```powershell
   hermes config check
   hermes doctor
   ```

   ```bash
   hermes config check
   hermes doctor
   ```

   If `config check` reports schema drift after a Hermes upgrade, run `hermes config migrate`.

7. **Referenced skills (auto-installed).** Bootstrap already ran the persona's referenced-skill installs from `dist/<persona>/skills.install.json` — `hermes skills install …` / `hermes skills tap add …`, gated by your confirmation (`-Yes` / `--yes` to auto-confirm, `-SkipSkillsInstall` / `--skip-skills-install` to skip) and tolerant of individual failures. To (re)run them manually, use the copy-paste block in `dist/<persona>/README.md`. Do **not** invent skill IDs.

8. **Report** what changed: resolved `HERMES_HOME`, backup path (if any), which files were written/replaced/preserved/skipped, whether `.env` was created or preserved, which keys still need values, and both verification outputs.

### Must NOT do (Runbook B)

- Do **not** write real secret values into this repo.
- Do **not** overwrite an existing `.env`.
- Do **not** delete skills, memories, sessions, `auth.json`, `models.json`, `desktop.json`, or any state DB.
- Do **not** hardcode `HERMES_HOME` — always resolve it dynamically.
- Do **not** invent CLI flags. The bootstrap template flag is `-Template` / `--template`; there is no long-form on PowerShell and no short-form on POSIX.

---

## When to prefer which runbook

- **Runbook A (named profile)** — the safe default. Cleanest, sandboxed, easy to delete with `hermes profile delete <name>`. Use this when trying out a persona, running multiple personas side-by-side, or when the default profile is already configured and in use.
- **Runbook B (default profile via bootstrap)** — use only when you want *this* persona to be the default agent on the machine. Bootstrap is still non-destructive, but it modifies the default profile in place.

Both runbooks leave the repo untouched. Real secrets never leave `HERMES_HOME`.
