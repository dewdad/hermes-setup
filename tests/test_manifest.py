"""distribution.yaml manifest ownership + install-list shape (G1: meta-skills owned, skills not)."""

from __future__ import annotations

import unittest

from configurator.manifest import (
    DEFAULT_DIST_OWNED,
    build_manifest,
    build_skills_install,
)
from configurator.parse import parse_template


def _tpl(**extra: object) -> object:
    data: dict[str, object] = {"name": "general", "kind": "base",
                               "distribution": {"version": "1.2.0"}}
    data.update(extra)
    return parse_template(data)  # type: ignore[arg-type]


class OwnedPaths(unittest.TestCase):
    def test_meta_skills_always_owned(self) -> None:
        # The generated finish-setup meta-skill lives under meta-skills/ and is distribution-owned
        # so `hermes profile update` refreshes it.
        owned = build_manifest(_tpl())["distribution_owned"]  # type: ignore[arg-type]
        self.assertIn("meta-skills", owned)

    def test_skills_never_owned_without_vendored(self) -> None:
        # G1 (proven): Hermes' updater wholesale-replaces any shipped top-level dir it owns. `skills`
        # must NOT be owned/shipped or `profile update` would wipe the user's installed skills.
        owned = build_manifest(_tpl(post_install=[{"id": "a/b/c"}]))["distribution_owned"]  # type: ignore[arg-type]
        self.assertNotIn("skills", owned)

    def test_defaults_and_readme_present(self) -> None:
        owned = build_manifest(_tpl())["distribution_owned"]  # type: ignore[arg-type]
        for base in DEFAULT_DIST_OWNED:
            self.assertIn(base, owned)
        self.assertIn("README.md", owned)

    def test_owned_is_sorted_stable(self) -> None:
        owned = build_manifest(_tpl(post_install=[{"id": "a/b/c"}]))["distribution_owned"]  # type: ignore[arg-type]
        self.assertEqual(owned, sorted(owned))

    def test_post_install_adds_install_json_ownership(self) -> None:
        owned = build_manifest(_tpl(post_install=[{"id": "a/b/c"}]))["distribution_owned"]  # type: ignore[arg-type]
        self.assertIn("skills.install.json", owned)

    def test_setup_steps_add_generated_scripts_to_ownership(self) -> None:
        owned = build_manifest(_tpl(setup_steps=[{"id": "rtk"}]))["distribution_owned"]  # type: ignore[arg-type]
        self.assertIn("setup.steps.ps1", owned)
        self.assertIn("setup.steps.sh", owned)

    def test_no_setup_steps_no_scripts_owned(self) -> None:
        owned = build_manifest(_tpl())["distribution_owned"]  # type: ignore[arg-type]
        self.assertNotIn("setup.steps.sh", owned)


class InstallList(unittest.TestCase):
    def test_tier_and_tap_flags_serialized(self) -> None:
        tpl = _tpl(post_install=[
            {"id": "a/b/c", "note": "n0", "tier": 0},
            {"id": "obra/superpowers", "tap": True, "tier": 1},
        ])
        skills = build_skills_install(tpl)["skills"]  # type: ignore[arg-type]
        self.assertEqual([s["id"] for s in skills], ["a/b/c", "obra/superpowers"])
        self.assertFalse(skills[0]["tap"])
        self.assertTrue(skills[1]["tap"])


class Manifest(unittest.TestCase):
    def test_name_version_hermes_requires(self) -> None:
        manifest = build_manifest(_tpl())  # type: ignore[arg-type]
        self.assertEqual(manifest["name"], "general")
        self.assertEqual(manifest["version"], "1.2.0")
        self.assertEqual(manifest["hermes_requires"], ">=0.18.0")


if __name__ == "__main__":
    unittest.main()
