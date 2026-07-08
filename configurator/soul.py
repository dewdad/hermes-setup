"""Compose SOUL.md from ordered, inheritance-resolved fragments.

Each fragment is read from its owning template's ``soul/`` dir. Fragments join with a blank line;
the result must stay within Hermes' effective SOUL budget (``SOUL_MAX_CHARS``) or the build fails.
"""

from __future__ import annotations

from configurator import SOUL_MAX_CHARS
from configurator.errors import TemplateError
from configurator.model import SoulFragment

_SEPARATOR = "\n\n"


def compose_soul(fragments: tuple[SoulFragment, ...], template_name: str) -> str:
    """Read + concatenate fragments in order. Returns "" for no fragments; raises on cap/missing."""
    if not fragments:
        return ""
    parts: list[str] = []
    for frag in fragments:
        if frag.path is None or not frag.path.is_file():
            raise TemplateError(
                template=template_name,
                field="soul.fragments",
                reason=f"fragment '{frag.name}' not found at {frag.path}",
            )
        parts.append(frag.path.read_text(encoding="utf-8").strip())
    composed = _SEPARATOR.join(parts) + "\n"
    if len(composed) > SOUL_MAX_CHARS:
        raise TemplateError(
            template=template_name,
            field="soul",
            reason=f"composed SOUL is {len(composed)} chars (max {SOUL_MAX_CHARS})",
        )
    return composed
