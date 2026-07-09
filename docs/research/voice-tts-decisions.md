# Plan & key decisions: voice / TTS / audio for `hermes-setup`

**Status:** decision doc (pre-implementation) — **recommendations are now decisive**. **Date:** 2026-07-09.
**Companion to:** [`voice-tts-audio.md`](./voice-tts-audio.md) (the research + verified cost/licensing tiers).
**Purpose:** the decisions we must make before writing template changes, each resolved with a clear
recommended default. Nothing here is implemented yet — this is the agreed plan of record pending your
sign-off. Items marked **⚑ confirm** are where a one-word owner override is cheap; everything else is
decided.

> Reminder of the verified frame (see research doc §1): **STT never needs the paid gateway**; **TTS
> has free backends** (Edge keyless, Piper/NeuTTS/KittenTTS local); **only `image_gen` truly needs the
> paid Nous gateway**. So voice lives almost entirely on the free Tier-0 path.

## Decision summary (the plan of record)

| # | Decision | Recommendation |
|---|---|---|
| D1 | Tier-0 TTS default | **Edge TTS default + Piper documented as the local alternative.** Edge qualifies as Tier 0. |
| D2 | Enable voice by default? | **Yes — STT+TTS config on by default; deps gated in `setup_steps[]`.** |
| D3 | Default local STT model | **`small` (~0.5 GB) in `base/general`; ivrit.ai turbo in `locale/il`.** |
| D4 | How to install deps/models | **`setup_steps[]` (RTK pattern).** |
| D5 | Fix outdated `tts` premise | **Yes, fix it in this work.** |
| D6 | Hebrish strategy | **Local `small` auto-detect now; cloud = Tier-1 upgrade; Whisper-Hebrish = benchmark-later.** |
| D7 | Meetings in v1 | **Native only (Discord + CLI dictation). Vexa = Tier-1 follow-up.** |
| D8 | Docs in DOX chain | **Keep as loose `docs/research/` artifacts now; formalize only when implementation lands.** |
| D9 | First voice channel | **Telegram (native Hermes voice pipeline).** |

---

## A. Decisions needed now (blocking)

### D1 — Tier-0 TTS default: Edge vs Piper
The Tier-0 contract's intent is **"no paid, per-call services on the default path."** Edge TTS is
free, keyless, and zero per-call cost — it satisfies that intent even though it calls Microsoft's
endpoint. "Local" in the contract is the *means* to "free + private + no lock-in," not an end in
itself; a keyless free endpoint meets the same goal for the layman path.

**Decision: ship both — `tts.provider: edge` as the default, Piper documented as the fully-local
alternative.** Rationale: Edge gives the best zero-setup layman UX (no model download, good `he-IL`
voices, works on weak machines); Piper covers users who need true offline/local. Update the Tier-0
wording from "free-to-run **and local**" to **"free-to-run + keyless (fully-local option provided)"**
so Edge is unambiguously compliant and Piper is the offline upgrade.
**⚑ confirm** only if you want Tier 0 to remain strictly local — then Piper becomes the default and
Edge drops to a documented option.

### D2 — Enable voice on the default path
**Decision: yes — enable STT + TTS config in `base/general` by default**, consistent with the
"one-step working agent" principle. The heavier **model/dependency downloads** go into a gated,
idempotent, failure-tolerant `setup_steps[]` (D4), so a machine without `ffmpeg`/GPU still installs
cleanly and simply degrades (Hermes falls back gracefully when a provider is unavailable).

### D3 — Default local STT model size
**Decision: `base/general` → `small` (~0.5 GB, multilingual, Hebrish auto-detect); `locale/il` →
ivrit.ai turbo (~1.6 GB, best Hebrew).** `small` is the balance point: meaningfully better than `base`
on Hebrew, far lighter/faster than `large-v3` (~3 GB) on the CPU-only machines most laymen run. Power
users can bump to `large-v3` via one config line.
**⚑ confirm** the ~0.5 GB default download is acceptable for the layman path (fallback: `base` at
~150 MB if you want the lightest possible first-run).

### D4 — How to install local deps/models
**Decision: `setup_steps[]`, mirroring the existing RTK precedent** — gated, idempotent,
failure-tolerant, per-platform `setup.steps.{sh,ps1}`; no skill authoring, no security-scan friction.
One Tier-0 step installs `ffmpeg` (OS-specific: apt/brew/winget, tolerate absence) + `pip install
faster-whisper piper-tts`; model weights auto-download on first use.

### D5 — Fix the outdated `tts` premise in the DOX rail
**Decision: yes, correct it in this work.** Root [`AGENTS.md`](../../AGENTS.md) + the base template
comment claim "`tts` ships no free local backend" — false (research §1c). Regroup `tts` with
`web`/`browser` (has a free direct backend); keep `image_gen` as the *only* no-free-backend gateway
tool. Small, factual, and it unblocks enabling free TTS by default.

---

## B. Decisions that shape scope (resolved for v1)

### D6 — Hebrish (hybrid Hebrew/English) strategy
**Decision: ship local `small` on auto-detect now** (free, decent, no key). Position **cloud
multilingual (OpenAI/Groq) auto-detect as the Tier-1 quality upgrade**, and **Whisper-Hebrish as a
benchmark-then-adopt candidate** (it's a promising but single-speaker POC — measure on real user audio
before making it a default). **Never** use ivrit.ai turbo for Hebrish (Hebrew-only by design).

### D7 — Meeting participation scope for v1
**Decision: native only for v1 — Discord voice channels + CLI dictation** (zero new infra, ships
immediately). Document **Vexa (self-host via MCP, or hosted)** as the Tier-1 follow-up that adds
Zoom/Google Meet/Teams join-and-speak.
**⚑ confirm** if in-meeting Zoom/Meet/Teams participation is actually required in v1 — if so, Vexa
self-host moves from "follow-up" into v1 scope (adds a GPU-node + MCP-wiring workstream).

### D8 — Where these docs live in the DOX chain
**Decision: keep them as loose working artifacts under `docs/research/` for now.** They are
research/decision inputs, not binding contracts, so adding a `docs/AGENTS.md` child rail now is
premature overhead. **Formalize** (add `docs/AGENTS.md` + a root README doc-table link) **only when the
implementation lands** and these become durable reference docs.

### D9 — First voice channel to target
**Decision: Telegram.** It has a first-class native Hermes voice pipeline (auto-STT on inbound voice
memos, TTS voice-bubble replies, and a 2 GB file ceiling via local Bot API for long recordings). Beeper
— the repo's current Tier-1 messaging path — is text-oriented and a weaker fit for a voice-first
experience, so it stays a general-messaging option, not the voice target.

---

## C. Already settled (from verified research — no decision needed)

- STT is free and never uses the paid gateway.
- The paid Nous gateway is *optional* for voice (OpenAI TTS convenience only).
- `image_gen` is out of scope for a free voice agent (no free backend).
- Extension mechanism for Hebrew models = Hermes **custom-command providers** (no Python, no skill).

---

## D. Recommended MVP (the plan of record)

1. Correct the `tts`-has-no-free-backend premise in root `AGENTS.md` + base template comment (D5).
2. `base/general`: set `tts.provider: edge` + an `stt` block (`provider: local`, `local.model: small`,
   `language: ""` for Hebrish auto-detect); keep `use_gateway: false` throughout (D1/D2/D3).
3. Add a Tier-0 `setup_steps[]` entry: `ffmpeg` + `pip install faster-whisper piper-tts` (D4).
4. `locale/il`: override to ivrit.ai turbo STT (`language: he`) + Edge `he-IL-AvriNeural` TTS, with
   Piper+Phonikud documented as the fully-local alternative.
5. `/finish-setup`: Tier-1 opt-ins — Groq/OpenAI/ElevenLabs keys, the Hebrish cloud upgrade, and Vexa
   for meetings.
6. Document the free/paid/gateway distinction in the persona README + `PREREQUISITES.md`; target
   **Telegram** as the primary voice channel (D9).

**Explicitly deferred (post-v1):** Vexa/meeting bots (D7), Whisper-Hebrish adoption (D6), `image_gen`,
and DOX formalization of these docs (D8).

---

## E. Items still worth a one-word owner override (⚑)

These are decided with sensible defaults; flag only if you disagree:

1. **D1** — Tier 0 stays keyless (Edge default) vs must be strictly local (Piper default).
2. **D3** — `small` (~0.5 GB) default download acceptable vs go lighter (`base`).
3. **D7** — native-only meetings in v1 vs pull Vexa (Zoom/Meet/Teams) into v1.

Everything else is locked. On your go-ahead (or overrides), I'll convert Section D into concrete
template edits and recompile.
