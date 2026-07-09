"""Build the repo-root ``profiles.json`` catalogue.

A single machine-readable index of every compiled distribution so an agent pointed at the repo can
list installable profiles in ONE fetch and install a chosen one — reliably, even on a weak model.

Hermes has no profile registry, and ``hermes profile install`` CANNOT target a repo *subdirectory*
(it clones the URL root and requires ``distribution.yaml`` there — verified against Hermes'
``profile_distribution.py``). So the catalogue records repo-relative ``dist/<name>`` paths plus the
clone-then-local-install flow the bundled ``install.sh`` / ``install.ps1`` automate, and carries a
plain-language ``agent_instructions`` recipe a small model can follow verbatim. No absolute repo URL
is embedded (the publisher/org is never hard-coded), keeping output identical across forks.

Pure function; stdlib + PyYAML only. Emitted deterministically (sorted keys) and secret-scanned by
the compiler before writing, like every other generated artifact.
"""

from __future__ import annotations

from collections.abc import Sequence

from configurator import HERMES_REQUIRES
from configurator.model import Template
from configurator.yamlio import YamlMap, YamlValue

CATALOG_FILENAME = "profiles.json"
SCHEMA_ID = "hermes-setup/profiles@1"

_AGENT_INSTRUCTIONS = (
    "You are pointed at the hermes-setup repo. To set up a Hermes agent from it: "
    "(1) present the `profiles` list below to the user (each entry's `name` + `description`); "
    "(2) ask which one they want; "
    "(3) install the chosen <name> by running its `install_command`. "
    "IMPORTANT: `hermes profile install` cannot install from a repo-subdirectory URL, so the "
    "profile must be installed from a LOCAL clone of this repo. The simplest path is the bundled "
    "installer, which does the clone + install for you: `./install.sh <name>` (POSIX) or "
    "`./install.ps1 <name>` (Windows). Equivalently, clone the repo and run "
    "`hermes profile install ./dist/<name> --name <name> --yes`. "
    "After install, open the profile (`hermes -p <name>`) and run `/finish-setup`."
)

_INSTALL_NOTE = (
    "hermes profile install cannot target a subdirectory of a git repo (it clones the URL root and "
    "requires distribution.yaml there). Install from a local clone: run ./install.sh <name> "
    "(POSIX) or ./install.ps1 <name> (Windows), or clone this repo then "
    "hermes profile install ./dist/<name> --name <name> --yes."
)


def _description(template: Template) -> str:
    desc = template.distribution.get("description")
    return desc if isinstance(desc, str) and desc else template.name


def _version(template: Template) -> str:
    version = template.distribution.get("version")
    return version if isinstance(version, str) and version else "0.1.0"


def _profile_entry(template: Template) -> YamlMap:
    name = template.name
    return {
        "name": name,
        "kind": str(template.kind),
        "version": _version(template),
        "description": _description(template),
        "path": f"dist/{name}",
        "install_command": f"hermes profile install ./dist/{name} --name {name} --yes",
    }


def build_catalog(templates: Sequence[Template]) -> YamlMap:
    """Assemble the ``profiles.json`` catalogue mapping from every resolved (leaf) template."""
    profiles: list[YamlValue] = [
        _profile_entry(tpl) for tpl in sorted(templates, key=lambda tpl: tpl.name)
    ]
    return {
        "schema": SCHEMA_ID,
        "generated_by": "python -m configurator compile",
        "hermes_requires": HERMES_REQUIRES,
        "agent_instructions": _AGENT_INSTRUCTIONS,
        "install": {
            "note": _INSTALL_NOTE,
            "posix_script": "./install.sh",
            "windows_script": "./install.ps1",
        },
        "profiles": profiles,
    }
