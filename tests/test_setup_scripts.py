"""Generated per-platform setup.steps.{sh,ps1}: content, quoting safety, determinism."""

from __future__ import annotations

import unittest

from configurator.model import SetupStep
from configurator.setup_scripts import (
    build_setup_script_posix,
    build_setup_script_windows,
)

_RTK = SetupStep(
    id="rtk",
    label="RTK (Rust Token Killer)",
    note="Compresses output.",
    tier=0,
    posix_check='test -d "$HOME/.hermes/plugins/rtk-rewrite"',
    posix_run="curl -fsSL https://x/install.sh | sh; rtk init --agent hermes",
    windows_check="Test-Path (Join-Path $env:HERMES_HOME 'plugins\\rtk-rewrite')",
    windows_run="Invoke-WebRequest -Uri https://x/rtk.zip -OutFile $z; rtk init --agent hermes",
)


class PosixScript(unittest.TestCase):
    def test_shebang_and_helper_present(self) -> None:
        script = build_setup_script_posix((_RTK,))
        self.assertTrue(script.startswith("#!/usr/bin/env sh"))
        self.assertIn("_run_step()", script)

    def test_step_call_carries_label_check_run(self) -> None:
        script = build_setup_script_posix((_RTK,))
        self.assertIn("_run_step 'RTK (Rust Token Killer)'", script)
        self.assertIn("rtk init --agent hermes", script)

    def test_single_quote_in_value_is_escaped(self) -> None:
        step = SetupStep(id="x", label="a'b", posix_run="echo 'hi'")
        script = build_setup_script_posix((step,))
        # POSIX escaping turns ' into '\'' — the raw two-char sequence "''" must not appear bare.
        self.assertIn("'a'\\''b'", script)
        self.assertIn("echo '\\''hi'\\''", script)

    def test_empty_when_no_steps(self) -> None:
        # Header only, no _run_step calls.
        self.assertNotIn("_run_step '", build_setup_script_posix(()))


class WindowsScript(unittest.TestCase):
    def test_function_and_error_pref_present(self) -> None:
        script = build_setup_script_windows((_RTK,))
        self.assertIn("function Invoke-SetupStep", script)
        self.assertIn("$ErrorActionPreference = 'Continue'", script)

    def test_step_call_carries_label_check_run(self) -> None:
        script = build_setup_script_windows((_RTK,))
        self.assertIn("Invoke-SetupStep -Label 'RTK (Rust Token Killer)'", script)
        self.assertIn("rtk init --agent hermes", script)

    def test_single_quote_in_value_is_doubled(self) -> None:
        step = SetupStep(id="x", label="a'b", windows_run="Write-Host 'hi'")
        script = build_setup_script_windows((step,))
        self.assertIn("'a''b'", script)
        self.assertIn("'Write-Host ''hi'''", script)

    def test_backslash_path_preserved_verbatim(self) -> None:
        # Windows paths must survive as literal backslashes (single-quoted, never \r-escaped).
        script = build_setup_script_windows((_RTK,))
        self.assertIn("plugins\\rtk-rewrite", script)


class Determinism(unittest.TestCase):
    def test_posix_build_twice_identical(self) -> None:
        self.assertEqual(
            build_setup_script_posix((_RTK,)), build_setup_script_posix((_RTK,)),
        )

    def test_windows_build_twice_identical(self) -> None:
        self.assertEqual(
            build_setup_script_windows((_RTK,)), build_setup_script_windows((_RTK,)),
        )

    def test_step_order_preserved(self) -> None:
        a = SetupStep(id="a", label="AAA", posix_run="ra")
        b = SetupStep(id="b", label="BBB", posix_run="rb")
        script = build_setup_script_posix((a, b))
        self.assertLess(script.index("AAA"), script.index("BBB"))


if __name__ == "__main__":
    unittest.main()
