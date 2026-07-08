"""Live-config drift ingest — reads config.yaml only, never secrets/desktop state."""

from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from configurator.ingest import compute_drift, read_live_config


class ComputeDrift(unittest.TestCase):
    def test_reports_changed_key(self) -> None:
        base = {"model": {"provider": "zenmux", "max_tokens": 8192}}
        live = {"model": {"provider": "openai", "max_tokens": 8192}}
        report = compute_drift(base, live)
        self.assertIn("model.provider", report.changed)
        self.assertEqual(report.changed["model.provider"], ("zenmux", "openai"))

    def test_reports_only_in_live_and_only_in_base(self) -> None:
        report = compute_drift({"a": 1, "b": 2}, {"a": 1, "c": 3})
        self.assertIn("b", report.only_in_base)
        self.assertIn("c", report.only_in_live)

    def test_no_drift_is_empty(self) -> None:
        report = compute_drift({"a": {"x": 1}}, {"a": {"x": 1}})
        self.assertFalse(report.changed)
        self.assertFalse(report.only_in_base)
        self.assertFalse(report.only_in_live)


class ReadLiveConfig(unittest.TestCase):
    def test_reads_only_config_yaml_not_secrets(self) -> None:
        with TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "config.yaml").write_text("model: {provider: zenmux}\n", encoding="utf-8")
            (home / ".env").write_text("ZENMUX_API_KEY=sk-super-secret-value-123456789\n", encoding="utf-8")
            (home / "auth.json").write_text('{"token": "secret-token-abcdefghijklmnop"}', encoding="utf-8")
            (home / "desktop.json").write_text('{"remoteApiKey": "sk-desktop-999888777"}', encoding="utf-8")
            config = read_live_config(home, profile=None)
            self.assertEqual(config["model"], {"provider": "zenmux"})
            # The returned config never contains any secret value from the sibling files.
            flat = repr(config)
            self.assertNotIn("sk-super-secret", flat)
            self.assertNotIn("secret-token", flat)
            self.assertNotIn("sk-desktop", flat)


if __name__ == "__main__":
    unittest.main()
