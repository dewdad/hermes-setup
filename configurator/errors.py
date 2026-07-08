"""Typed error hierarchy for the configurator.

Every failure carries structured fields (never a bare string) and propagates to the CLI
boundary in ``compile.main``, which renders it and returns a non-zero exit code.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import override


class ConfiguratorError(Exception):
    """Base class for every configurator failure."""


@dataclass(slots=True)
class TemplateError(ConfiguratorError):
    """A template manifest is missing a field, has a bad value, or violates the schema."""

    template: str
    field: str
    reason: str

    @override
    def __str__(self) -> str:
        return f"template '{self.template}': field '{self.field}': {self.reason}"


@dataclass(slots=True)
class MergeError(ConfiguratorError):
    """Inheritance resolution failed (cycle, missing parent, or illegal kind ordering)."""

    template: str
    reason: str

    @override
    def __str__(self) -> str:
        return f"inheritance for '{self.template}': {self.reason}"


@dataclass(slots=True)
class SecretLeakError(ConfiguratorError):
    """A key-shaped literal was found in emitted output; the build must fail."""

    where: str
    key_path: str
    hint: str

    @override
    def __str__(self) -> str:
        return f"secret-shaped literal in {self.where} at '{self.key_path}': {self.hint}"


@dataclass(slots=True)
class SourceError(ConfiguratorError):
    """A skill source could not be resolved, fetched, or validated."""

    source_id: str
    reason: str

    @override
    def __str__(self) -> str:
        return f"skill source '{self.source_id}': {self.reason}"


@dataclass(slots=True)
class LockError(ConfiguratorError):
    """A lockfile is missing, stale, or records a non-redistributable vendored skill."""

    lock: str
    reason: str

    @override
    def __str__(self) -> str:
        return f"lock '{self.lock}': {self.reason}"


@dataclass(slots=True)
class VerifyError(ConfiguratorError):
    """A ``configurator verify`` gate failed (config, secret, lock, or DOX chain)."""

    gate: str
    reason: str

    @override
    def __str__(self) -> str:
        return f"verify gate '{self.gate}': {self.reason}"
