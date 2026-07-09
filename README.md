# hermes-setup

<!-- AGENT-INSTALL:START -->
> **AGENT INSTRUCTIONS (read first if you are an AI agent given this repo's URL and asked to set up / install a Hermes profile):**
>
> 1. **Fetch the catalogue:** `<REPO_RAW_BASE>/profiles.json` — where `<REPO_RAW_BASE>` is this repo's raw-content base (for GitHub, turn `https://github.com/<owner>/<repo>` into `https://raw.githubusercontent.com/<owner>/<repo>/<default-branch>`; this repo → `https://raw.githubusercontent.com/dewdad/hermes-setup/main`).
> 2. **List & pick:** show the user the `profiles[]` entries (`name` + `description`) and ask which one.
> 3. **Install the chosen `<name>`:** run that entry's `standalone_posix_command` (macOS/Linux) or `standalone_windows_command` (Windows), replacing `<RAW_REPO_URL>` with `<REPO_RAW_BASE>` and `<REPO_GIT_URL>` with this repo's git URL. If you are *already inside a local clone*, run `local_install_command` instead.
> 4. **Finish:** tell the user to open the profile (`hermes -p <name>`) and run `/finish-setup`.
>
> `profiles.json` also carries an `agent_instructions` field with this same recipe. Do **not** run `hermes profile install` against a repo-subdirectory URL — it only accepts a repo ROOT or a LOCAL folder; the standalone command clones for you. Full details: [For an AI agent pointed at this repo](#for-an-ai-agent-pointed-at-this-repo).
<!-- AGENT-INSTALL:END -->

A **template compiler** for [Hermes Agent](https://hermes-agent.nousresearch.com/docs) by Nous Research. Author personas as layered declarative templates, compile them into native Hermes **profile distributions**, and apply them anywhere Hermes runs.

This repo is *not* an installer. Hermes' own `hermes profile install/update` handles apply, updates, env-var checks, secret hygiene, and skill security scanning — we don't reinvent that.

---

## For everyone — one-step install (no terminal, no Python)

You do **not** need this repo's compiler, Python, or any developer tooling to *use* a persona. The
compiler is a **contributor tool**; a compiled distribution under `dist/<persona>/` is a ready,
standalone Hermes profile you install in one step and use for free.

> **Do the one-time prerequisites first.** Before installing a persona, work through
> **[`PREREQUISITES.md`](PREREQUISITES.md)** — install Hermes, complete the **free Nous Portal
> subscription** + `hermes setup --portal` login (the baseline that powers free chat), and install
> **Node.js + git** (the apply flow builds the Google Workspace CLI). Beeper Desktop and a Google
> account are optional Tier-1 extras. Everything on the list is free to run.

1. **Install Hermes** — [Desktop installer](https://hermes-agent.nousresearch.com/) (recommended for
   non-technical users), or the one-line CLI installer under *Quick start* below.
2. **Install the `general` profile in one step** — from the user's published repo, a local folder, or
   (if your Hermes Desktop build supports it) the in-UI "install profile from git/URL" import:

   ```bash
   hermes profile install <REPO_URL> --name general      # once someone publishes dist/general
   hermes profile install ./dist/general --name general  # or straight from a local folder
   ```

3. **Turn on free chat with one key (or a free sign-in).** Chat runs on a free, no-per-call-cost
   model chain, but it needs **one** free-tier provider key — or a free Nous sign-in via
   `hermes auth`. Browser automation and web research/scraping (SearXNG + DuckDuckGo) are **genuinely
   keyless** and install on apply, so those work before you add anything.
4. **Run `/finish-setup`** in the chat — it walks you through setting that one free key (or sign-in),
   (re)installs the referenced skills, offers Tier-1 extras (Google Workspace, messaging), and lists
   more skills to discover. Everything beyond the one chat key is optional.

> **Capability tiers.** *Tier 0* is **free to run** (no per-call cost): free chat needs **one** free
> key or a `hermes auth` sign-in, while browser automation + web research are **keyless**. A working
> agent depends only on Tier-0 (free) providers. *Tier 1* (Google Workspace via `multi-gws-cli`,
> messaging via `beeper`) is a guided opt-in through `/finish-setup` and is never required.

### Free (default) or paid Nous Portal — your choice per install

The free chain above is the default for **every** persona. If you have a **paid
[Nous Portal](https://portal.nousresearch.com) subscription**, you can instead run any persona on the
Portal — frontier agentic models plus the Nous Tool Gateway (web, image, TTS, browser) through one
OAuth login, no per-tool API keys. Two ways:

- **Any persona, in paid mode** — add `--pro` (named-profile install) or `--portal` (bootstrap):

  ```bash
  ./install.sh developer --pro --yes         # POSIX;  installs developer, then applies the Portal base
  .\install.ps1 developer -Pro -Yes          # Windows
  ./bootstrap.sh --template developer --portal   # apply to the default profile in paid mode
  ```

  This installs the persona's free distribution, then splices the Nous Portal base-layer config onto
  it (`hermes config set`) and runs the Portal OAuth login (`hermes auth add nous`). Or, from inside
  the agent, run `/finish-setup` and follow its **"Upgrade to Nous Portal"** step (`hermes setup
  --portal`).

- **A plain Portal general agent** — install the `general-pro` base directly:

  ```bash
  hermes profile install ./dist/general-pro --name general-pro
  ```

> Paid mode requires a **paid** Nous Portal plan (the free plan runs free models only). See
> [`PREREQUISITES.md`](PREREQUISITES.md).

Everything below is the **contributor** workflow for authoring and compiling personas.

---

## For an AI agent pointed at this repo

Hand an agent — even a small model like the free `stepfun/step-3.7-flash:free` — a link to this
repo and ask it to set you up, and the reliable flow is **one fetch + one command**: no
repo-subdirectory install (Hermes can't do that), no multi-step reasoning.

1. **Fetch the catalogue.** [`profiles.json`](profiles.json) at the repo root is a generated,
   machine-readable index of every installable profile — `name`, `kind`, `description`, `version`,
   the `dist/<name>` path, and three ready-to-run commands (`local_install_command`,
   `standalone_posix_command`, `standalone_windows_command`) — plus an `agent_instructions` string
   the model follows verbatim. One raw-URL fetch gives the agent the whole list:

   ```
   <RAW_REPO_URL>/profiles.json    # e.g. https://raw.githubusercontent.com/<owner>/hermes-setup/main/profiles.json
   ```

2. **List and pick.** The agent shows the `profiles[]` entries and asks which one you want.

3. **Install the choice.** `hermes profile install` **cannot** target a repo *subdirectory* (it
   clones the URL root and needs `distribution.yaml` there), so installation always runs from a
   **local clone**. Two cases:

   - **Already inside a clone** → run the profile's `local_install_command`, i.e. the bundled
     installer:

     ```bash
     ./install.sh <name> --yes          # POSIX;  --list to list; --name / --repo also supported
     ```

     ```powershell
     .\install.ps1 <name> -Yes          # Windows; -List, -Name, -Repo
     ```

   - **Standalone (no checkout yet)** → run the profile's `standalone_posix_command` /
     `standalone_windows_command`, which clone the repo for you (substitute the URLs of *this* repo):

     ```bash
     curl -fsSL <RAW_REPO_URL>/install.sh | bash -s -- <name> --repo <REPO_GIT_URL> --yes
     ```

     ```powershell
     $p=Join-Path $env:TEMP 'hermes-setup-install.ps1'; irm <RAW_REPO_URL>/install.ps1 -OutFile $p; & $p <name> -Repo <REPO_GIT_URL> -Yes
     ```

   `--yes` / `-Yes` skips the Hermes confirmation prompt (recommended for unattended agent runs).

4. **Finish.** Open the profile (`hermes -p <name>`) and run `/finish-setup` to add a free key and
   install its skills.

`profiles.json` and both installers are persona-agnostic and hard-code **no** repo URL — the agent
uses the link you gave it. `profiles.json` is regenerated by `compile`, so it never drifts from
`dist/`.

---

## What it is

Templates live under `templates/` and are resolved through a strict **single-inheritance chain**:

```
templates/base/general   ──►   templates/locale/il   ──►   templates/persona/il-legal
```

The `configurator/` Python package (stdlib + PyYAML only) walks that chain, deep-merges the fragments, composes SOUL fragments, resolves the skill sources, and emits each **leaf** template as a standard Hermes profile distribution into `dist/<persona>/`. Every emitted distribution contains exactly what `hermes profile install` expects:

```
dist/<persona>/
├─ distribution.yaml     # name, version, hermes_requires, env_requires (drives .env.EXAMPLE)
├─ config.yaml           # _config_version: 33; secrets only as ${VAR} / key_env references
├─ SOUL.md               # composed from ordered fragments, ≤ 20,000 chars
├─ skills.install.json   # machine-readable referenced-skill list the apply flow auto-installs
├─ cron/*.json           # emitted, but Hermes never auto-schedules distribution cron
├─ .env.EXAMPLE          # auto-generated from env_requires (no real secrets)
├─ .no-bundled-skills    # present when skills.bundled: none
├─ .gitignore
└─ README.md             # install steps + auto-installed referenced-skill block
```

> **Reference-only:** distributions ship **no `skills/` directory**. This repo authors no skill
> content — personas only *reference* verified-real skill ids from trusted registries, which the
> apply flow installs via `hermes skills install`.

### Three-bucket skill source model

This repo **authors no skill content**. Personas only *reference* verified-real skill ids from
trusted registries — every id is confirmed with `hermes skills search` / `hermes skills inspect`
before it ships (no fabricated ids). Skills are sourced three ways. This is a **binding project
contract** (see the root `AGENTS.md`):

| Bucket | Where it lives | When to use it |
| --- | --- | --- |
| **1. Vendored + locked (dormant capability)** | Copied into `dist/<persona>/skills/…`, pinned by content hash in `locks/<template>.lock.json`. | Retained github/url/well-known fetch for genuinely *fetched* real skills if offline reproducibility is ever needed. **No template uses this today** (so `locks/` is empty); authoring skills in-repo (`source: local`) is removed. |
| **2. Referenced live via `skills.external_dirs`** | *Not* copied. Emitted as a path in `config.yaml` (e.g. `~/open-skills/skills`). Hermes **silently skips** the entry if the directory does not exist. | Fast-moving shared checkouts shared across every profile (e.g. `dewdad/open-skills`). One git checkout, no duplication. |
| **3. Referenced post-install (the default path)** | Not vendored. Listed in `dist/<persona>/skills.install.json` and the README; the apply flow auto-runs `hermes skills install …` / `hermes skills tap add …`. | Default taps (`openai`, `anthropics`, `huggingface`, `NVIDIA`, `garrytan/gstack`), `obra/superpowers`, `official/…`, and source-available skills (Anthropic `docx/pdf/pptx/xlsx`). Preserves each tap's built-in trust and `NVIDIA/skills`' signatures, and sidesteps redistribution-license issues. |

Where no trusted-registry skill exists for a capability, the persona references the closest real
skill or omits it — the SOUL fragments still shape behavior. The compiler **fails the build** if a
`redistributable: false` skill is ever vendored into `dist/` instead of referenced post-install.

### Secret hygiene (hard rule)

- `config.yaml` uses only `${VAR}` / `key_env` references — never literal keys.
- The compiler scans emitted output for key-shaped literals and fails the build on any hit.
- `.env`, `auth.json`, `models.json`, `desktop.json`, `state.db*`, `sessions/`, `memories/`, and every real secret **never** enter the repo or `dist/`.
- Real secrets live in `HERMES_HOME/.env`, which is per-machine and not committed. `.env.EXAMPLE` (secret-free) ships inside each distribution.

---

## Quick start (contributors — compiling from templates)

> If you just want to *use* a persona, see **For everyone — one-step install** above; you do not
> need any of the steps in this section.

### 1. Install Hermes (once per machine)

```powershell
# Windows (native)
iex (irm https://hermes-agent.nousresearch.com/install.ps1)
```

```bash
# Linux / macOS / WSL2 / Termux
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

Or use the [Desktop installer](https://hermes-agent.nousresearch.com/).

### 2. Clone this repo and list templates

The compiler needs **Python 3.11+** and its single runtime dependency, **PyYAML** (nothing else):

```bash
python -m pip install "PyYAML>=6.0"   # or: pip install -e .
```

```powershell
git clone <this-repo> hermes-setup
cd hermes-setup
python -m configurator list
```

```bash
git clone <this-repo> hermes-setup
cd hermes-setup
python -m configurator list
```

### 3. Compile a distribution

Compile every leaf template into `dist/`:

```powershell
python -m configurator compile --all
```

Or compile one template by name:

```powershell
python -m configurator compile general
```

Compile is deterministic — repeated runs produce identical bytes, so `dist/` diffs cleanly in git.

### 4. Apply a persona to a Hermes profile

You have two options.

**(a) Install as a named profile (recommended — isolated).**

```powershell
hermes profile install .\dist\general --name my-general --yes
hermes -p my-general config check
hermes -p my-general
```

```bash
hermes profile install ./dist/general --name my-general --yes
hermes -p my-general config check
hermes -p my-general
```

Then fill in the keys Hermes prompts for (all provider keys are optional — any single key yields a working agent). Hermes writes the profile's real `.env` under its own `HERMES_HOME` — the repo never sees your secrets.

**(b) Apply to the default profile via bootstrap (idempotent, non-destructive).**

```powershell
.\bootstrap.ps1 -Template general -DryRun    # preview
.\bootstrap.ps1 -Template general
```

```bash
chmod +x bootstrap.sh
./bootstrap.sh --template general --dry-run   # preview
./bootstrap.sh --template general
```

Bootstrap default template is `base/general`. It backs up, swaps `config.yaml` with `.bak`, preserves SOUL unless it carries the unconfigured marker, merges skills (never deletes others), and creates `.env` from `.env.EXAMPLE` **only if it does not already exist**.

See `AGENT_SETUP.md` for the full step-by-step runbook (both flows) that a coding agent can follow.

### 5. The shared open-skills checkout (provisioned for you)

`base/general` emits `skills.external_dirs: [~/open-skills/skills]`. **You normally don't run this by hand** — both apply paths provision it for first use: the `bootstrap` scripts clone/pull it by default (skip with `-SkipOpenSkills` / `--skip-open-skills`), and `/finish-setup` walks the agent through the same clone. It stays fully tolerated — Hermes silently skips a missing external dir, so a git/network failure never breaks the agent. To provision or refresh it manually:

```powershell
git clone --depth 1 https://github.com/dewdad/open-skills $HOME\open-skills
# or refresh an existing checkout:
git -C $HOME\open-skills pull --ff-only
```

```bash
git clone --depth 1 https://github.com/dewdad/open-skills ~/open-skills
git -C ~/open-skills pull --ff-only
```

Every distribution also emits `cron/open-skills-sync.json` for a daily fast-forward pull. Hermes **never auto-schedules** distribution cron; enable it explicitly per profile if you want it.

---

## Template authoring guide

Templates are the source of truth. See `templates/AGENTS.md` for the full authoring contract — `template.yaml` schema, merge semantics (`include` / `exclude` / `!remove`, base → locale → persona ordering), SOUL fragment composition + 20k cap, skill-bucket rules, and the requirement that every `env:` entry be `required: false` so a single provider key yields a working agent.

Skeleton:

```yaml
name: my-persona
kind: persona                 # base | locale | persona
extends: locale/il            # single inheritance; chain resolved root-first
distribution:
  description: "…"
  version: 1.0.0
  license: MIT
config:                       # deep-merged config.yaml fragment (_config_version: 33)
  model: { provider: zenmux, default: anthropic/claude-sonnet-5-free }
env:
  - { name: ZENMUX_API_KEY, description: "primary provider", required: false }
soul:
  fragments: [identity.md, style.md, scope.md]
skills:
  bundled: none
  external_dirs: [~/open-skills/skills]     # bucket 2 — live shared checkout
  exclude: [name-from-parent]               # prunes inherited include[] AND post_install[] by name
post_install:                               # bucket 3 (default path) — verified-real ids only
  - { id: skills-sh/anthropics/skills/docx, note: "Word docs. Source-available; free to run." }
  - { id: obra/superpowers, tap: true, note: "Dev workflow skills (adds the tap)." }
```

Every `post_install` id must be confirmed real with `hermes skills search` / `hermes skills inspect`
before it ships. The apply flow auto-installs them from the emitted `skills.install.json`.

### Extending and locking

- Add a new persona by creating `templates/persona/<name>/template.yaml` with `extends:` pointing at any existing base or locale.
- Reference skills via `post_install[]` (verified-real ids only). `locks/` is **empty** under the reference-only model — it only fills if a template ever uses the dormant github/url/well-known vendoring capability. In that case, refresh with:

  ```powershell
  python -m configurator update-locks
  ```

  This is the **only** writer of `locks/` (it also prunes orphan lockfiles when a template vendors nothing).
- After any template or lockfile edit, run:

  ```powershell
  python -m configurator verify
  ```

  which validates schemas, checks the DOX chain, and re-scans `dist/` for secret literals.

### Publishing a persona

Every leaf under `dist/<persona>/` is already a valid Hermes profile distribution. To publish one standalone so others can install it directly from git:

1. Copy `dist/<persona>/` out to its own git repo (or use `git subtree split`).
2. Push it to GitHub / any git host.
3. Anyone can then install it with:

   ```powershell
   hermes profile install github.com/you/<persona> --name <profile>
   ```

The distribution stays small, its referenced-skill list ships in its own `skills.install.json` + README, and Hermes handles updates via `hermes profile update`.

---

## Updating templates from a live install (`ingest`)

The old "re-mirror `hermes-home/` from your live install" flow is **gone**. To propagate changes from a live Hermes profile back into this repo:

```powershell
python -m configurator ingest
# or for a specific profile:
python -m configurator ingest --profile my-general
```

`ingest` reads the **live `config.yaml` only** — never `.env`, `auth.json`, `models.json`, `desktop.json`, or any desktop/session state. It diffs the live config against the resolved `base/general` config and prints a reviewable drift diff. Nothing is written automatically; fold the meaningful drift back into the appropriate template by hand, then recompile.

---

## Config schema & upgrades

- Target: `_config_version: 33` (Hermes v0.18.x / 2026.7.x).
- Custom providers use `key_env` (not `api_key_env`).
- Unknown config keys are **warned, not failed** — live Hermes `config check` is lenient.
- After a Hermes upgrade, on each profile you use:

  ```powershell
  hermes -p <profile> config check
  hermes -p <profile> config migrate
  ```

---

## `base/general` — the 0-cost default chain

`base/general` reproduces a free, no-lock-in model chain that every persona inherits by default:

- **Primary:** `opencode-zen / big-pickle` (128k context; opencode-zen is a built-in provider)
- **Fallbacks (quality-first, throughput-last):** `nvidia/glm-5.2` → `zenmux / anthropic/claude-sonnet-5-free` → `nous / stepfun/step-3.7-flash:free`
- **Vision aux:** `gemini/gemini-3.1-flash` with a nous free fallback

Four independent providers, every provider key `required: false` — **any one key yields a working agent** with no per-call paid services on the default path.

## `base/general-pro` — the paid Nous Portal chain (opt-in)

`base/general-pro` is the **paid** sibling rail — never the default, never inherited by a free
persona. It mirrors exactly what `hermes setup --portal` writes:

- **Inference:** `model.provider: nous` on `https://inference-api.nousresearch.com/v1`, default
  `anthropic/claude-sonnet-4.6` (a frontier *agentic* model — deliberately **not** Hermes-4, which is
  chat/reasoning-tuned), with a `nous / stepfun/step-3.7-flash:free` free floor.
- **Nous Tool Gateway on (`use_gateway: true`):** `web` (Firecrawl) · `browser` (Browser Use) ·
  `image_gen` (FAL) · `tts` (OpenAI TTS) — this is the one base allowed to route through the paid
  gateway.
- **Credential:** the Portal OAuth token (`hermes setup --portal` → `~/.hermes/auth.json`), not an
  API key — so it declares `env: []` and its `/finish-setup` walks the OAuth login instead of keys.

Use it standalone (`hermes profile install ./dist/general-pro --name general-pro`) or apply any
persona in paid mode with `--pro` / `--portal` (see *Free or paid* above). Requires a **paid** Nous
Portal plan.

---

## Repository layout

```
hermes-setup/
├─ AGENTS.md              # DOX root rail — project-wide binding contracts (contributor/agent facing)
├─ AGENT_SETUP.md         # end-user install runbook (see below)
├─ README.md              # this file
├─ templates/             # authoring surface — base / locale / persona
│  └─ AGENTS.md           # template authoring contract
├─ configurator/          # Python compiler package (stdlib + PyYAML only)
│  └─ AGENTS.md           # compiler code contract
├─ dist/                  # generated distributions — never hand-edit
│  └─ AGENTS.md           # generated-output contract
├─ locks/                 # pinned skill sources — only --update-locks may write here
│  └─ AGENTS.md           # lockfile provenance contract
├─ tests/                 # compiler + live-harness tests
│  └─ AGENTS.md           # harness safety contract
├─ bootstrap.ps1          # apply a dist to the default profile (Windows)
├─ bootstrap.sh           # apply a dist to the default profile (POSIX)
├─ install.ps1            # list + install a named profile from dist/ (Windows; agent entry point)
├─ install.sh             # list + install a named profile from dist/ (POSIX; agent entry point)
├─ profiles.json          # generated catalogue of installable profiles (single-fetch agent index)
└─ .gitignore
```

---

## The docs — who reads what

| Document | Audience | Purpose |
| --- | --- | --- |
| `PREREQUISITES.md` | **Anyone before installing a persona** | The one-time host setup checklist: install Hermes, complete the free Nous Portal subscription + login, install Node.js + git, and the optional Beeper / Google extras. Do this first. |
| Root `AGENTS.md` | **Contributors and coding agents editing this repo** | The DOX rail — binding work contracts for the source tree (secret hygiene, three-bucket model, determinism, config schema, per-directory child rails). |
| `AGENT_SETUP.md` | **End users and agents installing a persona** | Two step-by-step runbooks (named profile via `hermes profile install`; default profile via `bootstrap`). Does not describe how to change the source tree. |
| `dist/<persona>/README.md` | **Someone installing this specific persona** | Install command, `.env.EXAMPLE` pointer, and the referenced-skill `hermes skills install …` block (auto-installed by the apply flow) for that persona. |

If you are installing a persona, start at `PREREQUISITES.md`, then `AGENT_SETUP.md` or the per-distribution README. If you are extending this repo, start at root `AGENTS.md`.

---

## Notes

- Every emitted distribution ships `cron/*.json` when the template declares cron. **Hermes never auto-schedules distribution cron** — you must enable it explicitly per profile.
- The compiler is stdlib + PyYAML only. No runtime dependency beyond PyYAML, so it runs anywhere Hermes runs.
- Windows-first correctness (paths, UTF-8 with Hebrew content) is a project contract; POSIX equivalents are always documented alongside.
