"""Template manifest parsing + validation."""

from __future__ import annotations

import unittest

from configurator.errors import TemplateError
from configurator.model import SkillSourceKind, Template, TemplateKind
from configurator.parse import parse_template


class ParseHappyPath(unittest.TestCase):
    def test_minimal_base_template(self) -> None:
        tpl = parse_template({"name": "general", "kind": "base"})
        self.assertEqual(tpl.name, "general")
        self.assertEqual(tpl.kind, TemplateKind.BASE)
        self.assertIsNone(tpl.extends)

    def test_env_defaults_to_optional(self) -> None:
        tpl = parse_template({
            "name": "general",
            "kind": "base",
            "env": [{"name": "ZENMUX_API_KEY"}],
        })
        self.assertEqual(len(tpl.env), 1)
        self.assertFalse(tpl.env[0].required)
        self.assertEqual(tpl.env[0].name, "ZENMUX_API_KEY")

    def test_skill_ref_source_kind_parsed(self) -> None:
        tpl = parse_template({
            "name": "il",
            "kind": "locale",
            "extends": "base/general",
            "skills": {"include": [{"source": "official", "id": "official/security/1password"}]},
        })
        ref = tpl.skills.include[0]
        self.assertEqual(ref.source, SkillSourceKind.OFFICIAL)
        self.assertFalse(ref.vendored)

    def test_github_ref_is_vendored(self) -> None:
        tpl = parse_template({
            "name": "il",
            "kind": "locale",
            "extends": "base/general",
            "skills": {"include": [{"source": "github", "id": "org/repo/skills/x"}]},
        })
        self.assertTrue(tpl.skills.include[0].vendored)


class ParseValidation(unittest.TestCase):
    def test_missing_name_raises(self) -> None:
        with self.assertRaises(TemplateError):
            parse_template({"kind": "base"})

    def test_bad_kind_raises(self) -> None:
        with self.assertRaises(TemplateError):
            parse_template({"name": "x", "kind": "widget"})

    def test_base_with_extends_raises(self) -> None:
        with self.assertRaises(TemplateError):
            parse_template({"name": "x", "kind": "base", "extends": "y/z"})

    def test_non_base_without_extends_raises(self) -> None:
        with self.assertRaises(TemplateError):
            parse_template({"name": "x", "kind": "persona"})

    def test_bad_skill_source_raises(self) -> None:
        with self.assertRaises(TemplateError):
            parse_template({
                "name": "x",
                "kind": "base",
                "skills": {"include": [{"source": "ftp", "id": "a"}]},
            })

    def test_local_source_removed(self) -> None:
        # Reference-only model: authoring in-repo ('local') is no longer a valid source.
        with self.assertRaises(TemplateError):
            parse_template({
                "name": "x",
                "kind": "base",
                "skills": {"include": [{"source": "local", "id": "authored"}]},
            })

    def test_bundled_allowlist_parsed(self) -> None:
        tpl = parse_template({
            "name": "dev",
            "kind": "persona",
            "extends": "base/general",
            "skills": {"bundled": ["github-pr-workflow", "test-driven-development"]},
        })
        self.assertEqual(tpl.skills.bundled, ("github-pr-workflow", "test-driven-development"))


if __name__ == "__main__":
    unittest.main()
