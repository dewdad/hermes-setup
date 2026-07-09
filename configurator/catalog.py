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

# Placeholders (NOT hard-coded — the publisher/agent substitutes the repo it was handed).
RAW_URL_PLACEHOLDER = "<RAW_REPO_URL>"
GIT_URL_PLACEHOLDER = "<REPO_GIT_URL>"

_AGENT_INSTRUCTIONS = (
    "You are pointed at the hermes-setup repo. To set up a Hermes agent from it: "
    "(1) present the `profiles` list to the user — each entry's `name`, `kind`, and `description` "
    "(`kind: base`, e.g. general, is the recommended general-purpose default; `locale` is a "
    "region base; `persona` is specialized); "
    "(2) ask which `name` they want; "
    "(3a) IF you are already running inside a local clone of this repo, run that profile's "
    "`local_install_command`; "
    "(3b) OTHERWISE run its `standalone_posix_command` (macOS/Linux) or `standalone_windows_command` "
    f"(Windows), first replacing {RAW_URL_PLACEHOLDER} and {GIT_URL_PLACEHOLDER} with the "
    "raw-content and git URLs of THIS repo (derive them from the link you were given). "
    "NEVER run `hermes profile install` against a repo-subdirectory URL — it only accepts a repo "
    "ROOT or a LOCAL folder, and the standalone command creates that local clone for you. "
    "After install, open the profile (`hermes -p <name>`) and run `/finish-setup`."
)

_INSTALL_NOTE = (
    "hermes profile install cannot target a subdirectory of a git repo (it clones the URL root and "
    "requires distribution.yaml there). Install from a LOCAL clone: from inside a checkout run a "
    "profile's local_install_command; standalone, run its standalone_posix_command / "
    "standalone_windows_command (which clone the repo for you). See each profile entry."
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
        # From inside a checkout only (relative ./dist path):
        "local_install_command": f"hermes profile install ./dist/{name} --name {name} --yes",
        # Standalone (no checkout): clone + install via the bundled scripts. URLs are placeholders.
        "standalone_posix_command": (
            f"curl -fsSL {RAW_URL_PLACEHOLDER}/install.sh | bash -s -- {name} "
            f"--repo {GIT_URL_PLACEHOLDER} --yes"
        ),
        "standalone_windows_command": (
            f"$p=Join-Path $env:TEMP 'hermes-setup-install.ps1'; "
            f"irm {RAW_URL_PLACEHOLDER}/install.ps1 -OutFile $p; "
            f"& $p {name} -Repo {GIT_URL_PLACEHOLDER} -Yes"
        ),
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
