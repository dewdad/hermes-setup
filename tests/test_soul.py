"""SOUL.md composition from ordered fragments with the 20k cap."""

from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from configurator.errors import TemplateError
from configurator.model import SoulFragment
from configurator.soul import compose_soul


class Compose(unittest.TestCase):
    def test_fragments_joined_in_order(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.md").write_text("# Identity\nI am A.", encoding="utf-8")
            (root / "b.md").write_text("# Style\nI speak B.", encoding="utf-8")
            frags = (
                SoulFragment(name="a.md", path=root / "a.md"),
                SoulFragment(name="b.md", path=root / "b.md"),
            )
            result = compose_soul(frags, "demo")
            self.assertEqual(result, "# Identity\nI am A.\n\n# Style\nI speak B.\n")

    def test_empty_fragments_yield_empty_string(self) -> None:
        self.assertEqual(compose_soul((), "demo"), "")

    def test_missing_fragment_file_raises(self) -> None:
        frag = SoulFragment(name="ghost.md", path=Path("does-not-exist-xyz.md"))
        with self.assertRaises(TemplateError):
            compose_soul((frag,), "demo")

    def test_cap_exceeded_raises(self) -> None:
        with TemporaryDirectory() as tmp:
            big = Path(tmp) / "big.md"
            big.write_text("x" * 20_001, encoding="utf-8")
            frag = SoulFragment(name="big.md", path=big)
            with self.assertRaises(TemplateError):
                compose_soul((frag,), "demo")


if __name__ == "__main__":
    unittest.main()
