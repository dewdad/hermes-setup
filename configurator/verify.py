"""``configurator verify`` — the build gates that CI and the DOX closeout depend on.

Gates: (1) secret scan over every emitted ``dist/`` config; (2) lockfile integrity — every vendored
skill is locked, redistributable, and hash-matched; (3) DOX chain — each durable-boundary dir has an
``AGENTS.md`` the root indexes, and no child weakens the root secret-hygiene rule.
"""

from __future__ import annotations

import re
from pathlib import Path

from configurator.errors import SecretLeakError
from configurator.loader import discover_templates, load_and_resolve
from configurator.locks import content_hash, lock_path, read_lock
from configurator.secretscan import scan_text
from configurator.sources import VENDOR_DIRNAME
from configurator.yamlio import load_yaml

_BOUNDARY_DIRS = ("templates", "configurator", "dist", "locks", "tests")
_FORBIDDEN_IN_DIST = (".env", "auth.json", "models.json", "desktop.json")
_SECRET_HYGIENE_MARK = "Secret hygiene"
_BINARY_SUFFIXES = frozenset({".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf", ".zip", ".gz", ".woff", ".woff2"})
# Root-level config.yaml keys Hermes recognizes (verified against the live schema). Unknowns warn.
_KNOWN_ROOT_KEYS = frozenset({
    "_config_version", "model", "providers", "fallback_model", "fallback_providers",
    "credential_pool_strategies", "toolsets", "agent", "terminal", "display", "compression",
    "delegation", "auxiliary", "moa", "custom_providers", "context", "memory", "gateway",
    "sessions", "streaming", "updates", "mcp_servers", "web", "browser", "skills", "security",
    "platforms", "plugins",
})
# A DOX child must not permit committing secrets (would weaken the root HARD rule).
_WEAKENING = re.compile(r"(?i)(commit|include|store|keep)[^\n]{0,40}\.env\b|secrets?[^\n]{0,20}(are|is)[^\n]{0,10}(ok|fine|allowed)")


def _secret_gate(root: Path, fails: list[str]) -> None:
    dist = root / "dist"
    if not dist.is_dir():
        return
    for path in sorted(p for p in dist.rglob("*") if p.is_file()):
        if path.suffix.lower() in _BINARY_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        try:
            scan_text(text, where=str(path.relative_to(root)))
        except SecretLeakError as err:
            fails.append(str(err))
    for name in _FORBIDDEN_IN_DIST:
        for hit in dist.rglob(name):
            fails.append(f"forbidden file committed in dist/: {hit.relative_to(root)}")
    # The repo-root profiles.json catalogue is generated + committed like dist/; scan it too.
    catalog = root / "profiles.json"
    if catalog.is_file():
        try:
            scan_text(catalog.read_text(encoding="utf-8"), where="profiles.json")
        except SecretLeakError as err:
            fails.append(str(err))


def _config_key_gate(root: Path) -> None:
    """Warn (never fail) on unknown top-level config.yaml keys — matches lenient live config check."""
    dist = root / "dist"
    if not dist.is_dir():
        return
    for config in sorted(dist.rglob("config.yaml")):
        data = load_yaml(config)
        for key in sorted(k for k in data if k not in _KNOWN_ROOT_KEYS):
            print(f"WARN: {config.relative_to(root)}: unknown config key '{key}'")


def _lock_gate(root: Path, fails: list[str]) -> None:
    registry = discover_templates(root / "templates")
    for ref in sorted(registry):
        merged = load_and_resolve(ref, registry)
        vendored = [s for s in merged.skills.include if s.vendored]
        if not vendored:
            continue
        lock = read_lock(lock_path(root, merged.name))
        for skill in vendored:
            entry = lock.get(skill.id)
            src = root / VENDOR_DIRNAME / (skill.category or "custom") / skill.skill_name
            if entry is None:
                fails.append(f"{merged.name}: vendored '{skill.id}' has no lock entry")
                continue
            if not entry.redistributable:
                fails.append(f"{merged.name}: '{skill.id}' non-redistributable but vendored")
            if src.is_dir() and entry.resolved != content_hash(src):
                fails.append(f"{merged.name}: '{skill.id}' content drifted from lock")


def _dox_gate(root: Path, fails: list[str]) -> None:
    root_doc = root / "AGENTS.md"
    if not root_doc.is_file():
        fails.append("root AGENTS.md missing")
        return
    root_text = root_doc.read_text(encoding="utf-8")
    if _SECRET_HYGIENE_MARK not in root_text:
        fails.append("root AGENTS.md missing the secret-hygiene rule")
    for boundary in _BOUNDARY_DIRS:
        child = root / boundary / "AGENTS.md"
        if not child.is_file():
            fails.append(f"missing DOX child: {boundary}/AGENTS.md")
            continue
        if f"{boundary}/AGENTS.md" not in root_text:
            fails.append(f"root Child DOX Index does not resolve {boundary}/AGENTS.md")
        if _WEAKENING.search(child.read_text(encoding="utf-8")):
            fails.append(f"{boundary}/AGENTS.md weakens the root secret-hygiene rule")


def run_verify(root: Path) -> int:
    """Run every gate, print all failures, and return a process exit code (0 clean, 1 failed)."""
    fails: list[str] = []
    _config_key_gate(root)
    _secret_gate(root, fails)
    _lock_gate(root, fails)
    _dox_gate(root, fails)
    if fails:
        for line in fails:
            print(f"FAIL: {line}")
        print(f"verify: {len(fails)} failure(s)")
        return 1
    print("verify: all gates passed")
    return 0
