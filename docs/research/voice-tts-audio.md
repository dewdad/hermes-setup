# Research: Voice, TTS & Audio for Hermes personas

**Status:** research / decision-input (not a binding contract). **Date:** 2026-07-09.
**Scope:** How `hermes-setup` personas can support voice notes (inbound), spoken replies
(outbound TTS), dictation, and meeting participation — with **Hebrew** and **hybrid
Hebrew/English ("Hebrish")** support — classified strictly by cost/licensing tier.

> **Why this doc exists.** The central question is *not* "can Hermes do voice" (it can, natively)
> but **"which voice features are free/local/open vs. which require the paid Nous Tool Gateway
> subscription vs. a paid third-party key."** That distinction drives what `base/general` (Tier 0,
> free) may enable by default vs. what belongs in a Tier-1 guided opt-in.

## Provenance / how this was verified

- **Hermes Tool Gateway** — <https://hermes-agent.nousresearch.com/docs/user-guide/features/tool-gateway> (fetched 2026-07-09).
- **Hermes Voice & TTS** — <https://hermes-agent.nousresearch.com/docs/user-guide/features/tts> (fetched 2026-07-09).
- **Hermes Voice Mode** — <https://hermes-agent.nousresearch.com/docs/user-guide/features/voice-mode>.
- Repo cross-check: [`templates/base/general/template.yaml`](../../templates/base/general/template.yaml),
  [`dist/general/config.yaml`](../../dist/general/config.yaml), [`PREREQUISITES.md`](../../PREREQUISITES.md),
  root [`AGENTS.md`](../../AGENTS.md).
- Hebrew ASR/TTS + budget-cloud + meeting-bot landscape: web research (2026-07), sources listed at the end.

---

## TL;DR

1. **Hermes ships production-grade native voice.** Inbound voice messages on Telegram/Discord/
   WhatsApp/Slack/Signal are auto-transcribed (STT) and injected as text; replies are delivered as
   TTS voice bubbles. `hermes-setup` currently does **not** enable any of this.
2. **Speech-to-text never requires the paid gateway.** STT is always local (`faster-whisper`) or a
   direct provider (Groq free tier, OpenAI key, …). **Inbound voice notes are free.**
3. **Text-to-speech has free backends** — Edge TTS (keyless) and Piper/NeuTTS/KittenTTS (fully
   local). The paid Nous Gateway TTS is *only* OpenAI voices as a convenience, **not** the only path.
   → **The repo's current assumption that "`tts` ships no free local backend" is outdated and should
   be corrected.**
4. **Only `image_gen` genuinely lacks a free backend** among the gateway tools — that one really does
   need the paid gateway or a paid key.
5. **Hebrew works but has a quality gap** best closed with local Israeli fine-tunes (ivrit.ai for STT,
   Phonikud+Piper for TTS), wired via Hermes' zero-Python **custom-command provider** hooks.
6. **Hybrid Hebrew/English (Hebrish) is the genuinely hard part** — no model nails intra-sentence
   code-switching; use a cloud multilingual model on auto-detect, or the `Whisper-Hebrish` fine-tune.

---

## 1. The critical distinction — four cost/licensing tiers (VERIFIED)

The user's three buckets (gateway-paid / local-open / verified-free-cloud) resolve cleanly, with a
necessary **fourth** bucket (paid third-party keys — neither the Nous gateway nor free):

| Bucket | What it means | Needs a paid Nous sub? | Needs a key? | Runs offline? |
|---|---|---|---|---|
| **A. Nous Gateway (paid)** | Tool routed through Nous Portal infra | **Yes** (paid plan; or limited "free tool pool") | No (Portal OAuth) | No |
| **B. Local & open** | Model runs on the user's machine | No | **No** | **Yes** |
| **C. Verified free cloud** | No per-call cost; a network call, maybe a free key/login | No | Sometimes (free-tier key) | No |
| **D. Paid third-party (BYO key)** | Direct provider account, per-use billing | No | Yes (paid) | No |

### 1a. What the Nous Tool Gateway actually gates (Bucket A)

Per the Tool Gateway doc, the gateway is **"included with every *paid* Nous Portal subscription"** and
routes exactly **four** tool categories:

| Gateway tool | Backend | Free alternative exists? |
|---|---|---|
| `web` search/extract | Firecrawl | ✅ Yes — keyless DuckDuckGo/SearXNG (repo already pins this) |
| `image_gen` | FAL/FLUX, GPT Image, etc. (9 models) | ❌ **No free local backend** — genuinely needs gateway or paid key |
| **`text_to_speech`** | **OpenAI TTS voices** | ✅ **Yes** — Edge (keyless) + Piper/NeuTTS/KittenTTS (local) |
| `browser` | Browser Use (cloud Chromium) | ✅ Yes — local Chromium (repo already pins this) |

**Eligibility (verified, verbatim intent):** *"The Tool Gateway is a **paid-subscription** feature.
Free-tier Nous accounts can use Portal for inference but don't include managed tools."* Some accounts
get a small **"free tool pool"** allowance, but the baseline is a paid plan.

> **STT is not on this list.** There is **no gateway speech-to-text**. Transcription of inbound voice
> notes is always Bucket B (local Whisper) or Bucket C/D (Groq/OpenAI/etc.). This is the single most
> important verification result: **receiving and understanding voice notes costs nothing and needs no
> subscription.**

### 1b. `use_gateway` semantics (verified)

`use_gateway` is a **per-tool boolean** inside each tool's config block (`web`, `image_gen`, `tts`,
`browser`). Precedence, per the doc:

- `use_gateway: true` → routes through Nous **regardless** of any direct keys.
- `use_gateway: false` (or absent) → uses a **direct backend if one exists**, and *only* falls back
  to the paid gateway when **no** direct backend is configured.

The repo's [`dist/general/config.yaml`](../../dist/general/config.yaml) sets `tts: {use_gateway:
false}`, `image_gen: {use_gateway: false}`, `web: {backend: ddgs, use_gateway: false}`, `browser:
{backend: local, use_gateway: false}`.

- For `web`/`browser`, a **free direct backend is pinned**, so there's no path to a paid call. ✅
- For `tts`, **no `provider` is set** — so behavior depends on Hermes' default `tts.provider`
  (documented default: **`edge`**, which is free/keyless). To be explicit and safe, the persona should
  *set* `tts.provider: edge` (or `piper`) rather than rely on the implicit default.
- For `image_gen`, there is no free backend, so it stays inert unless a user opts into a key/gateway.

### 1c. Correction to the repo's current premise

Root [`AGENTS.md`](../../AGENTS.md) and the base template comment state:
*"image_gen/tts ship no free local backend."* This is **half-right**:

- ✅ True for `image_gen` (no free backend ships).
- ❌ **Outdated for `tts`** — Hermes provides Edge TTS (keyless, free, default), plus Piper, NeuTTS,
  and KittenTTS (all free, fully local). TTS therefore belongs with `web`/`browser` (has a free
  direct backend) **not** with `image_gen`. The default path *can* speak for free.

---

## 2. Native Hermes voice capabilities (what exists out of the box)

| Goal | Native support | Bucket of the free path |
|---|---|---|
| Voice note in → agent understands | Auto-STT on Telegram/Discord/WhatsApp/Slack/Signal, transcript injected as text | **B** (local `faster-whisper`) |
| Agent replies in voice | TTS → Telegram voice bubble (Opus), Discord voice message, WhatsApp audio | **B/C** (Piper local / Edge keyless) |
| Dictation | Same STT pipeline; CLI **voice mode** (Ctrl+B push-to-talk, VAD, streaming TTS) | **B** |
| Meeting participation | **Discord voice channels** (join, per-speaker listen, speak back) | **B/C** |
| Zoom / Google Meet / Teams | ❌ No native bot — needs external bridge (see §6) | external |

**Extension hooks (no Python needed), both verified in the TTS doc:**

- **STT command providers** — `stt.providers.<name>: type: command`, audio `{input_path}` →
  transcript `{output_path}`, with `{language}`/`{model}`. Wire whisper.cpp, Parakeet, ivrit.ai, etc.
- **TTS command providers** — `tts.providers.<name>: type: command`, text → audio; `voice_compatible:
  true` makes Telegram render a voice bubble. Wire XTTS/Phonikud/HebTTS/etc.
- **Python plugins** — `register_transcription_provider()` / `register_tts_provider()` for SDK-only
  engines.
- Native **Piper** also loads any custom `.onnx` voice directly via `tts.piper.voice: /path/…`.

`ffmpeg` is required for Telegram voice bubbles with Edge/Piper/NeuTTS/KittenTTS output (they emit
MP3/WAV; OpenAI/ElevenLabs/Mistral emit Opus natively).

---

## 3. Speech-to-text (inbound voice notes)

Built-in providers: `local` (faster-whisper), `groq`, `openai`, `mistral`, `xai`, plus command/plugin
providers. **None route through the paid gateway.**

### Bucket B — local & open (no key)
- **ivrit-ai/whisper-large-v3-turbo** (Apache-2.0) — SOTA free **Hebrew** ASR; ~20–30% WER reduction
  over vanilla Whisper. Runs via `faster-whisper`/CTranslate2 (~0.9–1.6 GB). **Hebrew-only** —
  language detection/translation degraded on purpose → **do not use for Hebrish**.
- **Hermes default `local` faster-whisper `large-v3`** — multilingual, handles Hebrew acceptably,
  zero config. Safe baseline; upgrade to ivrit.ai for pure-Hebrew quality.

```yaml
# Hebrew-optimized local STT (fully local, no key)
stt:
  provider: ivrit
  language: he
  providers:
    ivrit:
      type: command
      command: "faster-whisper {input_path} --model ivrit-ai/whisper-large-v3-turbo --language he --output_dir {output_dir} --output_format txt"
      format: txt
      language: he
      timeout: 300
```

### Bucket C — verified free cloud
- **Groq `whisper-large-v3-turbo`** — free tier, needs a free `GROQ_API_KEY`; fastest (~0.5s);
  Hermes built-in. Best free-cloud pick.

### Bucket D — paid third-party (BYO key), for reference
Per-minute pricing verified 2026-07: OpenAI `gpt-4o-mini-transcribe` $0.003/min, `gpt-4o-transcribe`
$0.006/min; AssemblyAI Universal-2 $0.0025/min; Deepgram Nova-3 $0.0077/min stream; ElevenLabs Scribe
v2 $0.22/hr; Google Chirp 3 $0.016/min ($0.004 batch). Good Hebrew: OpenAI, Google Chirp, ElevenLabs.

---

## 4. Text-to-speech (spoken replies)

Ten built-in providers + command/plugin providers. **The paid gateway TTS (OpenAI voices) is optional
convenience, not required.**

> **Hebrew TTS wrinkle:** modern Hebrew omits niqqud (vowel diacritics), so good TTS needs a
> grapheme-to-phoneme step. The best open solution is **Phonikud** (Interspeech 2026), an open G2P
> designed to feed **Piper** for real-time Hebrew TTS.

### Bucket B — local & open (no key)
- **Piper + Phonikud** — best truly-local Hebrew TTS; point `tts.piper.voice` at the Phonikud `.onnx`.
- NeuTTS / KittenTTS — local, keyless (general voices). Research-grade Hebrew: HebTTS, RoboShaul,
  Mamre-TTS (heavier / non-commercial weights).

### Bucket C — verified free cloud
- **Edge TTS `he-IL` voices** (`he-IL-AvriNeural`, `he-IL-HilaNeural`) — Hermes default, keyless, no
  setup, decent quality. Free + keyless, but calls Microsoft's endpoint (not local). Needs `ffmpeg`
  for voice bubbles.
- **Google Gemini TTS** — free tier, needs free `GEMINI_API_KEY`; expressive (audio tags).

### Bucket A — Nous Gateway (paid)
- OpenAI TTS voices via `tts.use_gateway: true` — needs the **paid** Portal subscription (or free tool
  pool). Convenience only; the free buckets above cover the default path.

### Bucket D — paid third-party (BYO key)
- **ElevenLabs multilingual v2/v3** — best-in-class Hebrew naturalness ($0.10/1k chars v2, $0.05
  Flash), native Opus. OpenAI TTS (direct key), MiniMax, Mistral, xAI also available.

---

## 5. Hybrid Hebrew/English ("Hebrish") — the hard part

Whisper detects one language from the first ~30s and sticks with it, so intra-sentence code-switching
degrades (romanizes Hebrew, or translates instead of transcribing). Options, best-fit first:

1. **danielrosehill/Whisper-Hebrish** — a Whisper-large-v3-turbo fine-tune purpose-built for en-he
   immigrant code-switching (6.07% WER vs 16.79% baseline). On Replicate for inference, weights on HF.
   **Caveat:** POC trained on one speaker + 516 sentences — benchmark on real users before shipping.
2. **Cloud multilingual on auto-detect** — OpenAI `gpt-4o-transcribe`, Google Chirp 3, ElevenLabs
   Scribe handle code-switching noticeably better than local Whisper. Best "just works" budget path.
   Do **not** force `language: he`.
3. **Do NOT use ivrit.ai large-v3 for Hebrish** — it is Hebrew-only by design.
4. **TTS:** multilingual voices (ElevenLabs multilingual, Gemini) render mixed text far better than
   single-language voices.

**Honest recommendation:** start Hebrish on a cloud multilingual model (Groq/OpenAI) for reliability;
evaluate Whisper-Hebrish as a local upgrade once benchmarked on real audio.

---

## 6. Meeting participation

- **Native:** Discord voice channels (join, per-speaker listen, speak back) and CLI voice mode
  (push-to-talk, streaming TTS). Dictation reuses the STT pipeline.
- **Zoom / Google Meet / Teams — no native Hermes bot. Bridge it:**
  - **Vexa** (Apache-2.0, self-hostable) — auto-join bot for Meet/Teams/Zoom, real-time per-speaker
    transcripts over WebSocket, bots that **speak/chat**, Whisper-based (100+ langs incl. Hebrew), and
    an **MCP server (17 tools)** so a Hermes agent can join, read the transcript, and talk. Free
    self-host (needs a GPU node for local Whisper) or hosted (~$0.30/hr bot + $0.20/hr transcription).
    **Best fit — connects via MCP.**
  - **MeetingScribe** (MIT) — 100% local, key-free note-taker via system-audio capture; great for
    private dictation/summaries, but doesn't autonomously *join* meetings.

---

## 7. Recommended stacks by tier

**Tier 0 — free, on the default apply path (Buckets B + C, no paid sub):**
- STT: ivrit.ai turbo (pure Hebrew) / faster-whisper `large-v3` (Hebrish, auto-detect) — local.
- TTS: Edge `he-IL` (easiest, keyless) or Piper+Phonikud (fully local).
- Meetings: Discord voice + CLI voice mode; Vexa self-host for Meet/Zoom.
- Local deps (via `setup_steps[]`): `ffmpeg`, `faster-whisper`, `piper-tts`.

**Tier 1 — guided opt-in (Buckets C-with-key / A / D):**
- STT: Groq (free key) → OpenAI `gpt-4o-transcribe` for Hebrish (paid).
- TTS: ElevenLabs multilingual v3 (paid), or OpenAI TTS free via the **paid** Nous gateway.
- Meetings: Vexa hosted via MCP.

---

## 8. How this maps to `hermes-setup`

Everything below fits existing repo patterns (the `setup_steps[]` RTK precedent, the Tier-0/Tier-1
contract, and reference-only skills). **Most of this needs no skill at all** — just `config.yaml`
fragments + a local-binary `setup_steps[]` entry — which sidesteps the reference-only skill rule.

- **Correct the outdated premise** in root [`AGENTS.md`](../../AGENTS.md) + base template comment:
  `tts` *does* have free backends (Edge keyless; Piper/NeuTTS/KittenTTS local); only `image_gen` lacks
  one. Group `tts` with `web`/`browser`.
- **`base/general` (Tier 0):** set `tts.provider: edge` (explicit, free) and add an `stt:` block
  (`provider: local`, `local.model: large-v3`, `language: ""` for Hebrish auto-detect). Keep
  `use_gateway: false` everywhere.
- **`setup_steps[]` (Tier 0):** add `ffmpeg` + `pip install faster-whisper piper-tts`, mirroring the
  gated/idempotent RTK step. Emitted into `setup.steps.{sh,ps1}`.
- **`locale/il` (Tier 0):** override to the Hebrew-optimized stack — ivrit.ai STT command provider +
  Piper+Phonikud (or Edge `he-IL-AvriNeural`) TTS, `stt.language: he`. Stays free/local/keyless.
- **`/finish-setup` (Tier 1):** offer Groq/OpenAI/ElevenLabs keys and Vexa (or its MCP) for
  Zoom/Meet/Teams meeting bots; document that Nous-gateway TTS needs the **paid** plan.

---

## 9. Caveats & open questions

- **Toolset enablement not yet confirmed.** `use_gateway`/`provider` control *how* TTS runs, but
  whether the `text_to_speech` tool / voice toolset is enabled by default per persona is a separate
  setting — verify against a live install before assuming replies auto-speak.
- **Edge TTS is keyless+free but not local** (calls Microsoft). For a strictly-local Tier-0 ideal,
  prefer Piper+Phonikud.
- **Hebrish is the real risk** — benchmark Whisper-Hebrish vs cloud auto-detect on real user audio.
- **ivrit.ai large-v3 is Hebrew-only** — never use where English mixes in.
- **Hebrew voice-quality rankings** come from web research (ivrit.ai leaderboard, Phonikud Interspeech
  2026), not first-hand testing — spot-check before shipping defaults.
- **`ffmpeg` is mandatory** for Telegram voice bubbles on the free (Edge/Piper) providers.

---

## Sources

- Hermes Tool Gateway, Voice & TTS, Voice Mode docs (nousresearch.com, 2026-07-09).
- ivrit.ai: <https://huggingface.co/ivrit-ai/whisper-large-v3-turbo>, Hebrew transcription leaderboard.
- Whisper-Hebrish: <https://huggingface.co/danielrosehill/Whisper-Hebrish> + blog.
- Phonikud (Interspeech 2026): <https://phonikud.github.io/>; Piper: <https://github.com/rhasspy/piper>.
- HebTTS: <https://github.com/slp-rl/HebTTS>; RoboShaul; Mamre-TTS.
- STT pricing (2026-07): convertaudiototext.com, apiscout.dev, vexascribe.com, aicost.ai.
- Meeting bots: Vexa <https://github.com/Vexa-ai/vexa>; MeetingScribe <https://github.com/elmoghany/meeting-scribe>.
