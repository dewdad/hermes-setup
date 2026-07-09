"""profiles.json catalogue: shape, determinism, secret-freedom, and committed-matches-fresh."""

from __future__ import annotations

import unittest

from configurator.catalog import CATALOG_FILENAME, SCHEMA_ID, build_catalog
from configurator.compile import REPO_ROOT
from configurator.loader import discover_templates, load_and_resolve
from configurator.model import Template
from configurator.parse import parse_template
from configurator.secretscan import scan_text
from configurator.yamlio import dump_json


def _tpl(name: str, **dist: object) -> Template:
    data: dict[str, object] = {"name": name, "kind": "base", "distribution": dict(dist)}
    return parse_template(data)  # type: ignore[arg-type]


class CatalogShape(unittest.TestCase):
    def test_top_level_keys(self) -> None:
        cat = build_catalog([_tpl("general", description="Base agent", version="1.0.0")])
        self.assertEqual(cat["schema"], SCHEMA_ID)
        self.assertEqual(cat["hermes_requires"], ">=0.18.0")
        self.assertIn("agent_instructions", cat)
        self.assertIn("install", cat)
        self.assertIsInstance(cat["profiles"], list)

    def test_profile_entry_fields(self) -> None:
        cat = build_catalog([_tpl("il-legal", description="Israeli legal", version="2.1.0")])
        entry = cat["profiles"][0]  # type: ignore[index]
        self.assertEqual(entry["name"], "il-legal")
        self.assertEqual(entry["kind"], "base")
        self.assertEqual(entry["version"], "2.1.0")
        self.assertEqual(entry["description"], "Israeli legal")
        self.assertEqual(entry["path"], "dist/il-legal")
        self.assertEqual(
            entry["local_install_command"],
            "hermes profile install ./dist/il-legal --name il-legal --yes",
        )

    def test_standalone_commands_use_placeholders_and_name(self) -> None:
        entry = build_catalog([_tpl("il-legal")])["profiles"][0]  # type: ignore[index]
        posix = entry["standalone_posix_command"]
        windows = entry["standalone_windows_command"]
        # Name is substituted, but repo URLs stay placeholders (no hard-coded org — contract).
        self.assertIn("<RAW_REPO_URL>", posix)
        self.assertIn("<REPO_GIT_URL>", posix)
        self.assertIn(" il-legal ", posix)
        self.assertIn("--yes", posix)
        self.assertIn("<RAW_REPO_URL>", windows)
        self.assertIn("<REPO_GIT_URL>", windows)
        self.assertIn("il-legal", windows)
        self.assertIn("-Yes", windows)

    def test_no_hardcoded_url_anywhere(self) -> None:
        # The whole catalogue must never leak a concrete host/org.
        text = dump_json(build_catalog([_tpl("general", description="d", version="1.0.0")]))
        for leaked in ("github.com", "raw.githubusercontent.com", "https://", "http://"):
            self.assertNotIn(leaked, text)

    def test_description_and_version_fallback(self) -> None:
        entry = build_catalog([_tpl("bare")])["profiles"][0]  # type: ignore[index]
        self.assertEqual(entry["description"], "bare")  # falls back to name
        self.assertEqual(entry["version"], "0.1.0")  # falls back to default

    def test_profiles_sorted_by_name(self) -> None:
        cat = build_catalog([_tpl("zeta"), _tpl("alpha"), _tpl("mid")])
        names = [p["name"] for p in cat["profiles"]]  # type: ignore[index]
        self.assertEqual(names, ["alpha", "mid", "zeta"])

    def test_deterministic_and_secret_free(self) -> None:
        templates = [_tpl("general", description="d", version="1.0.0"), _tpl("il")]
        first = dump_json(build_catalog(templates))
        second = dump_json(build_catalog(templates))
        self.assertEqual(first, second)
        scan_text(first, where=CATALOG_FILENAME)  # must not raise


class ApplyModes(unittest.TestCase):
    def test_free_profile_supports_free_and_pro(self) -> None:
        entry = build_catalog([_tpl("developer")])["profiles"][0]  # type: ignore[index]
        self.assertEqual(entry["apply_modes"], ["free", "pro"])

    def test_portal_base_is_pro_only(self) -> None:
        tpl = parse_template({"name": "general-pro", "kind": "base", "portal_auth": True})  # type: ignore[arg-type]
        entry = build_catalog([tpl])["profiles"][0]  # type: ignore[index]
        self.assertEqual(entry["apply_modes"], ["pro"])


class CatalogGolden(unittest.TestCase):
    def test_committed_catalog_matches_fresh(self) -> None:
        templates_root = REPO_ROOT / "templates"
        committed = REPO_ROOT / CATALOG_FILENAME
        if not templates_root.is_dir() or not committed.is_file():
            self.skipTest("templates/ or profiles.json not present in this checkout")
        registry = discover_templates(templates_root)
        resolved = [load_and_resolve(ref, registry) for ref in sorted(registry)]
        fresh = dump_json(build_catalog(resolved))
        self.assertEqual(
            fresh,
            committed.read_text(encoding="utf-8"),
            "stale committed profiles.json — run `python -m configurator compile --all`",
        )


if __name__ == "__main__":
    unittest.main()
