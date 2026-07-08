"""Hermes configurator: compile layered templates into native Hermes profile distributions.

stdlib + PyYAML only (see repo AGENTS.md). Public entry point is ``configurator.compile.main``.
"""

from typing import Final

__all__ = ["CONFIG_VERSION", "HERMES_REQUIRES", "SOUL_MAX_CHARS"]

CONFIG_VERSION: Final = 33
HERMES_REQUIRES: Final = ">=0.18.0"
SOUL_MAX_CHARS: Final = 20_000
