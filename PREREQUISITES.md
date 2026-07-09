# Prerequisites — do these first

Complete this checklist **before** you install a persona from this repo (whether you use
`hermes profile install`, the `bootstrap` script, or Hermes Desktop's in-UI import). Everything
here is free to run — the only cost is a few minutes of registration. When you are done, follow
[`AGENT_SETUP.md`](AGENT_SETUP.md) (or the persona's own `dist/<persona>/README.md`) to install.

> **Free-to-run, not necessarily zero-registration.** Nothing on this list charges you per call.
> The Nous Portal *free* plan asks for a card at sign-up (Stripe verification) but bills **$0** and
> runs **free models only**. Everything else is a plain download or a free account.

| # | Prerequisite | Required? | Why |
| --- | --- | --- | --- |
| 1 | Hermes Agent installed | **Required** | The runtime that loads the persona. |
| 2 | Nous Portal free subscription + login | **Required** | Powers the default free chat chain (`nous / stepfun/step-3.7-flash:free`). |
| 3 | Node.js (LTS) + git | **Required** | `bootstrap` clones + builds the Google Workspace CLI and the open-skills catalogue. |
| 4 | Beeper Desktop app | Optional (Tier 1) | The cross-platform messaging skill talks to the local Beeper Desktop app. |
| 5 | A Google account | Optional (Tier 1) | Google Workspace (Gmail/Calendar/Drive/Docs/Sheets) OAuth, completed after install. |
| 6 | Extra provider API keys | Optional | Unlock the higher-tier *free* models in the fallback chain. |
| 7 | `ffmpeg` (for voice replies) | Optional | Auto-installed best-effort by the apply flow; needed only to render replies as Telegram/Discord *voice bubbles*. Free voice (STT + TTS) is on by default regardless. |

---

## 1. Install Hermes Agent — **required**

Pick one:

- **Desktop app (recommended for non-technical users):** download from
  <https://hermes-agent.nousresearch.com/> and run the installer.
- **Command line:**

  ```powershell
  # Windows (native PowerShell)
  iex (irm https://hermes-agent.nousresearch.com/install.ps1)
  ```

  ```bash
  # Linux / macOS / WSL2 / Termux
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  ```

Verify it is on your PATH:

```bash
hermes --version
```

---

## 2. Nous Portal free subscription + login — **required**

The default model chain every persona inherits ends in a guaranteed-free fallback,
`nous / stepfun/step-3.7-flash:free`, served by **Nous Portal**. Completing the free subscription
and logging in is what makes free chat work out of the box, even before you add any provider API
key.

1. **Sign up and choose a plan.** Open
   <https://portal.nousresearch.com/manage-subscription>, create an account, and select the
   **Free** plan (**$0 / month — free models only**).

   > A credit card is collected at registration (Stripe verification). The Free plan is **not
   > charged** and has **no per-call cost** — it runs free models only. Upgrading to a paid plan is
   > entirely optional and never required by this repo.

2. **Log in from Hermes.** This links your Portal account to the local agent:

   ```bash
   hermes setup --portal
   ```

   It opens your browser for OAuth login, stores a refresh token at
   `HERMES_HOME/auth.json` (never committed anywhere), sets `model.provider: nous`, and turns on
   the Tool Gateway. Alternatively run `hermes auth`, or `hermes model` → *Nous Portal*.

3. **Verify:**

   ```bash
   hermes doctor          # Auth should show "logged in"; Portal should show connected
   ```

Official walkthrough:
<https://hermes-agent.nousresearch.com/docs/guides/run-hermes-with-nous-portal> ·
overview: <https://hermes-agent.nousresearch.com/docs/integrations/nous-portal>.

---

## 3. Node.js (LTS) + git — **required for the apply flow**

The `bootstrap` script provisions two free, local, keyless capabilities that are Node/git builds:

- the **Google Workspace CLI** (`multi-gws-cli`) — cloned and `npm run build`-compiled into
  `~/multi-gws-cli`, and
- the **open-skills catalogue** — cloned into `~/open-skills`.

Install both tools first:

- **Node.js LTS:** <https://nodejs.org/> (bundles `npm`).
- **git:** <https://git-scm.com/>.

Verify:

```bash
node --version
npm --version
git --version
```

> If either is missing, `bootstrap` still succeeds — it just skips that build and prints a warning
> so you can install the tool and re-run. You can also pass `-SkipGws` / `--skip-gws` (skip the
> Google Workspace build) or `-SkipOpenSkills` / `--skip-open-skills` explicitly.

---

## 4. Beeper Desktop app — optional (Tier 1, messaging)

The cross-platform messaging skill (`beeper-desktop-api`) drives the **local Beeper Desktop app**,
so messaging only works once the app is installed, signed in, and running.

1. Download and install Beeper Desktop: <https://www.beeper.com/download>.
2. Create / sign in to a free Beeper account.
3. Connect the chat networks you want (WhatsApp, iMessage, Telegram, Signal, and more) inside the
   app.

The Hermes messaging skill itself is installed automatically by the apply flow — you only need to
provide the app and its account. Skip this entirely if you do not want messaging; the agent works
without it.

---

## 5. A Google account — optional (Tier 1, Google Workspace)

Google Workspace access (Gmail / Calendar / Drive / Docs / Sheets) runs through the `multi-gws-cli`
that the apply flow builds for you (step 3). To actually use it you complete a one-time **Google
OAuth** consent after install — have a Google account ready. `/finish-setup` walks you through the
OAuth step. Optional; the agent works without it.

---

## 6. Extra provider API keys — optional

The agent already chats for free via Nous Portal (step 2). Adding **any one** of these free-tier
keys unlocks the higher-quality free models earlier in the fallback chain — none costs per call, and
none is required. Fill them into `.env` after install (`/finish-setup` or `hermes config set`
routes them for you):

| Key | Where to get it |
| --- | --- |
| `OPENCODE_ZEN_API_KEY` | Sign in and create a Zen API key at <https://opencode.ai/auth>. |
| `ZENMUX_API_KEY` | Create a Pay-As-You-Go key at <https://zenmux.ai/platform/pay-as-you-go> (restrict it to free models). |
| `NVIDIA_API_KEY` | Generate a key at <https://build.nvidia.com/settings/api-keys>. |
| `GOOGLE_API_KEY` | Create a Gemini key at <https://aistudio.google.com/app/apikey> (`GEMINI_API_KEY` also accepted). |

Keys go into `HERMES_HOME/.env` only — never paste a key into chat or into any file under this repo.

---

## 7. Voice — free out of the box (optional extras)

This profile ships **free voice on the default (Tier-0) path** — no key, no subscription:

- **Inbound voice notes** (Telegram, Discord, WhatsApp, Slack, Signal) are transcribed by local
  `faster-whisper` (`stt.provider: local`). STT is **never** a paid-gateway tool.
- **Spoken replies** use the keyless **Edge** TTS voice (`tts.provider: edge`); fully-local **Piper**
  is a documented alternative.
- The apply flow's `voice-deps` setup step installs `faster-whisper`, `piper-tts`, and (best-effort)
  **ffmpeg**. `ffmpeg` is needed only to render replies as Telegram/Discord *voice bubbles*; on Linux
  without Homebrew, install it manually if missing: `sudo apt install ffmpeg` (or
  `sudo dnf install ffmpeg`). Without ffmpeg, replies still send as playable audio files.
- **Hebrew (the `il` locale + IL personas):** STT is pinned to the free **ivrit.ai** Hebrew model and
  TTS to a **he-IL** Edge voice — still fully free/local. For **hybrid Hebrew/English ("Hebrish")**,
  the multilingual default (or a Tier-1 cloud key) transcribes better than the Hebrew-only model.

> **Free vs. paid vs. gateway (important).** Understanding voice notes (STT) and speaking replies
> (TTS) are **free and never require the paid Nous Tool Gateway subscription** — the gateway's TTS
> (OpenAI voices) is only an optional convenience. **Optional Tier-1 upgrades** (each needs its own
> key; none required): a **free-tier Groq** key or a paid **OpenAI** / **ElevenLabs** key for
> higher-quality or code-switching STT/TTS — add with `hermes config set <KEY> <value>`.
> **Telegram** is the recommended first voice channel (richest native voice pipeline).

---

## Next step

With the required items (1–3) done, install a persona:

- **Named profile (recommended, isolated):** see Runbook A in [`AGENT_SETUP.md`](AGENT_SETUP.md).
- **Default profile via bootstrap:** see Runbook B in [`AGENT_SETUP.md`](AGENT_SETUP.md).

After installing, run **`/finish-setup`** in the agent to (re)install referenced skills, complete
optional Tier-1 auth (Google, messaging), and health-check.
