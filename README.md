# hermes-setup

A reproducible, version-controlled configuration for [Hermes Agent](https://hermes-agent.nousresearch.com/docs) by Nous Research. Clone this repo and run **one command** (or hand the [agent runbook](AGENT_SETUP.md) to a coding agent) to configure a fresh Hermes install — or extend an existing one — with the same model/provider setup, personality, and custom skills on any machine.

**You only ever add your own API keys.** Everything else is committed here.

---

## How it works

Hermes keeps *everything* — config, secrets, personality, skills, memory, auth — under a single directory pointed to by the `HERMES_HOME` environment variable:

| Platform | Default `HERMES_HOME` |
| --- | --- |
| Windows (Desktop installer) | `%LOCALAPPDATA%\hermes` |
| Linux / macOS / WSL2 / Termux (shell installer) | `~/.hermes` |
| Anywhere | value of `$HERMES_HOME`, or `hermes config path` → parent dir |

Because Hermes reads secrets **only** from `HERMES_HOME/.env` (config.yaml uses `${VAR}` / `api_key_env:` references, never literal keys), the config is safe to commit. This repo ships the secret-free parts and a bootstrap that drops them into `HERMES_HOME`, creating a `.env` from the template for you to fill in.

```
hermes-setup/
├─ hermes-home/            # mirror of the secret-free parts of HERMES_HOME
│  ├─ config.yaml          # providers, fallback chain, agent/web/vision/auxiliary, platforms
│  ├─ SOUL.md              # global personality / identity
│  └─ skills/              # curated custom (non-bundled) skills
│     ├─ autonomous-ai-agents/hermes-config-maintenance/
│     └─ mlops/{evaluation,inference,models}/...
├─ .env.example            # every env var the config references (no secrets)
├─ bootstrap.ps1           # Windows one-command setup
├─ bootstrap.sh            # Linux/macOS/WSL/Termux one-command setup
├─ AGENT_SETUP.md          # runbook you can paste to any coding agent
└─ .gitignore              # keeps real secrets/state out of git
```

> This config uses providers **opencode_zen** (primary, `big-pickle`), **nvidia_nim**, **nous_portal**, and **google_ai_studio** (vision), a Telegram platform binding, the `firecrawl` web backend, and **no** MCP servers. Adjust `hermes-home/config.yaml`to taste before distributing.

---

## Quick start

### 1. Install Hermes (if not already installed)

```bash
# Linux / macOS / WSL2 / Termux
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

```powershell
# Windows (native)
iex (irm https://hermes-agent.nousresearch.com/install.ps1)
```

Or use the [Desktop installer](https://hermes-agent.nousresearch.com/).

### 2. Bootstrap this config

**Windows (PowerShell):**

```powershell
git clone <this-repo> hermes-setup
cd hermes-setup
.\bootstrap.ps1 -DryRun     # preview — shows exactly what will change
.\bootstrap.ps1             # apply
```

**Linux / macOS / WSL2 / Termux:**

```bash
git clone <this-repo> hermes-setup
cd hermes-setup
chmod +x bootstrap.sh
./bootstrap.sh --dry-run    # preview
./bootstrap.sh              # apply
```

### 3. Add your API keys

The bootstrap creates `HERMES_HOME/.env` from `.env.example` (only if you don't already have one). Open it and fill in the keys you need:

```bash
hermes config env-path      # prints the exact .env path
```

For Nous Portal, you can instead run `hermes setup --portal` (OAuth — one login covers a model plus web search, image gen, TTS, and browser). That stores a refresh token in `HERMES_HOME/auth.json`, no key needed in `.env`.

### 4. Verify & run

```bash
hermes config check         # flags missing/outdated config options
hermes doctor               # full health check
hermes                      # start chatting
```

---

## Bootstrap behavior (safe by design)

Both scripts do the same thing and are **idempotent**:

| Item | On a fresh install | On an existing install |
| --- | --- | --- |
| Safety backup | skipped (nothing to back up) | `hermes backup` (zip), or a tar/zip fallback |
| `config.yaml` | written | existing → `config.yaml.bak.<timestamp>`, then replaced |
| `SOUL.md` | written | preserved if you've customized it; overwrite with `--force` / `-Force` |
| `skills/` | written | **merged** — your other skills are never deleted |
| `.env` | created from template | **never overwritten**; missing template keys are reported |

**Flags:** `--dry-run`/`-DryRun`, `--force`/`-Force`, `--skip-backup`/`-SkipBackup`, `--skip-skills`/`-SkipSkills`, `--hermes-home PATH`/`-HermesHome PATH`.

---

## Configure it via an agent instead

Hand `AGENT_SETUP.md` to any capable agent (including Hermes itself). It performs the identical steps on any platform and reports what changed.

---

## Updating the repo from your live install

When you change your live Hermes config and want to propagate it, re-mirror the secret-free parts back into the repo (from `HERMES_HOME`):

```powershell
# Windows example — adjust $src if your HERMES_HOME differs
$src = $env:HERMES_HOME; if (-not $src) { $src = Split-Path (hermes config path) }
Copy-Item "$src\config.yaml" .\hermes-home\config.yaml -Force
Copy-Item "$src\SOUL.md"     .\hermes-home\SOUL.md -Force
# copy only your custom (non-bundled) skills into .\hermes-home\skills\
```

Then commit. `.gitignore` keeps `.env`, `auth.json`, databases, sessions, memories, and backups out of git.

---

## Notes & caveats

- **Config schema version:** this config targets `_config_version: 33`(Hermes v0.18.x / 2026.7.x). After a Hermes upgrade, run `hermes config check` / `hermes config migrate` to reconcile new options.
- **Secrets hygiene:** never commit a real `.env`. Only `.env.example` is tracked.
- **MCP:** none configured here. Add with `hermes mcp add ...` and document the required env var in `.env.example`.