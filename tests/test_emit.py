"""Distribution emission: flat manifest, config, secret gate, ownership, determinism."""

from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import yaml

from configurator.emit import emit_distribution
from configurator.errors import SecretLeakError
from configurator.parse import parse_template
from configurator.secretscan import looks_like_secret


def _base(**extra: object) -> object:
    data: dict[str, object] = {
        "name": "general",
        "kind": "base",
        "distribution": {"description": "Base", "version": "1.2.0"},
        "config": {"model": {"provider": "zenmux"}, "providers": {"zenmux": {"key_env": "ZENMUX_API_KEY"}}},
        "env": [{"name": "ZENMUX_API_KEY", "description": "primary", "required": False}],
    }
    data.update(extra)
    return parse_template(data)  # type: ignore[arg-type]


class Manifest(unittest.TestCase):
    def test_distribution_yaml_is_flat_with_required_fields(self) -> None:
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(_base(), out)  # type: ignore[arg-type]
            manifest = yaml.safe_load((out / "distribution.yaml").read_text(encoding="utf-8"))
            self.assertEqual(manifest["name"], "general")
            self.assertEqual(manifest["version"], "1.2.0")
            self.assertEqual(manifest["hermes_requires"], ">=0.18.0")
            self.assertEqual(manifest["env_requires"][0]["name"], "ZENMUX_API_KEY")
            self.assertFalse(manifest["env_requires"][0]["required"])
            self.assertNotIn("distribution", manifest)

    def test_config_yaml_has_config_version(self) -> None:
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(_base(), out)  # type: ignore[arg-type]
            cfg = yaml.safe_load((out / "config.yaml").read_text(encoding="utf-8"))
            self.assertEqual(cfg["_config_version"], 33)
            self.assertEqual(cfg["providers"]["zenmux"]["key_env"], "ZENMUX_API_KEY")

    def test_bundles_add_skill_bundles_to_distribution_owned(self) -> None:
        tpl = _base(bundles=[{"name": "core", "skills": ["a", "b"]}])
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(tpl, out)  # type: ignore[arg-type]
            manifest = yaml.safe_load((out / "distribution.yaml").read_text(encoding="utf-8"))
            self.assertIn("skill-bundles", manifest["distribution_owned"])
            self.assertIn("SOUL.md", manifest["distribution_owned"])
            self.assertTrue((out / "skill-bundles" / "core.yaml").is_file())

    def test_reference_only_distribution_does_not_own_skills(self) -> None:
        # No vendored includes -> the compiler must NOT list `skills` in distribution_owned, so
        # `hermes profile update` leaves user-installed skills alone.
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(_base(), out)  # type: ignore[arg-type]
            manifest = yaml.safe_load((out / "distribution.yaml").read_text(encoding="utf-8"))
            self.assertNotIn("skills", manifest["distribution_owned"])
            self.assertFalse((out / "skills").exists())


class SkillsInstallList(unittest.TestCase):
    def test_post_install_emits_machine_readable_list(self) -> None:
        tpl = _base(post_install=[
            {"id": "official/research/duckduckgo-search", "note": "free search"},
            {"id": "obra/superpowers", "tap": True},
        ])
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(tpl, out)  # type: ignore[arg-type]
            data = yaml.safe_load((out / "skills.install.json").read_text(encoding="utf-8"))
            self.assertEqual([s["id"] for s in data["skills"]], [
                "official/research/duckduckgo-search", "obra/superpowers",
            ])
            self.assertFalse(data["skills"][0]["tap"])
            self.assertTrue(data["skills"][1]["tap"])
            manifest = yaml.safe_load((out / "distribution.yaml").read_text(encoding="utf-8"))
            self.assertIn("skills.install.json", manifest["distribution_owned"])

    def test_no_post_install_emits_no_list(self) -> None:
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(_base(), out)  # type: ignore[arg-type]
            self.assertFalse((out / "skills.install.json").exists())


class SetupSteps(unittest.TestCase):
    def test_setup_steps_emit_both_platform_scripts(self) -> None:
        tpl = _base(setup_steps=[{
            "id": "rtk", "label": "RTK", "tier": 0,
            "posix_run": "curl -fsSL https://x/install.sh | sh; rtk init --agent hermes",
            "windows_run": "rtk init --agent hermes",
        }])
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(tpl, out)  # type: ignore[arg-type]
            self.assertTrue((out / "setup.steps.sh").is_file())
            self.assertTrue((out / "setup.steps.ps1").is_file())
            self.assertIn("rtk init --agent hermes", (out / "setup.steps.sh").read_text(encoding="utf-8"))
            manifest = yaml.safe_load((out / "distribution.yaml").read_text(encoding="utf-8"))
            self.assertIn("setup.steps.sh", manifest["distribution_owned"])

    def test_no_setup_steps_emits_no_scripts(self) -> None:
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(_base(), out)  # type: ignore[arg-type]
            self.assertFalse((out / "setup.steps.sh").exists())
            self.assertFalse((out / "setup.steps.ps1").exists())

    def test_planted_secret_in_setup_run_fails_emit(self) -> None:
        tpl = _base(setup_steps=[{"id": "x", "posix_run": "export K=AKIAIOSFODNN7EXAMPLE1234"}])
        with TemporaryDirectory() as tmp, self.assertRaises(SecretLeakError):
            emit_distribution(tpl, Path(tmp))  # type: ignore[arg-type]


class SecretGate(unittest.TestCase):
    def test_key_prefix_detected(self) -> None:
        self.assertIsNotNone(looks_like_secret("sk-ant-abc123def456ghi789jkl012mno345"))

    def test_var_reference_is_clean(self) -> None:
        self.assertIsNone(looks_like_secret("${ZENMUX_API_KEY}"))

    def test_model_id_is_clean(self) -> None:
        self.assertIsNone(looks_like_secret("anthropic/claude-sonnet-5-free"))

    def test_url_is_clean(self) -> None:
        self.assertIsNone(looks_like_secret("https://zenmux.ai/api/v1"))

    def test_long_hyphenated_slug_is_clean(self) -> None:
        # A 32-char skill name/slug is not a credential (no digits, hyphen-separated words).
        self.assertIsNone(looks_like_secret("israeli-accessibility-compliance"))
        self.assertIsNone(looks_like_secret("hebrew-document-generator"))

    def test_high_entropy_alphanumeric_token_flagged(self) -> None:
        self.assertIsNotNone(looks_like_secret("aB3xK9zQ1mN7pR4tV6wY2cF8hJ0lD5sG"))

    def test_literal_key_in_config_fails_emit(self) -> None:
        tpl = _base(config={"providers": {"x": {"api_key": "AKIAIOSFODNN7EXAMPLE1234"}}})
        with TemporaryDirectory() as tmp, self.assertRaises(SecretLeakError):
            emit_distribution(tpl, Path(tmp))  # type: ignore[arg-type]


class MetaSkill(unittest.TestCase):
    def test_finish_setup_emitted_under_meta_skills_not_skills(self) -> None:
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(_base(), out)  # type: ignore[arg-type]
            self.assertTrue((out / "meta-skills" / "finish-setup" / "SKILL.md").is_file())
            # Never under skills/ — that dir would be wiped/replaced by `hermes profile update`.
            self.assertFalse((out / "skills").exists())

    def test_meta_skills_dir_prepended_to_external_dirs(self) -> None:
        tpl = _base(skills={"bundled": "none", "external_dirs": ["~/open-skills/skills"]})
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(tpl, out)  # type: ignore[arg-type]
            cfg = yaml.safe_load((out / "config.yaml").read_text(encoding="utf-8"))
            self.assertEqual(cfg["skills"]["external_dirs"][0], "meta-skills")
            self.assertIn("~/open-skills/skills", cfg["skills"]["external_dirs"])

    def test_meta_skills_owned_but_skills_not(self) -> None:
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(_base(), out)  # type: ignore[arg-type]
            manifest = yaml.safe_load((out / "distribution.yaml").read_text(encoding="utf-8"))
            self.assertIn("meta-skills", manifest["distribution_owned"])
            self.assertNotIn("skills", manifest["distribution_owned"])

    def test_secret_in_env_description_fails_meta_skill_scan(self) -> None:
        # The meta-skill renders env descriptions; a planted key-shaped literal there must fail emit.
        tpl = _base(env=[{"name": "X_KEY", "description": "use sk-ant-abc123def456ghi789jkl012mno345"}])
        with TemporaryDirectory() as tmp, self.assertRaises(SecretLeakError):
            emit_distribution(tpl, Path(tmp))  # type: ignore[arg-type]


class Markers(unittest.TestCase):
    def test_bundled_none_writes_marker(self) -> None:
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(_base(skills={"bundled": "none"}), out)  # type: ignore[arg-type]
            self.assertTrue((out / ".no-bundled-skills").is_file())

    def test_env_example_generated(self) -> None:
        with TemporaryDirectory() as tmp:
            out = Path(tmp)
            emit_distribution(_base(), out)  # type: ignore[arg-type]
            example = (out / ".env.EXAMPLE").read_text(encoding="utf-8")
            self.assertIn("ZENMUX_API_KEY", example)


class Determinism(unittest.TestCase):
    def test_emit_twice_is_byte_identical(self) -> None:
        tpl = _base(bundles=[{"name": "core", "skills": ["a"]}])
        with TemporaryDirectory() as tmp:
            a, b = Path(tmp) / "a", Path(tmp) / "b"
            emit_distribution(tpl, a)  # type: ignore[arg-type]
            emit_distribution(tpl, b)  # type: ignore[arg-type]
            for rel in ("distribution.yaml", "config.yaml"):
                self.assertEqual(
                    (a / rel).read_bytes(), (b / rel).read_bytes(), f"{rel} not deterministic",
                )


if __name__ == "__main__":
    unittest.main()
