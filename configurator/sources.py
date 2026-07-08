"""Skill vendoring + lock management (bucket 1).

``compile`` calls :func:`vendor_skills` which reads the committed ``skills-vendor/`` cache offline
and verifies each vendored skill against its lock. ``update-locks`` is the only network path: it
(re-)fetches from the recorded source into ``skills-vendor/`` and rewrites ``locks/<template>.json``.
Referenced skills (OFFICIAL/TAP) are never vendored — they surface in the distribution README.
"""

from __future__ import annotations

import re
from datetime import UTC, datetime
from pathlib import Path

import yaml

from configurator.errors import LockError, SourceError
from configurator.fetch import fetch_github, fetch_url, resolve_well_known
from configurator.loader import discover_templates, load_and_resolve, ref_for_name
from configurator.locks import (
    LockEntry,
    assert_redistributable,
    content_hash,
    lock_path,
    read_lock,
    write_lock,
)
from configurator.model import SkillRef, SkillSourceKind, Template

VENDOR_DIRNAME = "skills-vendor"

# Obvious exfil / remote-code-execution patterns. Conservative — legit skill scripts do not pipe
# network downloads straight into a shell, decode base64 into a shell, fork-bomb, or rm -rf /.
_DANGEROUS = re.compile(
    r"(curl|wget)\b[^\n|]*\|\s*(ba)?sh"
    r"|base64\s+-d[^\n|]*\|\s*(ba)?sh"
    r"|eval\s+\"\$\((curl|wget)"
    r"|:\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:"
    r"|rm\s+-rf\s+(/|~)(\s|$)"
    r"|>\s*/dev/tcp/",
)
_SCREEN_SUFFIXES = frozenset({".md", ".sh", ".py", ".js", ".ps1", ".bat", ".txt", ""})


def _vendor_dir(root: Path, ref: SkillRef) -> Path:
    return root / VENDOR_DIRNAME / (ref.category or "custom") / ref.skill_name


def _screen_dangerous(skill_dir: Path, source_id: str) -> None:
    """Reject a vendored skill whose text files contain obvious exfil / RCE patterns."""
    for path in sorted(p for p in skill_dir.rglob("*") if p.is_file()):
        if path.suffix.lower() not in _SCREEN_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        match = _DANGEROUS.search(text)
        if match is not None:
            raise SourceError(
                source_id=source_id,
                reason=f"dangerous pattern in {path.name}: {match.group(0)!r}",
            )


def _validate_frontmatter(skill_dir: Path, source_id: str) -> None:
    """Ensure the vendored skill has a SKILL.md with the required name + description frontmatter."""
    md = skill_dir / "SKILL.md"
    if not md.is_file():
        raise SourceError(source_id=source_id, reason=f"no SKILL.md in {skill_dir}")
    text = md.read_text(encoding="utf-8")
    if not text.startswith("---"):
        raise SourceError(source_id=source_id, reason="SKILL.md missing YAML frontmatter")
    _, _, rest = text.partition("---")
    block, sep, _ = rest.partition("\n---")
    if not sep:
        raise SourceError(source_id=source_id, reason="SKILL.md frontmatter is not closed")
    meta = yaml.safe_load(block) or {}
    if not isinstance(meta, dict) or not meta.get("name") or not meta.get("description"):
        raise SourceError(source_id=source_id, reason="frontmatter needs 'name' and 'description'")


def vendor_skills(template: Template, root: Path) -> list[tuple[str, Path]]:
    """Return (rel_dest, src_dir) payloads for every vendored skill, verifying locks offline."""
    lock = read_lock(lock_path(root, template.name))
    assert_redistributable(lock, template.name)
    payloads: list[tuple[str, Path]] = []
    for ref in template.skills.include:
        if not ref.vendored:
            continue
        src = _vendor_dir(root, ref)
        if not src.is_dir():
            raise SourceError(
                source_id=ref.id,
                reason=f"vendored content missing at {src.relative_to(root)}; run update-locks",
            )
        _validate_frontmatter(src, ref.id)
        _screen_dangerous(src, ref.id)
        entry = lock.get(ref.id)
        if entry is None:
            raise LockError(lock=template.name, reason=f"'{ref.id}' has no lock entry; run update-locks")
        if entry.resolved != content_hash(src):
            raise LockError(lock=template.name, reason=f"'{ref.id}' drifted from lock; run update-locks")
        payloads.append((f"{ref.category or 'custom'}/{ref.skill_name}", src))
    return payloads


def _fetch_ref(ref: SkillRef, dest: Path) -> None:
    match ref.source:
        case SkillSourceKind.URL:
            fetch_url(ref.id, dest, ref.id)
        case SkillSourceKind.WELL_KNOWN:
            fetch_url(resolve_well_known(ref.id, ref.id), dest, ref.id)
        case SkillSourceKind.GITHUB:
            parts = ref.id.split("/")
            if len(parts) < 3:
                raise SourceError(source_id=ref.id, reason="github id must be owner/repo/subpath...")
            fetch_github("/".join(parts[:2]), "/".join(parts[2:]), ref.ref, dest, ref.id)
        case SkillSourceKind.OFFICIAL | SkillSourceKind.TAP:
            raise SourceError(source_id=ref.id, reason="referenced source is never vendored")


def _lock_one(template: Template, root: Path) -> dict[str, LockEntry]:
    entries: dict[str, LockEntry] = {}
    now = datetime.now(UTC).isoformat(timespec="seconds")
    for ref in template.skills.include:
        if not ref.vendored:
            continue
        dest = _vendor_dir(root, ref)
        _fetch_ref(ref, dest)
        _validate_frontmatter(dest, ref.id)
        _screen_dangerous(dest, ref.id)
        entries[ref.id] = LockEntry(
            source_id=ref.id,
            resolved=content_hash(dest),
            fetched_at=now,
            license=ref.license or "",
            redistributable=ref.redistributable,
        )
    return entries


def update_locks(root: Path, targets: list[str]) -> int:
    """Re-resolve vendored skills and rewrite lockfiles. Returns a process exit code."""
    registry = discover_templates(root / "templates")
    refs = sorted(registry) if not targets else [ref_for_name(t, registry) for t in targets]
    for ref in refs:
        merged = load_and_resolve(ref, registry)
        entries = _lock_one(merged, root)
        assert_redistributable(entries, merged.name)
        path = lock_path(root, merged.name)
        if entries:
            write_lock(path, entries)
            print(f"locked {merged.name}: {len(entries)} vendored skill(s)")
        elif path.is_file():
            path.unlink()
            print(f"pruned {merged.name}: no vendored skills (orphan lock removed)")
        else:
            print(f"skipped {merged.name}: no vendored skills")
    return 0
