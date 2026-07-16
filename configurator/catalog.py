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
    "(1) present the `profiles` list to the user — each entry's `name`, `kind`, `description`, and "
    "`apply_modes` (`kind: base` `general` is the recommended FREE, no-per-call-cost, "
    "general-purpose default; `general-pro` is the PAID Nous Portal variant — frontier models + the "
    "Nous Tool Gateway, requires a paid Portal subscription; `locale` is a region base; `persona` is "
    "specialized). A profile whose `apply_modes` lists `pro` can also be installed on the paid Portal "
    "base by adding the installer's `--pro` / `-Pro` flag (bootstrap uses `--portal` / `-Portal`); "
    "with no flag the free chain is used; "
    "(2) ask which `name` they want (and, if it supports `pro`, whether they want the free default or "
    "the paid Portal mode); "
    "(3) ask HOW to apply it — the two paths are different and the user should choose: "
    "(a) a NEW ISOLATED profile (recommended default) — its own sessions/auth, leaving the current "
    "profile untouched; run the profile's `local_posix_command` / `local_windows_command` / "
    "`standalone_*_command` (the `install.sh` / `install.ps1` scripts — always use these, NOT a bare "
    "`hermes profile install`, or `/finish-setup` will not register on Desktop/default surfaces); OR "
    "(b) EXTEND the CURRENT/default profile — inherit its existing sessions/auth/skills; run "
    "`bootstrap.sh --template <name>` / `bootstrap.ps1 -Template <name>` instead. "
    "Warn the user that a NEW isolated profile starts with empty session history and separate auth "
    "(their old history is intact in its original profile, reachable via `hermes -p <old>`); "
    "(4a) IF you are already running inside a local clone of this repo, run that profile's "
    "`local_posix_command` (macOS/Linux) or `local_windows_command` (Windows) — append `--pro` / "
    "`-Pro` for paid Portal mode — for a new profile, or the `bootstrap.*` command to extend the "
    "current one; "
    "(4b) OTHERWISE run its `standalone_posix_command` (macOS/Linux) or `standalone_windows_command` "
    f"(Windows), first replacing {RAW_URL_PLACEHOLDER} and {GIT_URL_PLACEHOLDER} with the "
    "raw-content and git URLs of THIS repo (derive them from the link you were given). "
    "NEVER run `hermes profile install <repo-root-url>` for this repo: the installable profiles live "
    "in `dist/<name>/` subdirectories, so the repo ROOT has NO distribution.yaml and the bare-root "
    "install fails — do NOT fall back to downloading/extracting the repo ZIP yourself (that bakes a "
    "transient temp-dir `source:` into the profile manifest and breaks `hermes profile update`). "
    "The bundled installer scripts always clone to a STABLE cache and install from `./dist/<name>`. "
    "After install, open the profile (`hermes -p <name>`) and run `/finish-setup`."
)

_INSTALL_NOTE = (
    "hermes profile install cannot target a subdirectory of a git repo, and this repo's installable "
    "profiles live under dist/<name>/ — so the repo ROOT has no distribution.yaml and a bare "
    "`hermes profile install <repo-root-url>` fails. Never improvise a repo-ZIP-to-temp install "
    "(it bakes a transient source: that breaks profile update). Install from a LOCAL clone via the "
    "bundled installer scripts (NOT a bare hermes profile install, which skips /finish-setup "
    "registration on Desktop/default surfaces): from inside a checkout run a profile's "
    "local_posix_command / local_windows_command (or bootstrap.* to extend the current profile); "
    "standalone, run its standalone_posix_command / standalone_windows_command (which clone the repo "
    "to a stable cache for you). See each profile entry."
)


def _description(template: Template) -> str:
    desc = template.distribution.get("description")
    return desc if isinstance(desc, str) and desc else template.name


def _version(template: Template) -> str:
    version = template.distribution.get("version")
    return version if isinstance(version, str) and version else "0.1.0"


def _profile_entry(template: Template) -> YamlMap:
    name = template.name
    # A portal_auth base is paid-only; every other profile installs free by default and can be
    # upgraded to the paid Portal base at apply time via the installer's --pro / --portal flag.
    apply_modes: list[YamlValue] = ["pro"] if template.portal_auth else ["free", "pro"]
    return {
        "name": name,
        "kind": str(template.kind),
        "version": _version(template),
        "description": _description(template),
        "apply_modes": apply_modes,
        "path": f"dist/{name}",
        # From inside a checkout: run the bundled installer (NOT a bare `hermes profile install`).
        # The installer registers /finish-setup on every surface (populates the ~/.hermes-setup
        # fallback dir), surfaces the new-vs-extend choice, and prints the per-profile-sessions note —
        # all of which a bare `hermes profile install ./dist/<name>` would skip.
        "local_posix_command": f"./install.sh {name} --yes",
        "local_windows_command": f".\\install.ps1 {name} -Yes",
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
