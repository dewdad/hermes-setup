"""Deterministic YAML/JSON IO.

The compiler must emit byte-stable output so ``dist/`` diffs cleanly in git. Every dump here
sorts keys and forces block style with a wide line so re-running ``compile`` never rewrites a
file that did not semantically change. ``allow_unicode`` keeps Hebrew content readable.
"""

from __future__ import annotations

import json
from pathlib import Path

import yaml

# A JSON/YAML value tree. Config fragments and MCP maps are genuinely free-form Hermes data,
# so this recursive alias is the honest boundary type (no ``Any``).
type YamlValue = str | int | float | bool | None | list["YamlValue"] | dict[str, "YamlValue"]
type YamlMap = dict[str, YamlValue]

_DUMP_WIDTH = 4096


def load_yaml(path: Path) -> YamlMap:
    """Parse a YAML file into a mapping. Raises if the top level is not a mapping."""
    text = path.read_text(encoding="utf-8")
    data = yaml.safe_load(text)
    if data is None:
        return {}
    if not isinstance(data, dict):
        msg = f"{path}: top-level YAML must be a mapping, got {type(data).__name__}"
        raise ValueError(msg)
    return data


def dump_yaml(data: YamlMap) -> str:
    """Serialize a mapping to deterministic block-style YAML with sorted keys."""
    return yaml.safe_dump(
        data,
        sort_keys=True,
        allow_unicode=True,
        default_flow_style=False,
        width=_DUMP_WIDTH,
    )


def dump_json(data: YamlValue) -> str:
    """Serialize to deterministic pretty JSON with a trailing newline."""
    return json.dumps(data, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def write_text(path: Path, text: str) -> None:
    """Write UTF-8 text with LF newlines, creating parent dirs. Idempotent for stable input."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
