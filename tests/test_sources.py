"""Vendoring, frontmatter validation, and lockfile provenance."""

from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from configurator.errors import LockError, SourceError
from configurator.locks import (
    LockEntry,
    assert_redistributable,
    content_hash,
    lock_path,
    read_lock,
    write_lock,
)
from configurator.parse import parse_template
from configurator.sources import vendor_skills


def _skill(root: Path, category: str, name: str, *, valid: bool = True) -> None:
    d = root / "skills-vendor" / category / name
    d.mkdir(parents=True)
    body = (
        f"---\nname: {name}\ndescription: A real skill.\n---\n# {name}\n"
        if valid
        else f"# {name}\nno frontmatter\n"
    )
    (d / "SKILL.md").write_text(body, encoding="utf-8")


def _tpl(category: str, name: str) -> object:
    return parse_template({
        "name": "demo",
        "kind": "base",
        "skills": {"include": [
            {"source": "github", "id": name, "category": category, "redistributable": True},
        ]},
    })


class Hashing(unittest.TestCase):
    def test_content_hash_is_stable_and_prefixed(self) -> None:
        with TemporaryDirectory() as tmp:
            d = Path(tmp) / "s"
            d.mkdir()
            (d / "a.txt").write_text("x", encoding="utf-8")
            h1 = content_hash(d)
            h2 = content_hash(d)
            self.assertTrue(h1.startswith("sha256:"))
            self.assertEqual(h1, h2)


class LockRoundTrip(unittest.TestCase):
    def test_write_then_read(self) -> None:
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "demo.lock.json"
            entry = LockEntry("skill-x", "sha256:abc", "2026-01-01T00:00:00+00:00", "MIT", True)
            write_lock(path, {"skill-x": entry})
            loaded = read_lock(path)
            self.assertEqual(loaded["skill-x"], entry)

    def test_non_redistributable_fails(self) -> None:
        entry = LockEntry("doc", "sha256:x", "t", "proprietary", False)
        with self.assertRaises(LockError):
            assert_redistributable({"doc": entry}, "demo")


class VendorSkills(unittest.TestCase):
    def test_returns_payload_for_valid_local_skill(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _skill(root, "research", "widget", valid=True)
            src = root / "skills-vendor" / "research" / "widget"
            write_lock(lock_path(root, "demo"), {
                "widget": LockEntry("widget", content_hash(src), "t", "MIT", True),
            })
            payloads = vendor_skills(_tpl("research", "widget"), root)  # type: ignore[arg-type]
            self.assertEqual(len(payloads), 1)
            self.assertEqual(payloads[0][0], "research/widget")

    def test_missing_lock_entry_fails(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _skill(root, "research", "unlocked", valid=True)
            with self.assertRaises(LockError):
                vendor_skills(_tpl("research", "unlocked"), root)  # type: ignore[arg-type]

    def test_missing_content_raises(self) -> None:
        with TemporaryDirectory() as tmp:
            with self.assertRaises(SourceError):
                vendor_skills(_tpl("research", "ghost"), Path(tmp))  # type: ignore[arg-type]

    def test_invalid_frontmatter_raises(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _skill(root, "research", "bad", valid=False)
            with self.assertRaises(SourceError):
                vendor_skills(_tpl("research", "bad"), root)  # type: ignore[arg-type]


if __name__ == "__main__":
    unittest.main()
