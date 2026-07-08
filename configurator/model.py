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
    """A referenced (not vendored) skill/tap recorded in the distribution README."""

    id: str
    note: str = ""
    is_tap: bool = False


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
    source_dir: Path | None = None
