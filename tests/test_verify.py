"""verify gates: DOX chain + secret scan over dist/."""

from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from configurator.verify import run_verify

_BOUNDARIES = ("templates", "configurator", "dist", "locks", "tests")


def _clean_repo(root: Path) -> None:
    child_index = "\n".join(f"- `{b}/AGENTS.md`" for b in _BOUNDARIES)
    (root / "AGENTS.md").write_text(
        f"# root\n## Secret hygiene\nnever emit secrets.\n## Child DOX Index\n{child_index}\n",
        encoding="utf-8",
    )
    for boundary in _BOUNDARIES:
        (root / boundary).mkdir()
        (root / boundary / "AGENTS.md").write_text(f"# {boundary}\n", encoding="utf-8")


class Gates(unittest.TestCase):
    def test_clean_repo_passes(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _clean_repo(root)
            self.assertEqual(run_verify(root), 0)

    def test_missing_child_dox_fails(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _clean_repo(root)
            (root / "tests" / "AGENTS.md").unlink()
            self.assertEqual(run_verify(root), 1)

    def test_secret_literal_in_dist_fails(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _clean_repo(root)
            (root / "dist" / "x").mkdir()
            (root / "dist" / "x" / "config.yaml").write_text(
                "providers:\n  y:\n    api_key: AKIAIOSFODNN7EXAMPLE1234\n", encoding="utf-8",
            )
            self.assertEqual(run_verify(root), 1)


if __name__ == "__main__":
    unittest.main()
