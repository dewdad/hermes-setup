"""Lockfile provenance for vendored skills.

``locks/<template>.lock.json`` pins each vendored skill by content hash + provenance so ``compile``
is offline-reproducible. ``--update-locks`` is the only writer. A ``redistributable: false`` entry
that was vendored (rather than referenced post-install) fails the build.
"""

from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path

from configurator.errors import LockError
from configurator.yamlio import dump_json, YamlMap


@dataclass(frozen=True, slots=True)
class LockEntry:
    """One vendored skill's pinned provenance."""

    source_id: str
    resolved: str
    fetched_at: str
    license: str
    redistributable: bool


def content_hash(directory: Path) -> str:
    """Deterministic ``sha256:`` hash over the sorted (relpath, bytes) of every file in a dir."""
    digest = sha256()
    for path in sorted(p for p in directory.rglob("*") if p.is_file()):
        digest.update(path.relative_to(directory).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return "sha256:" + digest.hexdigest()


def lock_path(root: Path, template_name: str) -> Path:
    """Path to a template's lockfile under ``locks/``."""
    return root / "locks" / f"{template_name}.lock.json"


def read_lock(path: Path) -> dict[str, LockEntry]:
    """Load a lockfile into a ``source_id -> LockEntry`` mapping (empty if the file is absent)."""
    if not path.is_file():
        return {}
    import json  # noqa: PLC0415 (stdlib, local to keep module surface small)

    raw = json.loads(path.read_text(encoding="utf-8"))
    skills = raw.get("skills", {}) if isinstance(raw, dict) else {}
    out: dict[str, LockEntry] = {}
    for source_id, entry in skills.items():
        out[source_id] = LockEntry(
            source_id=source_id,
            resolved=str(entry.get("resolved_commit_or_hash", entry.get("resolved", ""))),
            fetched_at=str(entry.get("fetched_at", "")),
            license=str(entry.get("license", "")),
            redistributable=bool(entry.get("redistributable", True)),
        )
    return out


def write_lock(path: Path, entries: dict[str, LockEntry]) -> None:
    """Write a lockfile deterministically (sorted keys)."""
    skills: YamlMap = {
        entry.source_id: {
            "source_id": entry.source_id,
            "resolved_commit_or_hash": entry.resolved,
            "fetched_at": entry.fetched_at,
            "license": entry.license,
            "redistributable": entry.redistributable,
        }
        for entry in entries.values()
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dump_json({"skills": skills}), encoding="utf-8", newline="\n")


def assert_redistributable(entries: dict[str, LockEntry], template_name: str) -> None:
    """Raise if any locked (vendored) skill is marked non-redistributable."""
    for entry in entries.values():
        if not entry.redistributable:
            raise LockError(
                lock=template_name,
                reason=f"'{entry.source_id}' is non-redistributable and must be referenced "
                "post-install, not vendored",
            )
