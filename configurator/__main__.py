"""``python -m configurator`` entry point — delegates to the CLI in ``compile.py``."""

from __future__ import annotations

import sys

from configurator.compile import main

if __name__ == "__main__":
    sys.exit(main())
