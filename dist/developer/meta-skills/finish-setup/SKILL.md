---
description: 'Finish Hermes setup: keys, skills, and discover more.'
metadata:
  hermes:
    category: meta
name: finish-setup
tags:
- setup
- onboarding
---

# Finish setup

Complete this profile: add an optional provider key, install its referenced skills, enable
any Tier-1 extras you want, then health-check. Everything here is optional polish — the
agent already works for free out of the box.

## When to Use

Run `/finish-setup` right after installing this profile (via `hermes profile install` or
Hermes Desktop), or any time you want to add keys, (re)install skills, or discover more.

## Procedure

### 1. Provider keys (optional)

Chat runs on a free, **no-per-call-cost** model chain. Its guaranteed baseline is the
**Nous Portal free plan**: sign up at https://portal.nousresearch.com/manage-subscription
(Free plan — $0, free models only), then log in with `hermes setup --portal`. That alone
switches on free chat. Browser automation and web search are **keyless** and already work.
(Full one-time checklist: PREREQUISITES.md in the hermes-setup repo.)

Adding **any one** of the keys below is optional — it unlocks the higher-tier free models
earlier in the fallback chain. None costs per call:

- **OPENCODE_ZEN_API_KEY** — Primary provider (opencode-zen / big-pickle) — sign in and create/copy a Zen API key at https://opencode.ai/auth.
- **ZENMUX_API_KEY** — Fallback + delegation provider (zenmux / claude-sonnet-5-free / claude-fable-5-free) — top up credits and create a Pay As You Go key at https://zenmux.ai/platform/pay-as-you-go; restrict the key to free models to use only free-tier quota.
- **NVIDIA_API_KEY** — Fallback provider (nvidia / glm-5.2) — generate a NVIDIA Build API key at https://build.nvidia.com/settings/api-keys.
- **GOOGLE_API_KEY** — Vision aux (gemini) — create a Google AI Studio Gemini API key at https://aistudio.google.com/app/apikey. GEMINI_API_KEY also accepted.
- **TELEGRAM_BOT_TOKEN** — Mobile chat surface — create a free bot via @BotFather and paste its token. Tier 1, optional; enables reminders/proactive messages.
- **TELEGRAM_HOME_CHANNEL** — Your Telegram chat id (the bot reports it) — the default delivery target for scheduled reminders.

Set one on the CLI (auto-routed into `.env`, never committed):

```bash
hermes config set OPENCODE_ZEN_API_KEY <your-key>
```

Or run `hermes auth` for a free Nous sign-in. On Desktop / messaging surfaces, add keys via
`hermes setup` or the profile's `.env`.

### 2. Referenced skills

**Tier 0 — free to run, installed on apply.** A working agent depends only on these
(browser automation + web search are keyless). Installed from `skills.install.json`; to
(re)install manually:

- `hermes skills install skills-sh/dewdad/open-skills/web-search-api` — Preferred web search — free SearXNG multi-engine (Google/Bing/DDG/70+). Keyless.
- `hermes skills install skills-sh/dewdad/open-skills/browser-automation-agent` — Browser automation via agent-browser CLI. Free, keyless.
- `hermes skills install skills-sh/dewdad/open-skills/using-web-scraping` — Scrape public web content with headless Chrome. Free, keyless.
- `hermes skills install official/research/duckduckgo-search` — Keyless DuckDuckGo fallback for the `web` toolset when SearXNG instances are down.
- `hermes skills tap add obra/superpowers` — TDD / debugging / git / code-review / planning workflows (adds the tap).
- `hermes skills install skills-sh/garrytan/gstack/gstack` — Browser QA, ship, design-review, scrape.

**Tier 1 — guided opt-in.** Not required; each needs an extra step (a build, OAuth, or
a companion app — e.g. messaging needs the free Beeper Desktop app; see PREREQUISITES.md).
The skill installs automatically; you supply the app/auth. Install only what you want:

- `hermes skills install skills-sh/dewdad/beeper-desktop-api-skill/beeper-desktop-api` — Cross-platform messaging (WhatsApp/iMessage/Telegram/…). Needs the free Beeper Desktop app.

**Local tools.** These install a standalone binary and wire its Hermes plugin. The apply
flow (`bootstrap.ps1` / `bootstrap.sh`) runs them for you; to (re)set one up manually, run
the command for your platform (each is idempotent and safe to re-run):

- **RTK (Rust Token Killer)** — Compresses git/cargo/pytest/docker/... output 60-90% before it reaches the model. Free, keyless, local.

  ```bash
  command -v rtk >/dev/null 2>&1 || curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh; PATH="$HOME/.local/bin:$PATH" rtk init --agent hermes
  ```

  ```powershell
  $d="$env:USERPROFILE\.local\bin"; New-Item -ItemType Directory -Force -Path $d | Out-Null; if (-not (Get-Command rtk -ErrorAction SilentlyContinue)) { $z="$env:TEMP\rtk.zip"; Invoke-WebRequest -Uri https://github.com/rtk-ai/rtk/releases/latest/download/rtk-x86_64-pc-windows-msvc.zip -OutFile $z; Expand-Archive -Path $z -DestinationPath $d -Force }; $env:PATH="$d;$env:PATH"; rtk init --agent hermes
  ```
- **Voice (STT/TTS) dependencies** — Local faster-whisper (STT) + piper-tts (TTS) + ffmpeg for Telegram voice bubbles. Free, keyless.

  ```bash
  python3 -m pip install --user --quiet faster-whisper piper-tts || true; command -v ffmpeg >/dev/null 2>&1 || { command -v brew >/dev/null 2>&1 && brew install ffmpeg; } || echo "note: install ffmpeg (e.g. sudo apt install ffmpeg / sudo dnf install ffmpeg) for Telegram voice bubbles"
  ```

  ```powershell
  python -m pip install --quiet faster-whisper piper-tts; if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { try { winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements } catch { Write-Host "note: install ffmpeg manually for Telegram voice bubbles" } }
  ```

### open-skills catalogue (Tier 0 — provisioned by default)

The flagship open-skills skills already install on apply. This step clones the **full
~40-skill open-skills catalogue** into the referenced external dir so the rest are ready
on first use. It is free and keyless — **do it now** as part of setup. A missing checkout
is tolerated, and re-running only fast-forwards, so this is always safe:

```bash
git clone --depth 1 https://github.com/dewdad/open-skills ~/open-skills \
  || git -C ~/open-skills pull --ff-only
```

Hermes discovers the checkout automatically via `skills.external_dirs` — no restart
needed. (The apply-flow `bootstrap` scripts run this same clone/pull for you.)

### Google Workspace (Tier 1, optional)

Gmail / Calendar / Drive / Docs / Sheets via `multi-gws-cli`. The `bootstrap` apply flow
clones + builds this for you automatically. If you installed via `hermes profile install`
(no bootstrap), build it once yourself — needs Node.js + git (see PREREQUISITES.md):

```bash
git clone https://github.com/dewdad/multi-gws-cli ~/multi-gws-cli
cd ~/multi-gws-cli && npm install && npm run build
```

Then complete the skill's Google OAuth (a Google account is all you need). Hermes picks
up the built external dir automatically. Purely optional — the agent works without it.

### Mobile chat & proactive reminders (Tier 1, optional)

Reach the agent from your phone and let it nudge you proactively — all native Hermes, and
the bot is free. Never required; skip it and the agent still works.

1. **Connect a chat surface.** Create a free Telegram bot with @BotFather, then wire it with
   the native gateway configurator (set `TELEGRAM_BOT_TOKEN` + `TELEGRAM_HOME_CHANNEL` when
   prompted, or in the profile's `.env`):

```bash
hermes gateway setup
```

2. **Let the agent learn you.** It keeps `USER.md` (timezone, working hours, preferred
   channel, standing priorities) via native memory — tell it your preferences once and the
   brief and follow-ups read from there. No extra setup.

3. **Turn on the reminders.** This profile ships proactive jobs **paused**; run the
   scheduler and resume the ones you want (they deliver to the surface from step 1):

```bash
hermes gateway      # run the scheduler daemon
hermes cron resume morning-brief
hermes cron resume followup-sweep
```

### 3. Health check

```bash
hermes config check
hermes doctor
```

### 4. Discover more

Find more skills any time with the built-in registry search:

```bash
hermes skills search <topic>      # e.g. hebrew, pdf, github
hermes skills install <id>        # install one you like
```

Curated catalogues:

- [Skills Hub (skills.sh)](https://skills.sh) — Browse the community + official skill registries Hermes installs from.

## Pitfalls

- Sessions, auth, and memory are **per-profile**. Installing this as a new named profile does
  NOT delete anything — your previous chat history stays in its own profile. If Hermes opens
  a different (near-empty) profile afterward, nothing was wiped: make this one your sticky
  default with `hermes profile use <name>`, or open it directly with `hermes -p <name>`.
- Tier-1 extras (Google apps, messaging) need their own setup and never block a working
  agent — skip them freely.
- Community SearXNG instances can rotate/expire; the DuckDuckGo fallback keeps web search
  working keyless if a preferred instance is down.
- Keys go through `hermes config set` / `.env` only — never paste a key into chat or a file
  that lands in git.

## Verification

- `hermes config check` reports no missing *required* options (all provider keys are
  optional).
- `hermes skills list` shows the Tier-0 skills installed.
- With no key set: a web search returns results and browser automation runs (both keyless).
- After you set one provider key (or run `hermes auth`): a free chat message replies.
