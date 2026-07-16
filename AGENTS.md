# hermes-setup — DOX root rail

This repository follows [DOX](https://raw.githubusercontent.com/agent0ai/dox/refs/heads/main/AGENTS.md): the `AGENTS.md`
hierarchy is a set of **binding work contracts** for their subtrees. Any agent (including
Hermes editing itself) must obey them.

## Read Before Editing

1. Read this root `AGENTS.md`.
2. Identify every file/folder you will touch.
3. Walk from repo root to each target; read every `AGENTS.md` along the route.
4. If a parent lists a child `AGENTS.md` whose scope contains the path, read that child too.
5. Nearest doc controls local details; parent docs control repo-wide rules. **No child may weaken the secret-hygiene rule below.**

Do not rely on memory — re-read the applicable chain in the current session.

## Update After Editing

Every meaningful change requires a DOX pass before the task is done. Update the closest owning
`AGENTS.md` (and affected parents/children + their Child DOX Index) when a change affects purpose,
scope, ownership, durable structure, contracts, workflows, inputs/outputs, constraints, artifacts,
user preferences, or the existence/index of any `AGENTS.md`. Remove stale text immediately.

## Closeout

Re-check changed paths against the DOX chain, update nearest owning docs + affected parents/children,
refresh every affected Child DOX Index, delete stale text, run `python -m configurator verify`, and
report any docs intentionally left unchanged and why.

---

## What this repo is

`hermes-setup` is a **template compiler**, not an installer. Layered declarative templates
(`base → locale → persona`, single inheritance) are resolved by the `configurator/` Python package
and emitted as native [Hermes](https://hermes-agent.nousresearch.com/docs) **profile distributions**
into `dist/<persona>/`. Hermes' own `hermes profile install/update` then handles apply, updates,
env-var checks, secret hygiene, and skill security scanning — we never reinvent that machinery.

## Project-wide contracts (binding)

- **Guiding principle** — a layman must be able to get a working, capable agent in **one step, for
  free**, then optionally polish it. `hermes-setup` is a **contributor tool**; the layman never runs
  Python (see the layman/Desktop path below). Curated skills stay **free-to-run and local** (no
  per-call paid services on the default path).
- **Two base rails (binding)** — there are exactly two base templates, and **free is always the
  default**:
  - `base/general` — the **free** rail (Tier 0), the bootstrap default, the catalogue-recommended
    base, and the rail every locale/persona compiles against. Every free-path contract below binds
    it and everything that inherits it.
  - `base/general-pro` — an **explicitly-labeled, paid, opt-in** sibling rail powered by a **paid
    Nous Portal subscription** (frontier agentic models + the Nous Tool Gateway; `model.provider:
    nous`, gateway on, OAuth credential — no `${VAR}` key, so `env: []` and a `portal_auth: true`
    template flag drives `/finish-setup`'s login step). It is **never the default**, no free persona
    inherits it, and it is the **one sanctioned place** `use_gateway: true` / paid routing is allowed
    (see the gateway rule below). A **persona is never re-parented** to it; instead the free↔paid
    choice is made **at apply time** — `bootstrap.*`/`install.*` gain a `--portal`/`-Portal` (bootstrap)
    or `--pro`/`-Pro` (install) flag that, after applying a persona's free dist, splices
    `dist/general-pro/config.yaml`'s base-layer keys onto the profile via `hermes config set` and runs
    `hermes auth add nous`. `/finish-setup` offers the same upgrade via the all-in-one `hermes setup
    --portal`. `general-pro` is also installable standalone as a plain Portal agent.
- **Capability tiers (binding)** — capabilities are split by auth friction so the free path stays
  cheap and simple:
  - **Tier 0 — free-to-run, on by default:** free chat on the default model chain — **no per-call
    cost**. Its documented baseline is the **free Nous Portal subscription** ($0 / free-models-only)
    plus a `hermes setup --portal` login — a **required one-time prereq** (see `PREREQUISITES.md`)
    that powers the `nous / stepfun/step-3.7-flash:free` fallback; adding any **one** free-tier
    provider key is optional and unlocks the higher-tier free models (with zero keys AND no Portal
    login the chain returns HTTP 403). Plus **genuinely keyless** browser automation + web
    research/scraping (from `dewdad/open-skills`, no key at all), the free/keyless/local RTK
    token-compressor (a `setup_steps[]` local tool), and **free voice** — inbound voice-note
    transcription via local `faster-whisper` (`stt.provider: local`) and spoken replies via keyless
    `edge` TTS (local Piper/NeuTTS/KittenTTS as offline alternatives), with `ffmpeg` + the STT/TTS
    deps provisioned by a `setup_steps[]` step. Installed on apply. Also the **personal-assistant
    disposition** — a thin `base/general` SOUL fragment (`assistant.md`) that has Hermes anticipate,
    track open loops, remind, and follow up, leaning on native `memory` (`USER.md`) — free and
    always on, inherited by every persona (which tailor only the *domain*, not this modality).
    **A working agent depends ONLY on Tier-0 (free) providers, never Tier-1.**
  - **Tier 1 — guided opt-in:** Google Workspace (`multi-gws-cli` — Node build + OAuth),
    cross-platform messaging (`beeper` — companion app), and the **mobile-chat surface** — a native
    Telegram channel (`env: TELEGRAM_BOT_TOKEN` + `TELEGRAM_HOME_CHANNEL`, a free @BotFather bot)
    that both lets the user reach the agent from a phone AND gives the shipped **proactive reminder
    cron** (`morning-brief` / `followup-sweep`, agent-prompt jobs shipped `enabled: false`) an
    outbound path. The apply flow **provisions** Google + beeper for free (bootstrap clones +
    `npm run build`s `~/multi-gws-cli`; the `beeper` skill auto-installs from `skills.install.json`),
    and `/finish-setup` guides their human auth plus the native `hermes gateway setup` surface wiring
    and `hermes cron resume` for the reminders — never a hardcoded gateway config block (Hermes' own
    configurator owns that schema). Their host prereqs (Node.js + git, the Beeper Desktop app, a
    Google account) live in `PREREQUISITES.md`. Still **never required** for a working agent, never
    on the critical path, never a paid/per-call dependency — they stay inert until the user completes
    the free auth.
- **Reference-only skills (HARD RULE)** — this repo **authors no skill content**. Personas only
  *reference* verified-real skill ids from trusted registries; `dist/<persona>/` ships **no**
  `skills/` directory. Every referenced id MUST be confirmed real with `hermes skills search` /
  `hermes skills inspect` before shipping — no fabricated or placeholder ids. Where no trusted
  registry skill exists for a capability, reference the closest real one or omit it (SOUL still
  shapes behavior) — never author one.
  - **The ONE carve-out** — the compiler generates a single onboarding skill, `finish-setup`
    (`configurator/setup_skill.py`), emitted to `dist/<persona>/meta-skills/finish-setup/SKILL.md`.
    It is *generated infrastructure*, secret-scanned like every artifact, and is the sole exception
    to "authors no skill content". It is deliberately shipped under **`meta-skills/` (NOT `skills/`)**:
    Hermes' `profile_distribution.py` updater wholesale-replaces any shipped top-level dir it copies
    (it is denylist-driven; `distribution_owned` is advisory only in Hermes v0.18.x), so shipping it
    under `skills/` would **wipe the user's installed skills on `hermes profile update`** (proven).
    `config.yaml` references `meta-skills` via a profile-relative `skills.external_dirs` entry so
    Hermes discovers it and registers `/finish-setup`. `dist/` still ships no `skills/`.
- **`/finish-setup` completion command** — Hermes registers every discovered skill as a
  `/slash-command`, so the generated meta-skill is invoked as `/finish-setup`. It walks the user
  through optional provider keys, (re)installs the referenced skills grouped by Tier, offers Tier-1
  opt-ins, runs `config check`/`doctor`, and lists discovery catalogues. It supplements bootstrap and
  is the primary completion path for named-profile / Desktop installs (which don't run bootstrap).
- **In-agent discovery** — templates carry a `discovery[]` list of `{label, url, note}` catalogue
  links (URLs only) merged base→locale and rendered into `/finish-setup`; `locale/il` adds a SOUL
  fragment teaching `hermes skills search`/`install`. `skills-il` has no native Hermes tap, so IL
  discovery is by github-source ids + catalogue links (agentskills.co.il, Claude-Israel), not a tap.
- **IL skills sourced from `skills-il` only** — Israeli skills come exclusively from
  **agentskills.co.il** (GitHub org `skills-il`, MIT, security-scanned), referenced as
  `skills-sh/skills-il/<category-repo>/<skill>`. No IL skill comes from `dewdad/open-skills`.
  Payment-gateway / bank-connector (`tax-and-finance`) skills are excluded (free-to-run).
- **Auto-install at apply** — referenced skills are emitted machine-readably to
  `dist/<persona>/skills.install.json` (and to the README). The apply flow
  (`bootstrap.ps1`/`bootstrap.sh`) auto-runs `hermes skills install <id>` / `hermes skills tap add
  <tap>` for each, gated by the user's confirmation and tolerant of individual failures, so applying
  a persona lands its skills installed **and** Hermes-security-scanned.
- **Zero paid Tool Gateway by default (binding)** — this rule binds `base/general` and the free path;
  the paid `base/general-pro` rail is the **one sanctioned carve-out** (it deliberately sets
  `use_gateway: true` for `web`/`browser`/`image_gen`/`tts` and routes them through the Portal —
  never the default). On the free rail, `base/general` forces every Nous Tool Gateway
  (Portal) tool off the paid gateway (`web`, `browser`, `image_gen`, `tts` all `use_gateway: false`)
  and pins every tool that HAS a free backend to it, so Hermes' "fall back to the gateway when no
  direct key exists" rule can never route a paid call: `web` → keyless DuckDuckGo (`ddgs`), `browser`
  → local Chromium (`local`), and **`tts` → free keyless `edge`** (with local Piper/NeuTTS/KittenTTS
  as offline alternatives). **STT (voice-note transcription) is never a Nous gateway tool at all** —
  it runs on the free local `faster-whisper` (`stt.provider: local`), so inbound voice is free and
  subscription-less. Web + browser + voice are all served free — never the paid gateway. **Only
  `image_gen` ships no free backend**: it stays gateway-off and simply needs a direct key (or the
  paid gateway) if a user ever opts in — never a paid-gateway call on the default, subscription-less
  path.
- **Local-tool provisioning (`setup_steps[]`)** — capabilities that are **not** a `hermes skills
  install` (a standalone binary + a Hermes plugin) are declared as template `setup_steps[]`. The
  compiler generates per-platform `dist/<persona>/setup.steps.{sh,ps1}` (generated infrastructure,
  secret-scanned); the apply flow runs the platform-matched one — gated by confirmation, idempotent
  (a check command skips already-provisioned tools), failure-tolerant — and `/finish-setup` shows the
  manual commands. `base/general` ships **RTK** (`rtk-ai/rtk`, Apache-2.0): a free/keyless/local
  Tier-0 CLI that compresses terminal output 60–90% before it reaches the model, wired via
  `rtk init --agent hermes` into `$HERMES_HOME/plugins/rtk-rewrite/`.
- **Secret hygiene (HARD RULE — no child may weaken it)** — never commit or emit `.env`, `auth.json`,
  `models.json`, `desktop.json`, `state.db*`, `sessions/`, `memories/`, or any literal secret. Emitted
  `config.yaml` references secrets only as `${VAR}` / `key_env`. The compiler **fails the build** on any
  key-shaped literal in emitted output. `ingest` reads the live `config.yaml` **only** — never secrets
  or desktop state.
- **Three-bucket source model** (details in `templates/AGENTS.md` + `locks/AGENTS.md`):
  1. **Vendored + locked (dormant capability)** — retained github/url/well-known fetch + `locks/`
     pinning for genuinely *fetched* real skills if offline reproducibility is ever needed. `local`
     (author-in-repo) is removed. No template uses this today, so `locks/` is empty.
  2. **Referenced live via `skills.external_dirs`** — fast-moving shared checkouts (`~/open-skills/skills`
     bonus layer; `~/multi-gws-cli` Tier-1 Google Workspace clone), never copied into `dist/`; Hermes
     silently skips them if absent. The apply flow (`bootstrap`) provisions both for free by default
     (git clone; `~/multi-gws-cli` also `npm install` + `npm run build` — needs Node.js + git;
     `-SkipOpenSkills` / `-SkipGws` opt out). The compiler also prepends the profile-relative
     `meta-skills` dir.
  3. **Referenced post-install (the DEFAULT path)** — `post_install[]` ids from trusted registries:
     default taps (openai, anthropics, huggingface, NVIDIA, garrytan/gstack), `obra/superpowers`,
     `official/…`, source-available skills (Anthropic docx/pdf/pptx/xlsx), the Tier-0 flagship
     `skills-sh/dewdad/open-skills/*` (browser automation + web research/scraping), and IL
     `skills-sh/skills-il/*`. Never vendored (preserves trust + `NVIDIA/skills` signatures, sidesteps
     redistribution-license issues); the apply flow auto-installs them from `skills.install.json`.
     Entries carry an optional `tier` (0 default / 1 opt-in) that `/finish-setup` groups by.
- **Layman / Hermes-Desktop one-step install** — the layman never touches the compiler. After the
  one-time host setup in `PREREQUISITES.md` (Hermes, free Nous Portal subscription + login, Node.js
  + git), each `dist/<persona>/` is a ready standalone distribution installable in one step from a
  local folder, the user's published git repo, or Hermes Desktop's in-UI import:
  `hermes profile install ./dist/general --name general` (or `<REPO_URL>`). Tier-0's browser
  automation + web research work immediately keyless; free chat runs on the free Nous Portal
  baseline (or any one free-tier key), which `/finish-setup` walks the user through (along with
  Tier-1). Publishing to a concrete repo is a **user/manual step** — no org is hard-coded and no
  implementation depends on it.
- **Agent-pointed-at-repo install (catalogue + one-shot installer)** — so an agent handed a link to
  this repo (even on the weak `stepfun/step-3.7-flash:free` fallback) can list the profiles and
  install a chosen one in **one fetch + one command**, the compiler emits a generated repo-root
  `profiles.json` catalogue (every installable profile's name/description/version, its `dist/<name>`
  path, a ready-to-run `install_command`, and an `agent_instructions` recipe) and the repo ships two
  static, persona-agnostic installers `install.sh` / `install.ps1` (`--list` / `-List`, positional
  `<name>`, `--name`/`--yes`/`--repo`). Because Hermes' `profile install` **cannot** target a repo
  *subdirectory* (it clones the URL root and requires `distribution.yaml` there), the installers do
  the **clone-then-local-install** (`hermes profile install ./dist/<name> --name <name>`), running
  against a local checkout or cloning `--repo`/`$HERMES_SETUP_REPO`. That fetch is **resilient**:
  the installers set `GIT_TERMINAL_PROMPT=0`, validate any cached clone (a corrupt/half clone — a
  `.git` with no `dist/` — is nuked and refetched, never reused), retry the clone with a low-speed
  abort, and if git transport itself is broken fall back to downloading the repo archive (ZIP on
  Windows / tarball on POSIX) whose URL is **derived from the `--repo` value** (GitHub only) — never
  a baked-in org; `--repo` also accepts a **local folder** (a manually extracted archive) so the
  printed remediation actually works offline. `profiles.json` is **generated infrastructure**
  (regenerated by `compile`, secret-scanned, deterministic) and, like the installers, **embeds no
  repo URL / org** — the agent uses the link it was given.
- **Determinism & portability** — emit with stable key ordering so `dist/` diffs cleanly in git.
  Windows-first correctness (paths, UTF-8 with Hebrew content) since this machine is the primary test bed.
- **Config schema** — target `_config_version: 33` (Hermes v0.18.x / 2026.7.x). Custom providers use
  `key_env` (not `api_key_env`). Unknown config keys are **warned, not failed** (live Hermes `config check`
  is lenient). After a Hermes upgrade, run `hermes config check` / `hermes config migrate`.
- **Toolchain** — the `configurator/` package is **stdlib + PyYAML only** so it runs anywhere Hermes runs.
  Tests use stdlib `unittest`; run them with `python -m unittest discover -s tests -p "test_*.py"`
  (bare `python -m unittest` from the repo root discovers nothing — `tests/` is not a top-level
  package). No runtime dependency beyond PyYAML.
- **Live testing safety** — harness runs ONLY against throwaway named profiles; never `default`, never
  empty `-p`, never writes `%LOCALAPPDATA%\hermes\config.yaml`. See `tests/AGENTS.md`.

## User Preferences

- Deliver full, working implementations — no demos, no "extend later", no scope reduction.
- Commit messages carry no AI attribution or `Co-Authored-By` lines.
- Prefer editing existing files over creating new ones; never create docs unless required by the plan.

## Child DOX Index

- `templates/AGENTS.md` — template authoring contract: `template.yaml` schema (incl. `post_install[].tier`,
  `discovery[]`, and `setup_steps[]` local-tool provisioning), single-inheritance + merge semantics
  (`include`/`exclude`, `!remove`, base→locale→persona ordering; `discovery` set-union by url; `setup_steps`
  set-union by id, exclude-by-id), SOUL fragment composition + 20k cap, skill-bucket rules, `env` keys
  `required: false`.
- `configurator/AGENTS.md` — compiler code contract: stdlib + PyYAML only, secret-literal detection fails the
  build (incl. the generated meta-skill + `setup.steps.{sh,ps1}`), `setup_skill.py` builds `/finish-setup`,
  `setup_scripts.py` builds the per-platform setup scripts, `emit.py` writes+scans them under `meta-skills/` /
  distribution root and injects the relative external_dir, `ingest.py` reads `config.yaml` only, deterministic
  emit, per-module responsibility boundaries.
- `dist/AGENTS.md` — generated-output contract: never hand-edit (regenerate via `compile`); committed but
  contains no secrets and no `skills/` content (reference-only); ships one generated `meta-skills/finish-setup/`
  (the carve-out) + `skills.install.json` for auto-install + `setup.steps.{sh,ps1}` when `setup_steps[]` present.
- `locks/AGENTS.md` — lockfile provenance contract: `source_id`, `resolved_commit_or_hash`, `fetched_at`,
  `license`, `redistributable`; `--update-locks` is the only writer.
- `tests/AGENTS.md` — harness safety contract: throwaway named profiles only; never target `default`/empty
  `-p`; never write `%LOCALAPPDATA%\hermes\config.yaml`; teardown via try/finally.
