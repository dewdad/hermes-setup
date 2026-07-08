"""Discover templates on disk and resolve inheritance.

A template lives at ``templates/<ref>/template.yaml`` where ``<ref>`` (e.g. ``base/general``,
``persona/il-legal``) is the value used in ``extends``. Discovery builds the ref->Template registry
that :func:`resolve` walks.
"""

from __future__ import annotations

from pathlib import Path

from configurator.errors import MergeError
from configurator.merge import resolve
from configurator.model import Template
from configurator.parse import parse_template
from configurator.yamlio import load_yaml

MANIFEST_NAME = "template.yaml"


def discover_templates(templates_root: Path) -> dict[str, Template]:
    """Return a mapping of ref (posix path under templates/) to parsed :class:`Template`."""
    registry: dict[str, Template] = {}
    for manifest in sorted(templates_root.rglob(MANIFEST_NAME)):
        source_dir = manifest.parent
        ref = source_dir.relative_to(templates_root).as_posix()
        registry[ref] = parse_template(load_yaml(manifest), source_dir=source_dir)
    return registry


def load_and_resolve(ref: str, registry: dict[str, Template]) -> Template:
    """Resolve the full inheritance chain for ``ref`` into a single merged template."""
    if ref not in registry:
        raise MergeError(template=ref, reason="no such template ref")
    return resolve(registry[ref], registry.__getitem__)


def ref_for_name(name: str, registry: dict[str, Template]) -> str:
    """Map a bare template name (``developer``) or a full ref to its ref, raising if ambiguous."""
    if name in registry:
        return name
    matches = [ref for ref, tpl in registry.items() if tpl.name == name]
    if not matches:
        raise MergeError(template=name, reason="no template with this ref or name")
    if len(matches) > 1:
        raise MergeError(template=name, reason=f"name is ambiguous across {matches}")
    return matches[0]
