"""Per-distribution README: install block, prerequisites + /finish-setup pointer, skill ids."""

import unittest

from configurator.parse import parse_template
from configurator.readme import build_readme


def _tpl(**extra: object) -> object:
    raw: dict[str, object] = {"name": "general", "kind": "base"}
    raw.update(extra)
    return parse_template(raw)


class ReadmeContent(unittest.TestCase):
    def test_install_command_present(self) -> None:
        text = build_readme(_tpl())  # type: ignore[arg-type]
        self.assertIn("hermes profile install <path-or-git-url> --name general", text)

    def test_finish_setup_and_portal_pointer(self) -> None:
        text = build_readme(_tpl())  # type: ignore[arg-type]
        self.assertIn("/finish-setup", text)
        self.assertIn("hermes setup --portal", text)

    def test_post_install_ids_present(self) -> None:
        text = build_readme(  # type: ignore[arg-type]
            _tpl(post_install=[{"id": "skills-sh/x/y/z", "note": "n"}])
        )
        self.assertIn("hermes skills install skills-sh/x/y/z", text)

    def test_deterministic(self) -> None:
        self.assertEqual(
            build_readme(_tpl()),  # type: ignore[arg-type]
            build_readme(_tpl()),  # type: ignore[arg-type]
        )


if __name__ == "__main__":
    unittest.main()
