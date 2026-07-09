"""Template manifest schema types.

Frozen dataclasses + enums describing a parsed ``template.yaml``. Parsing/validation lives in
``parse.py`` (``parse_template``) so this module owns *shape* only.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from pathlib import Path

from configurator.yamlio import YamlMap


class TemplateKind(StrEnum):
    """Layer of a template. Rank enforces base -> locale -> persona inheritance ordering."""

    BASE = "base"
    LOCALE = "locale"
    PERSONA = "persona"

    @property
    def rank(self) -> int:
        match self:
            case TemplateKind.BASE:
                return 0
            case TemplateKind.LOCALE:
                return 1
            case TemplateKind.PERSONA:
                return 2


class SkillSourceKind(StrEnum):
    """How a skill is sourced.

    GITHUB/URL/WELL_KNOWN are vendored (bucket 1, genuinely fetched into ``skills-vendor/`` and
    pinned by lock); OFFICIAL/TAP are referenced post-install (bucket 3). Skill *content* is never
    authored in this repo — every vendored skill is fetched from a real upstream via ``update-locks``.
    """

    GITHUB = "github"
    URL = "url"
    WELL_KNOWN = "well-known"
    OFFICIAL = "official"
    TAP = "tap"


@dataclass(frozen=True, slots=True)
class EnvVar:
    """One entry of the merged ``env`` list -> distribution ``env_requires``."""

    name: str
    description: str = ""
    required: bool = False
    default: str | None = None


@dataclass(frozen=True, slots=True)
class SkillRef:
    """A skill to include. ``vendored`` decides bucket 1 (copied) vs bucket 3 (referenced)."""

    source: SkillSourceKind
    id: str
    category: str | None = None
    license: str | None = None
    redistributable: bool = True
    ref: str = "main"  # github pin: commit SHA / tag / branch (recorded in the lock)

    @property
    def vendored(self) -> bool:
        match self.source:
            case (
                SkillSourceKind.GITHUB
                | SkillSourceKind.URL
                | SkillSourceKind.WELL_KNOWN
            ):
                return True
            case SkillSourceKind.OFFICIAL | SkillSourceKind.TAP:
                return False

    @property
    def skill_name(self) -> str:
        """Last path segment of the id (used for exclude matching and vendor dir naming)."""
        return self.id.rstrip("/").rsplit("/", 1)[-1]


@dataclass(frozen=True, slots=True)
class Bundle:
    """A skill bundle -> ``skill-bundles/<slug>.yaml``."""

    name: str
    skills: tuple[str, ...]
    description: str = ""
    instruction: str = ""


@dataclass(frozen=True, slots=True)
class PostInstallRef:
    """A referenced (not vendored) skill/tap recorded in the distribution README.

    ``tier`` splits capabilities by auth friction so the generated ``/finish-setup`` meta-skill can
    group them: tier 0 = zero-config, free, installed on apply (a working agent depends only on
    these); tier 1 = guided opt-in (needs a build / OAuth / external app), never required.
    """

    id: str
    note: str = ""
    is_tap: bool = False
    tier: int = 0


@dataclass(frozen=True, slots=True)
class DiscoveryRef:
    """One 'discover more skills' catalogue entry surfaced in ``/finish-setup`` (URLs only)."""

    label: str
    url: str
    note: str = ""


@dataclass(frozen=True, slots=True)
class SetupStep:
    """A local-tool provisioning step the apply flow runs that is NOT a ``hermes skills install``.

    ``post_install[]`` only covers skills/taps the bootstrap installs via ``hermes skills install`` /
    ``tap add``. A ``SetupStep`` covers everything else — installing a standalone binary + wiring its
    Hermes plugin (e.g. RTK's ``rtk init --agent hermes``). Commands are platform-split; the ``*_run``
    command executes only when the matching ``*_check`` command exits non-zero (so re-apply is
    idempotent). ``tier`` groups it in ``/finish-setup`` exactly like ``post_install`` (0 = free,
    on the apply path; 1 = guided opt-in). Commands carry no secrets and are secret-scanned on emit.
    """

    id: str
    label: str = ""
    note: str = ""
    tier: int = 0
    posix_check: str = ""
    posix_run: str = ""
    windows_check: str = ""
    windows_run: str = ""


@dataclass(frozen=True, slots=True)
class SoulFragment:
    """One SOUL.md fragment, bound to the source dir of the template that declared it."""

    name: str
    path: Path | None = None


@dataclass(frozen=True, slots=True)
class SkillsSpec:
    """The ``skills:`` block. ``bundled`` is 'none' | 'all' | an allowlist tuple."""

    bundled: str | tuple[str, ...] = "none"
    external_dirs: tuple[str, ...] = ()
    include: tuple[SkillRef, ...] = ()
    exclude: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class Template:
    """A fully parsed template manifest (pre- or post-inheritance-resolution)."""

    name: str
    kind: TemplateKind
    extends: str | None = None
    distribution: YamlMap = field(default_factory=dict)
    config: YamlMap = field(default_factory=dict)
    env: tuple[EnvVar, ...] = ()
    soul: tuple[SoulFragment, ...] = ()
    skills: SkillsSpec = field(default_factory=SkillsSpec)
    bundles: tuple[Bundle, ...] = ()
    mcp: YamlMap = field(default_factory=dict)
    cron: tuple[YamlMap, ...] = ()
    post_install: tuple[PostInstallRef, ...] = ()
    discovery: tuple[DiscoveryRef, ...] = ()
    setup_steps: tuple[SetupStep, ...] = ()
    portal_auth: bool = False
    source_dir: Path | None = None
