"""Golden output: recompiling every real template reproduces the committed dist/ byte-for-byte."""

from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from configurator.compile import REPO_ROOT
from configurator.emit import emit_distribution
from configurator.loader import discover_templates, load_and_resolve
from configurator.sources import vendor_skills


class Golden(unittest.TestCase):
    def test_committed_dist_matches_fresh_compile(self) -> None:
        templates_root = REPO_ROOT / "templates"
        dist_root = REPO_ROOT / "dist"
        if not templates_root.is_dir() or not dist_root.is_dir():
            self.skipTest("templates/ or dist/ not present in this checkout")
        registry = discover_templates(templates_root)
        self.assertTrue(registry, "no templates discovered")
        with TemporaryDirectory() as tmp:
            fresh = Path(tmp)
            for ref in sorted(registry):
                merged = load_and_resolve(ref, registry)
                emit_distribution(merged, fresh / merged.name, vendor_skills(merged, REPO_ROOT))
                committed = dist_root / merged.name
                self.assertTrue(committed.is_dir(), f"dist/{merged.name} not committed")
                for produced in sorted(p for p in (fresh / merged.name).rglob("*") if p.is_file()):
                    rel = produced.relative_to(fresh / merged.name)
                    target = committed / rel
                    self.assertTrue(target.is_file(), f"missing in committed dist: {merged.name}/{rel}")
                    self.assertEqual(
                        produced.read_bytes(), target.read_bytes(),
                        f"stale committed dist: {merged.name}/{rel} — run `python -m configurator compile --all`",
                    )


if __name__ == "__main__":
    unittest.main()
