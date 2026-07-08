"""Inheritance resolution + deep-merge semantics.

``resolve`` folds a template's ``extends`` chain root-first (base -> locale -> persona). Config
maps deep-merge child-over-parent; config lists set-union with ``!remove`` markers; skills use
``include``/``exclude``; env/bundles/post_install union by identity.
"""

from __future__ import annotations

import copy
from collections.abc import Callable
from typing import TypeGuard

from configurator.errors import MergeError
from configurator.model import (
    Bundle,
    DiscoveryRef,
    EnvVar,
    PostInstallRef,
    SetupStep,
    SkillRef,
    SkillsSpec,
    SoulFragment,
    Template,
)
from configurator.yamlio import YamlMap, YamlValue

_REMOVE_KEY = "!remove"


def _is_remove_marker(item: YamlValue) -> TypeGuard[dict[str, YamlValue]]:
    return isinstance(item, dict) and set(item.keys()) == {_REMOVE_KEY}


def _merge_list(parent: list[YamlValue], child: list[YamlValue]) -> list[YamlValue]:
    """Set-union preserving order: parent items (minus removed) then new child items."""
    removals = [item[_REMOVE_KEY] for item in child if _is_remove_marker(item)]
    additions = [item for item in child if not _is_remove_marker(item)]
    result: list[YamlValue] = [copy.deepcopy(p) for p in parent if p not in removals]
    for add in additions:
        if add not in result:
            result.append(copy.deepcopy(add))
    return result


def merge_config(parent: YamlMap, child: YamlMap) -> YamlMap:
    """Deep-merge two config fragments, child overriding parent. Never mutates the inputs."""
    result: YamlMap = copy.deepcopy(parent)
    for key, child_val in child.items():
        parent_val = result.get(key)
        if isinstance(parent_val, dict) and isinstance(child_val, dict):
            result[key] = merge_config(parent_val, child_val)
        elif isinstance(parent_val, list) and isinstance(child_val, list):
            result[key] = _merge_list(parent_val, child_val)
        else:
            result[key] = copy.deepcopy(child_val)
    return result


def _merge_env(parent: tuple[EnvVar, ...], child: tuple[EnvVar, ...]) -> tuple[EnvVar, ...]:
    by_name: dict[str, EnvVar] = {e.name: e for e in parent}
    for env in child:
        by_name[env.name] = env
    return tuple(by_name.values())


def _merge_soul(
    parent: tuple[SoulFragment, ...], child: tuple[SoulFragment, ...],
) -> tuple[SoulFragment, ...]:
    """Ordered append; a child fragment overrides a parent fragment of the same filename in place."""
    order: list[str] = []
    by_name: dict[str, SoulFragment] = {}
    for frag in (*parent, *child):
        if frag.name not in by_name:
            order.append(frag.name)
        by_name[frag.name] = frag
    return tuple(by_name[name] for name in order)


def _merge_skills(parent: SkillsSpec, child: SkillsSpec) -> SkillsSpec:
    excluded = set(parent.exclude) | set(child.exclude)
    merged_includes: dict[tuple[str, str], SkillRef] = {}
    for ref in (*parent.include, *child.include):
        merged_includes[(str(ref.source), ref.id)] = ref
    kept = tuple(r for r in merged_includes.values() if r.skill_name not in excluded)
    ext_order: list[str] = []
    for d in (*parent.external_dirs, *child.external_dirs):
        if d not in ext_order:
            ext_order.append(d)
    bundled = child.bundled if child.bundled != "none" or parent.bundled == "none" else parent.bundled
    return SkillsSpec(
        bundled=bundled,
        external_dirs=tuple(ext_order),
        include=kept,
        exclude=(),
    )


def _merge_bundles(parent: tuple[Bundle, ...], child: tuple[Bundle, ...]) -> tuple[Bundle, ...]:
    by_name: dict[str, Bundle] = {b.name: b for b in parent}
    for bundle in child:
        by_name[bundle.name] = bundle
    return tuple(by_name.values())


def _pi_name(ref: PostInstallRef) -> str:
    """Last path segment of a post-install id — the token ``skills.exclude`` matches against."""
    return ref.id.rstrip("/").rsplit("/", 1)[-1]


def _merge_post_install(
    parent: tuple[PostInstallRef, ...],
    child: tuple[PostInstallRef, ...],
    excluded: frozenset[str],
) -> tuple[PostInstallRef, ...]:
    by_id: dict[str, PostInstallRef] = {p.id: p for p in parent}
    for ref in child:
        by_id[ref.id] = ref
    return tuple(r for r in by_id.values() if _pi_name(r) not in excluded)


def _merge_discovery(
    parent: tuple[DiscoveryRef, ...], child: tuple[DiscoveryRef, ...],
) -> tuple[DiscoveryRef, ...]:
    """Set-union by url, parent entries first then new child entries (child overrides on url)."""
    order: list[str] = []
    by_url: dict[str, DiscoveryRef] = {}
    for ref in (*parent, *child):
        if ref.url not in by_url:
            order.append(ref.url)
        by_url[ref.url] = ref
    return tuple(by_url[url] for url in order)


def _merge_setup_steps(
    parent: tuple[SetupStep, ...],
    child: tuple[SetupStep, ...],
    excluded: frozenset[str],
) -> tuple[SetupStep, ...]:
    """Set-union by id (child overrides), preserving base->child order; ``skills.exclude`` drops by id."""
    order: list[str] = []
    by_id: dict[str, SetupStep] = {}
    for step in (*parent, *child):
        if step.id not in by_id:
            order.append(step.id)
        by_id[step.id] = step
    return tuple(by_id[sid] for sid in order if sid not in excluded)


def _merge_templates(parent: Template, child: Template) -> Template:
    """Produce the child with the parent's contributions folded in beneath it."""
    excluded = frozenset(parent.skills.exclude) | frozenset(child.skills.exclude)
    return Template(
        name=child.name,
        kind=child.kind,
        extends=None,
        distribution=merge_config(parent.distribution, child.distribution),
        config=merge_config(parent.config, child.config),
        env=_merge_env(parent.env, child.env),
        soul=_merge_soul(parent.soul, child.soul),
        skills=_merge_skills(parent.skills, child.skills),
        bundles=_merge_bundles(parent.bundles, child.bundles),
        mcp=merge_config(parent.mcp, child.mcp),
        cron=(*parent.cron, *child.cron),
        post_install=_merge_post_install(parent.post_install, child.post_install, excluded),
        discovery=_merge_discovery(parent.discovery, child.discovery),
        setup_steps=_merge_setup_steps(parent.setup_steps, child.setup_steps, excluded),
        source_dir=child.source_dir,
    )


def _chain(leaf: Template, resolver: Callable[[str], Template]) -> list[Template]:
    """Return the inheritance chain root-first, detecting cycles and illegal kind ordering."""
    chain: list[Template] = []
    seen: set[str] = set()
    current: Template | None = leaf
    while current is not None:
        chain.append(current)
        parent_ref = current.extends
        if parent_ref is None:
            break
        if parent_ref in seen:
            raise MergeError(template=leaf.name, reason=f"inheritance cycle at '{parent_ref}'")
        seen.add(parent_ref)
        try:
            parent = resolver(parent_ref)
        except KeyError:
            raise MergeError(template=leaf.name, reason=f"unknown parent '{parent_ref}'") from None
        if parent.kind.rank >= current.kind.rank:
            raise MergeError(
                template=leaf.name,
                reason=f"'{parent.name}' ({parent.kind}) cannot be a parent of "
                f"'{current.name}' ({current.kind})",
            )
        current = parent
    chain.reverse()
    return chain


def resolve(leaf: Template, resolver: Callable[[str], Template]) -> Template:
    """Fully resolve inheritance for ``leaf`` into a single merged :class:`Template`."""
    chain = _chain(leaf, resolver)
    merged = chain[0]
    for child in chain[1:]:
        merged = _merge_templates(merged, child)
    return merged
