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

Complete this profile: log in to your paid Nous Portal subscription, install its
referenced skills, enable any Tier-1 extras you want, then health-check. The Portal
login is required — it powers both the models and the Tool Gateway.

## When to Use

Run `/finish-setup` right after installing this profile (via `hermes profile install` or
Hermes Desktop), or any time you want to add keys, (re)install skills, or discover more.

## Procedure

### 1. Nous Portal login (required)

This profile is powered by a **paid Nous Portal subscription** — frontier agentic models
plus the Nous Tool Gateway (web search, image generation, TTS, browser automation) through
one OAuth login, with no per-tool API keys. It requires a **paid** Portal plan (the free
plan runs free models only). Full checklist: PREREQUISITES.md in the hermes-setup repo.

1. Subscribe to a paid plan at https://portal.nousresearch.com/manage-subscription.
2. Log in and wire the provider + Tool Gateway in one step:

```bash
hermes setup --portal
```

This sets Nous as your inference provider, turns on the Tool Gateway, and stores an OAuth
refresh token at `~/.hermes/auth.json` (no keys in `.env`). Verify with `hermes portal info`.

### 2. Referenced skills


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

- [Nous Portal](https://portal.nousresearch.com) — Your subscription — models, Tool Gateway routing, usage, and billing.
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
