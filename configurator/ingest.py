"""Report drift between the live Hermes ``config.yaml`` and the resolved ``base/general`` template.

This replaces the old "re-mirror from the live install" flow. It reads the live ``config.yaml``
**only** — never ``.env``, ``auth.json``, ``models.json``, ``desktop.json``, or any runtime state.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from configurator import CONFIG_VERSION
from configurator.errors import ConfiguratorError
from configurator.loader import discover_templates, load_and_resolve
from configurator.yamlio import YamlMap, YamlValue, load_yaml


@dataclass(frozen=True, slots=True)
class DriftReport:
    """Flat drift between two config trees, keyed by dotted leaf path."""

    only_in_base: dict[str, YamlValue] = field(default_factory=dict)
    only_in_live: dict[str, YamlValue] = field(default_factory=dict)
    changed: dict[str, tuple[YamlValue, YamlValue]] = field(default_factory=dict)

    @property
    def clean(self) -> bool:
        return not (self.only_in_base or self.only_in_live or self.changed)


def _flatten(data: YamlMap, prefix: str = "") -> dict[str, YamlValue]:
    out: dict[str, YamlValue] = {}
    for key, value in data.items():
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            out.update(_flatten(value, path))
        else:
            out[path] = value
    return out


def compute_drift(base: YamlMap, live: YamlMap) -> DriftReport:
    """Diff two config trees at leaf granularity (lists compared whole)."""
    flat_base, flat_live = _flatten(base), _flatten(live)
    base_keys, live_keys = set(flat_base), set(flat_live)
    return DriftReport(
        only_in_base={k: flat_base[k] for k in sorted(base_keys - live_keys)},
        only_in_live={k: flat_live[k] for k in sorted(live_keys - base_keys)},
        changed={
            k: (flat_base[k], flat_live[k])
            for k in sorted(base_keys & live_keys)
            if flat_base[k] != flat_live[k]
        },
    )


def _hermes_home() -> Path:
    env = os.environ.get("HERMES_HOME")
    if env:
        return Path(env)
    local = os.environ.get("LOCALAPPDATA")
    if local and (Path(local) / "hermes").is_dir():
        return Path(local) / "hermes"
    return Path.home() / ".hermes"


def read_live_config(home: Path, profile: str | None) -> YamlMap:
    """Read ONLY ``config.yaml`` for the default home or a named profile. Reads no other file."""
    config = home / "profiles" / profile / "config.yaml" if profile else home / "config.yaml"
    if not config.is_file():
        raise ConfiguratorError(f"live config.yaml not found at {config}")
    return load_yaml(config)


def run_ingest(root: Path, profile: str | None) -> int:
    """Print a reviewable drift diff of the live config vs resolved base/general. Never reads secrets."""
    registry = discover_templates(root / "templates")
    base = load_and_resolve("base/general", registry)
    base_config: YamlMap = {**base.config, "_config_version": CONFIG_VERSION}
    live = read_live_config(_hermes_home(), profile)
    report = compute_drift(base_config, live)
    if report.clean:
        print("no drift: live config matches base/general")
        return 0
    for key, (was, now) in report.changed.items():
        print(f"~ {key}: base={was!r} live={now!r}")
    for key, value in report.only_in_live.items():
        print(f"+ live-only {key}={value!r}")
    for key, value in report.only_in_base.items():
        print(f"- base-only {key}={value!r}")
    return 0
