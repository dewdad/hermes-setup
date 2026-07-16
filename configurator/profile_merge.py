"""Existing-preserving merge of a distribution ``config.yaml`` into a live profile config.

Pure engine for the EXTEND apply path (``bootstrap`` → ``python -m configurator merge-config``).
It ADDS keys/sub-keys the target lacks, KEEPS existing values on conflict (reporting each so the
installer can prompt), and UNIONS known ordered lists. It makes NO Hermes calls and never reads
``.env`` or any secret — the installer scripts own prompting, ``.env`` handling, backups, and
provenance. Compile-time inheritance uses ``merge.py`` (child-over-parent); this is deliberately
different (parent/existing wins) because a user's live config is not a template layer.
"""

from __future__ import annotations

import copy
import hashlib
import json
from dataclasses import dataclass, field

from configurator.yamlio import YamlMap, YamlValue, dump_yaml

# Config should only ever carry ``${VAR}`` / ``key_env`` references, but redact previews defensively.
_SENSITIVE_TOKENS = ("key", "token", "secret", "password", "auth")
# Lists merged by order-preserving set-union of exact scalars (append incoming extras).
_STRING_UNION_PATHS = frozenset({"skills.external_dirs"})
# Lists of provider dicts merged by ``(provider, model)`` identity (order preserved).
_PROVIDER_UNION_PATHS = frozenset({"fallback_providers", "auxiliary.vision.fallback_chain"})
_VERSION_KEY = "_config_version"
_PREVIEW_MAX = 60


@dataclass(frozen=True, slots=True)
class Conflict:
    """A key present in both configs whose values differ; the installer resolves it."""

    path: str
    kind: str  # "scalar" | "type" | "list"
    existing_preview: str
    incoming_preview: str
    sensitive: bool

    def as_json(self) -> dict[str, YamlValue]:
        return {
            "path": self.path,
            "kind": self.kind,
            "existing_preview": self.existing_preview,
            "incoming_preview": self.incoming_preview,
            "sensitive": self.sensitive,
        }


@dataclass(frozen=True, slots=True)
class MergePlan:
    """Result of planning a merge: the candidate config plus what changed / needs a decision."""

    strategy: str  # "copy" | "overwrite" | "merge"
    pristine: bool
    merged: YamlMap
    added: tuple[str, ...]
    list_appended: tuple[str, ...]
    conflicts: tuple[Conflict, ...]
    warnings: tuple[str, ...]


@dataclass(slots=True)
class _Acc:
    added: list[str] = field(default_factory=list)
    appended: list[str] = field(default_factory=list)
    conflicts: list[Conflict] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def normalized_text(config: YamlMap) -> str:
    """Canonical (sorted, block-style) YAML text — the basis for equality and hashing."""
    return dump_yaml(config)


def normalized_hash(config: YamlMap) -> str:
    """Stable ``sha256:`` digest of the normalized config, order/comment independent."""
    return "sha256:" + hashlib.sha256(normalized_text(config).encode("utf-8")).hexdigest()


def _sensitive(path: str) -> bool:
    low = path.lower()
    return any(tok in low for tok in _SENSITIVE_TOKENS)


def _preview(path: str, value: YamlValue) -> str:
    if _sensitive(path):
        return "<redacted>"
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, sort_keys=True)
    return text if len(text) <= _PREVIEW_MAX else text[: _PREVIEW_MAX - 1] + "\u2026"


def _identity(item: YamlValue) -> str:
    """Logical identity for provider-list union: ``(provider, model)`` when present, else the value."""
    if isinstance(item, dict) and ("provider" in item or "model" in item):
        return json.dumps([item.get("provider"), item.get("model")], ensure_ascii=False)
    return item if isinstance(item, str) else json.dumps(item, ensure_ascii=False, sort_keys=True)


def _merge_string_list(path: str, existing: list[YamlValue], incoming: list[YamlValue], acc: _Acc) -> list[YamlValue]:
    result = [copy.deepcopy(x) for x in existing]
    for item in incoming:
        if item not in result:
            result.append(copy.deepcopy(item))
            acc.appended.append(f"{path}[{item!r}]")
    return result


def _merge_provider_list(path: str, existing: list[YamlValue], incoming: list[YamlValue], acc: _Acc) -> list[YamlValue]:
    result = [copy.deepcopy(x) for x in existing]
    seen = {_identity(x): x for x in existing}
    for item in incoming:
        ident = _identity(item)
        if ident not in seen:
            result.append(copy.deepcopy(item))
            seen[ident] = item
            acc.appended.append(f"{path}[{ident}]")
        elif seen[ident] != item:
            acc.warnings.append(f"{path}: kept existing entry {ident} (distribution's differs)")
    return result


def _merge_list(path: str, existing: list[YamlValue], incoming: list[YamlValue], acc: _Acc) -> list[YamlValue]:
    if path in _STRING_UNION_PATHS:
        return _merge_string_list(path, existing, incoming, acc)
    if path in _PROVIDER_UNION_PATHS:
        return _merge_provider_list(path, existing, incoming, acc)
    if existing == incoming:
        return copy.deepcopy(existing)
    acc.conflicts.append(Conflict(path, "list", _preview(path, existing), _preview(path, incoming), _sensitive(path)))
    return copy.deepcopy(existing)


def _merge_map(existing: YamlMap, incoming: YamlMap, acc: _Acc, prefix: str = "") -> YamlMap:
    result: YamlMap = copy.deepcopy(existing)
    for key, inc in incoming.items():
        if key == _VERSION_KEY:
            continue  # reconciled separately — schema version is not a user preference
        path = f"{prefix}{key}"
        if key not in existing:
            result[key] = copy.deepcopy(inc)
            acc.added.append(path)
            continue
        cur = existing[key]
        if isinstance(cur, dict) and isinstance(inc, dict):
            result[key] = _merge_map(cur, inc, acc, prefix=f"{path}.")
        elif isinstance(cur, list) and isinstance(inc, list):
            result[key] = _merge_list(path, cur, inc, acc)
        elif isinstance(cur, dict) or isinstance(inc, dict) or isinstance(cur, list) or isinstance(inc, list):
            acc.conflicts.append(Conflict(path, "type", _preview(path, cur), _preview(path, inc), _sensitive(path)))
        elif cur != inc:
            acc.conflicts.append(Conflict(path, "scalar", _preview(path, cur), _preview(path, inc), _sensitive(path)))
    return result


def _reconcile_version(merged: YamlMap, existing: YamlMap, incoming: YamlMap, acc: _Acc) -> None:
    cur, inc = existing.get(_VERSION_KEY), incoming.get(_VERSION_KEY)
    if isinstance(inc, int) and (not isinstance(cur, int) or cur < inc):
        merged[_VERSION_KEY] = inc
    elif isinstance(cur, int) and isinstance(inc, int) and cur > inc:
        merged[_VERSION_KEY] = cur
        acc.warnings.append(f"{_VERSION_KEY}: kept existing {cur} (> distribution {inc}); distribution may be stale")


def is_pristine(existing: YamlMap, incoming: YamlMap, default: YamlMap | None, provenance_hash: str | None) -> bool:
    """Exact (never fuzzy) 'uncustomized' test: equal to what we last wrote, the incoming, or the default."""
    ex = normalized_hash(existing)
    return ex == provenance_hash or ex == normalized_hash(incoming) or (default is not None and ex == normalized_hash(default))


def plan_merge(
    existing: YamlMap, incoming: YamlMap, *, default: YamlMap | None = None, provenance_hash: str | None = None,
) -> MergePlan:
    """Plan an existing-preserving merge; overwrite outright when the target is provably pristine."""
    if not existing:
        return MergePlan("copy", True, copy.deepcopy(incoming), (), (), (), ())
    if is_pristine(existing, incoming, default, provenance_hash):
        return MergePlan("overwrite", True, copy.deepcopy(incoming), (), (), (), ())
    acc = _Acc()
    merged = _merge_map(existing, incoming, acc)
    _reconcile_version(merged, existing, incoming, acc)
    return MergePlan("merge", False, merged, tuple(acc.added), tuple(acc.appended), tuple(acc.conflicts), tuple(acc.warnings))


def _get_path(data: YamlMap, path: str) -> tuple[bool, YamlValue]:
    cur: YamlValue = data
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return False, None
        cur = cur[part]
    return True, cur


def _set_path(data: YamlMap, path: str, value: YamlValue) -> None:
    parts = path.split(".")
    cur = data
    for part in parts[:-1]:
        nxt = cur.get(part)
        if not isinstance(nxt, dict):
            nxt = {}
            cur[part] = nxt
        cur = nxt
    cur[parts[-1]] = value


def apply_decisions(existing: YamlMap, incoming: YamlMap, decisions: dict[str, str]) -> YamlMap:
    """Re-merge, then for each conflict the user resolved as 'incoming', take the incoming value."""
    acc = _Acc()
    merged = _merge_map(existing, incoming, acc)
    _reconcile_version(merged, existing, incoming, acc)
    for path, choice in decisions.items():
        if choice == "incoming":
            found, value = _get_path(incoming, path)
            if found:
                _set_path(merged, path, copy.deepcopy(value))
    return merged
