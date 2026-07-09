"""Generate the ``finish-setup`` meta-skill body from a resolved template.

This is the ONE piece of skill *content* the compiler authors (the documented reference-only
carve-out): a generated onboarding skill Hermes registers as ``/finish-setup``. It is emitted to
``dist/<persona>/meta-skills/finish-setup/SKILL.md`` — a top-level, distribution-owned dir kept OUT
of ``skills/`` so ``hermes profile update`` refreshes it without touching the user's installed
skills (Hermes' updater replaces any shipped top-level dir wholesale; shipping it under ``skills/``
would wipe user-installed skills). The distribution's ``config.yaml`` references it via a relative
``skills.external_dirs`` entry so it is discovered and slash-registered.

Pure function; stdlib + PyYAML only. Everything it emits (env var NAMES, skill ids, signup /
catalogue URLs) is secret-free and re-scanned by ``emit`` before writing.
"""

from __future__ import annotations

from configurator.model import DiscoveryRef, EnvVar, PostInstallRef, SetupStep, Template
from configurator.yamlio import dump_yaml

# The profile-relative external-skills dir the compiler ships the meta-skill into. Emitted verbatim
# into config.yaml's ``skills.external_dirs`` so Hermes discovers + slash-registers finish-setup.
META_SKILLS_DIRNAME = "meta-skills"
FINISH_SETUP_NAME = "finish-setup"
_DESCRIPTION = "Finish Hermes setup: keys, skills, and discover more."  # <= 60 chars


def _frontmatter() -> str:
    block = dump_yaml({
        "name": FINISH_SETUP_NAME,
        "description": _DESCRIPTION,
        "metadata": {"hermes": {"category": "meta"}},
        "tags": ["setup", "onboarding"],
    })
    return f"---\n{block}---\n"


def _key_lines(env: tuple[EnvVar, ...]) -> list[str]:
    if not env:
        return ["_No provider keys are declared — this profile needs no keys._"]
    example_key = env[0].name
    lines = [
        "Chat runs on a free, **no-per-call-cost** model chain. Its guaranteed baseline is the",
        "**Nous Portal free plan**: sign up at https://portal.nousresearch.com/manage-subscription",
        "(Free plan — $0, free models only), then log in with `hermes setup --portal`. That alone",
        "switches on free chat. Browser automation and web search are **keyless** and already work.",
        "(Full one-time checklist: PREREQUISITES.md in the hermes-setup repo.)",
        "",
        "Adding **any one** of the keys below is optional — it unlocks the higher-tier free models",
        "earlier in the fallback chain. None costs per call:",
        "",
    ]
    lines.extend(f"- **{var.name}** — {var.description}" for var in env)
    lines += [
        "",
        "Set one on the CLI (auto-routed into `.env`, never committed):",
        "",
        "```bash",
        f"hermes config set {example_key} <your-key>",
        "```",
        "",
        "Or run `hermes auth` for a free Nous sign-in. On Desktop / messaging surfaces, add keys via",
        "`hermes setup` or the profile's `.env`.",
    ]
    return lines


def _portal_auth_lines() -> list[str]:
    """Portal-base auth: one OAuth login instead of provider keys (paid subscription required)."""
    return [
        "This profile is powered by a **paid Nous Portal subscription** — frontier agentic models",
        "plus the Nous Tool Gateway (web search, image generation, TTS, browser automation) through",
        "one OAuth login, with no per-tool API keys. It requires a **paid** Portal plan (the free",
        "plan runs free models only). Full checklist: PREREQUISITES.md in the hermes-setup repo.",
        "",
        "1. Subscribe to a paid plan at https://portal.nousresearch.com/manage-subscription.",
        "2. Log in and wire the provider + Tool Gateway in one step:",
        "",
        "```bash",
        "hermes setup --portal",
        "```",
        "",
        "This sets Nous as your inference provider, turns on the Tool Gateway, and stores an OAuth",
        "refresh token at `~/.hermes/auth.json` (no keys in `.env`). Verify with `hermes portal info`.",
    ]


def _auth_section(template: Template) -> list[str]:
    """Section 1 of finish-setup: Portal OAuth login (portal_auth bases) or provider keys (free)."""
    if template.portal_auth:
        return ["### 1. Nous Portal login (required)", "", *_portal_auth_lines()]
    return ["### 1. Provider keys (optional)", "", *_key_lines(template.env)]


def _install_line(ref: PostInstallRef) -> str:
    verb = "hermes skills tap add" if ref.is_tap else "hermes skills install"
    suffix = f" — {ref.note}" if ref.note else ""
    return f"- `{verb} {ref.id}`{suffix}"


def _skill_lines(post_install: tuple[PostInstallRef, ...]) -> list[str]:
    tier0 = [r for r in post_install if r.tier == 0]
    tier1 = [r for r in post_install if r.tier != 0]
    lines: list[str] = []
    if tier0:
        lines += [
            "**Tier 0 — free to run, installed on apply.** A working agent depends only on these",
            "(browser automation + web search are keyless). Installed from `skills.install.json`; to",
            "(re)install manually:",
            "",
        ]
        lines += [_install_line(r) for r in tier0]
    if tier1:
        lines += [
            "",
            "**Tier 1 — guided opt-in.** Not required; each needs an extra step (a build, OAuth, or",
            "a companion app — e.g. messaging needs the free Beeper Desktop app; see PREREQUISITES.md).",
            "The skill installs automatically; you supply the app/auth. Install only what you want:",
            "",
        ]
        lines += [_install_line(r) for r in tier1]
    return lines


def _setup_step_lines(steps: tuple[SetupStep, ...]) -> list[str]:
    """Render local-tool setup steps (e.g. RTK) — installed by the apply flow, shown for manual use."""
    if not steps:
        return []
    lines = [
        "",
        "**Local tools.** These install a standalone binary and wire its Hermes plugin. The apply",
        "flow (`bootstrap.ps1` / `bootstrap.sh`) runs them for you; to (re)set one up manually, run",
        "the command for your platform (each is idempotent and safe to re-run):",
        "",
    ]
    for step in steps:
        label = step.label or step.id
        tier_tag = "" if step.tier == 0 else " (Tier 1 — opt-in)"
        note = f" — {step.note}" if step.note else ""
        lines.append(f"- **{label}**{tier_tag}{note}")
        if step.posix_run:
            lines += ["", "  ```bash", f"  {step.posix_run}", "  ```"]
        if step.windows_run:
            lines += ["", "  ```powershell", f"  {step.windows_run}", "  ```"]
    return lines


def _external_opt_in_lines(external_dirs: tuple[str, ...]) -> list[str]:
    """Setup for local checkouts referenced via external_dirs.

    open-skills is a Tier-0 default-provision step (free + keyless, provisioned for first use);
    multi-gws-cli stays a Tier-1 opt-in (needs a Node build + OAuth).
    """
    lines: list[str] = []
    if any("open-skills" in d for d in external_dirs):
        lines += [
            "",
            "### open-skills catalogue (Tier 0 — provisioned by default)",
            "",
            "The flagship open-skills skills already install on apply. This step clones the **full",
            "~40-skill open-skills catalogue** into the referenced external dir so the rest are ready",
            "on first use. It is free and keyless — **do it now** as part of setup. A missing checkout",
            "is tolerated, and re-running only fast-forwards, so this is always safe:",
            "",
            "```bash",
            "git clone --depth 1 https://github.com/dewdad/open-skills ~/open-skills \\",
            "  || git -C ~/open-skills pull --ff-only",
            "```",
            "",
            "Hermes discovers the checkout automatically via `skills.external_dirs` — no restart",
            "needed. (The apply-flow `bootstrap` scripts run this same clone/pull for you.)",
        ]
    if any("multi-gws" in d for d in external_dirs):
        lines += [
            "",
            "### Google Workspace (Tier 1, optional)",
            "",
            "Gmail / Calendar / Drive / Docs / Sheets via `multi-gws-cli`. The `bootstrap` apply flow",
            "clones + builds this for you automatically. If you installed via `hermes profile install`",
            "(no bootstrap), build it once yourself — needs Node.js + git (see PREREQUISITES.md):",
            "",
            "```bash",
            "git clone https://github.com/dewdad/multi-gws-cli ~/multi-gws-cli",
            "cd ~/multi-gws-cli && npm install && npm run build",
            "```",
            "",
            "Then complete the skill's Google OAuth (a Google account is all you need). Hermes picks",
            "up the built external dir automatically. Purely optional — the agent works without it.",
        ]
    return lines


def _discover_lines(discovery: tuple[DiscoveryRef, ...]) -> list[str]:
    lines = [
        "Find more skills any time with the built-in registry search:",
        "",
        "```bash",
        "hermes skills search <topic>      # e.g. hebrew, pdf, github",
        "hermes skills install <id>        # install one you like",
        "```",
    ]
    if discovery:
        lines += ["", "Curated catalogues:", ""]
        for ref in discovery:
            suffix = f" — {ref.note}" if ref.note else ""
            lines.append(f"- [{ref.label}]({ref.url}){suffix}")
    return lines


def build_finish_setup_skill(template: Template) -> str:
    """Render the full ``finish-setup`` SKILL.md (frontmatter + body) for a resolved template."""
    intro = (
        [
            "Complete this profile: log in to your paid Nous Portal subscription, install its",
            "referenced skills, enable any Tier-1 extras you want, then health-check. The Portal",
            "login is required — it powers both the models and the Tool Gateway.",
        ]
        if template.portal_auth
        else [
            "Complete this profile: add an optional provider key, install its referenced skills, enable",
            "any Tier-1 extras you want, then health-check. Everything here is optional polish — the",
            "agent already works for free out of the box.",
        ]
    )
    body: list[str] = [
        "# Finish setup",
        "",
        *intro,
        "",
        "## When to Use",
        "",
        "Run `/finish-setup` right after installing this profile (via `hermes profile install` or",
        "Hermes Desktop), or any time you want to add keys, (re)install skills, or discover more.",
        "",
        "## Procedure",
        "",
        *_auth_section(template),
        "",
        "### 2. Referenced skills",
        "",
        *_skill_lines(template.post_install),
        *_setup_step_lines(template.setup_steps),
        *_external_opt_in_lines(template.skills.external_dirs),
        "",
        "### 3. Health check",
        "",
        "```bash",
        "hermes config check",
        "hermes doctor",
        "```",
        "",
        "### 4. Discover more",
        "",
        *_discover_lines(template.discovery),
        "",
        "## Pitfalls",
        "",
        "- Tier-1 extras (Google apps, messaging) need their own setup and never block a working",
        "  agent — skip them freely.",
        "- Community SearXNG instances can rotate/expire; the DuckDuckGo fallback keeps web search",
        "  working keyless if a preferred instance is down.",
        "- Keys go through `hermes config set` / `.env` only — never paste a key into chat or a file",
        "  that lands in git.",
        "",
        "## Verification",
        "",
        "- `hermes config check` reports no missing *required* options (all provider keys are",
        "  optional).",
        "- `hermes skills list` shows the Tier-0 skills installed.",
        "- With no key set: a web search returns results and browser automation runs (both keyless).",
        "- After you set one provider key (or run `hermes auth`): a free chat message replies.",
    ]
    return _frontmatter() + "\n" + "\n".join(body).rstrip() + "\n"
