"""End-to-end: discover a templates tree, resolve inheritance, emit distributions."""

from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import yaml

from configurator.compile import run
from configurator.loader import discover_templates, load_and_resolve


def _make_tree(root: Path) -> None:
    base = root / "templates" / "base" / "general"
    (base / "soul").mkdir(parents=True)
    (base / "soul" / "identity.md").write_text("I am the base.", encoding="utf-8")
    (base / "template.yaml").write_text(
        "name: general\nkind: base\n"
        "distribution: {description: Base, version: 1.0.0}\n"
        "config: {model: {provider: zenmux}}\n"
        "env: [{name: ZENMUX_API_KEY, required: false}]\n"
        "soul: {fragments: [identity.md]}\n"
        "skills: {bundled: none}\n",
        encoding="utf-8",
    )
    loc = root / "templates" / "locale" / "il"
    (loc / "soul").mkdir(parents=True)
    (loc / "soul" / "he.md").write_text("אני מדבר עברית.", encoding="utf-8")
    (loc / "template.yaml").write_text(
        "name: il\nkind: locale\nextends: base/general\n"
        "config: {model: {default: anthropic/claude-sonnet-5-free}}\n"
        "soul: {fragments: [he.md]}\n",
        encoding="utf-8",
    )


class Discovery(unittest.TestCase):
    def test_discovers_all_templates_by_ref(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_tree(root)
            registry = discover_templates(root / "templates")
            self.assertIn("base/general", registry)
            self.assertIn("locale/il", registry)

    def test_resolve_inherits_and_appends_soul(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_tree(root)
            registry = discover_templates(root / "templates")
            merged = load_and_resolve("locale/il", registry)
            self.assertEqual(merged.config["model"], {
                "provider": "zenmux", "default": "anthropic/claude-sonnet-5-free",
            })
            self.assertEqual([f.name for f in merged.soul], ["identity.md", "he.md"])


class RunCompile(unittest.TestCase):
    def test_compile_all_emits_dist(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_tree(root)
            written = run(root=root, targets=(), all_templates=True, dry_run=False)
            self.assertEqual(set(written), {"general", "il"})
            manifest = yaml.safe_load(
                (root / "dist" / "il" / "distribution.yaml").read_text(encoding="utf-8"),
            )
            self.assertEqual(manifest["name"], "il")
            soul = (root / "dist" / "il" / "SOUL.md").read_text(encoding="utf-8")
            self.assertIn("עברית", soul)

    def test_compile_second_run_is_identical(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_tree(root)
            run(root=root, targets=(), all_templates=True, dry_run=False)
            first = (root / "dist" / "il" / "config.yaml").read_bytes()
            run(root=root, targets=(), all_templates=True, dry_run=False)
            second = (root / "dist" / "il" / "config.yaml").read_bytes()
            self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
