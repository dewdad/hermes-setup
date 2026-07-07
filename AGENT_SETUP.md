# Agent Runbook — Configure Hermes Agent from this repo

This file is a **prompt you can hand to any capable coding agent** (Hermes itself,
Claude, Codex, etc.) to configure a Hermes Agent installation from this repo
without running the bootstrap script by hand. Paste the "Prompt" section to the
agent, or point the agent at this file.

The script (`bootstrap.ps1` / `bootstrap.sh`) is the source of truth; this runbook
performs the same steps manually so an agent can do it on any platform.

---

## Prompt (paste this to the agent)

> You are configuring a Hermes Agent installation from the repo in the current
> directory. Do it **idempotently and non-destructively** following the steps
> below. Never overwrite an existing `.env`. Back up before replacing anything.
> After finishing, verify with `hermes config check` and `hermes doctor` and
> report what changed.

---

## Facts the agent must know

- **Everything lives under one directory: `HERMES_HOME`.** Resolve it in this order:
  1. `$HERMES_HOME` environment variable, if set.
  2. `hermes config path` → the parent directory of the printed path.
  3. Platform default: Windows Desktop installer → `%LOCALAPPDATA%\hermes`;
     shell installer → `~/.hermes`.
  Confirm with `hermes config path` and `hermes config env-path`.
- **Secrets never live in `config.yaml`.** They are `${VAR}` / `api_key_env`
  references resolved from `HERMES_HOME/.env`. That is what makes `config.yaml`
  safe to version-control.
- The repo mirrors the secret-free parts of `HERMES_HOME` under `hermes-home/`:
  - `hermes-home/config.yaml` — model providers, fallback chain, agent/web/vision/auxiliary, platforms.
  - `hermes-home/SOUL.md` — global personality/identity.
  - `hermes-home/skills/<category>/<skill>/SKILL.md` — curated custom skills.
- `.env.example` lists every environment variable the config references.

## Steps

1. **Resolve `HERMES_HOME`** (see above) and ensure the directory exists.
2. **Back up** the current home: run `hermes backup` (writes a zip). If the CLI is
   unavailable, zip/tar `HERMES_HOME` to a temp location. Skip if it's a fresh install.
3. **config.yaml**: if `HERMES_HOME/config.yaml` exists, copy it to
   `config.yaml.bak.<timestamp>` first, then copy `hermes-home/config.yaml` over it.
4. **SOUL.md**: copy `hermes-home/SOUL.md` to `HERMES_HOME/SOUL.md` **only if** the
   target is missing or still contains the literal marker `<!-- UNCONFIGURED -->`.
   If the target is customized, leave it and say so.
5. **skills**: for each `SKILL.md` under `hermes-home/skills/`, copy its whole
   folder (with `references/`, `scripts/`, etc.) to the matching path under
   `HERMES_HOME/skills/`, preserving the `<category>/<skill>` layout. Merge — do not
   delete other skills already present.
6. **.env**: if `HERMES_HOME/.env` does **not** exist, copy `.env.example` there and
   tell the user to fill in their keys. If it **does** exist, do not touch it —
   instead diff the keys and report any key present in `.env.example` but missing
   from the user's `.env`.
7. **Verify**: run `hermes config check`; if it reports missing/outdated options,
   run `hermes config migrate`. Then run `hermes doctor`. Report results.
8. **Report**: list exactly which files were written/backed up/skipped, the
   resolved `HERMES_HOME`, and any `.env` keys the user still needs to provide.

## Must NOT do

- Do **not** write real secret values anywhere in the repo.
- Do **not** overwrite an existing `.env`.
- Do **not** delete skills, memories, sessions, or `auth.json`.
- Do **not** hardcode a `HERMES_HOME` path — always resolve it dynamically.

## Extending an existing install (optional follow-ups)

- Add an MCP server: `hermes mcp add <name> --command <cmd> --args <...>` or
  `hermes mcp add <name> --url <endpoint>`; then `hermes mcp test <name>`.
  (This config ships with **no** MCP servers configured.)
- Install more skills: `hermes skills search <q>` / `hermes skills install <source/id>`.
- Change the model/provider: `hermes model` or edit `model.provider` / `model.default`
  in `config.yaml`, then `hermes config check`.
