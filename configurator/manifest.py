"""Build the flat ``distribution.yaml`` manifest and the ``.env.EXAMPLE`` body.

Both mirror the exact shapes Hermes' ``profile_distribution.py`` parses/generates so installs and
updates behave. ``skill-bundles`` is NOT in Hermes' default owned set, so any template that emits
bundles must declare a ``distribution_owned`` override that re-lists the defaults plus it.
"""

from __future__ import annotations

from configurator import HERMES_REQUIRES
from configurator.model import EnvVar, Template
from configurator.yamlio import YamlMap, YamlValue

# Files the compiler always manages. Under the reference-only model nothing is vendored, so
# ``skills`` is NOT owned by default — skills are installed via ``hermes skills install`` and stay
# user-owned; ``skills`` is only re-added when a template genuinely vendors a fetched skill.
DEFAULT_DIST_OWNED: tuple[str, ...] = ("SOUL.md", "config.yaml", "mcp.json", "cron",
                                       "distribution.yaml")


def _env_requires(env: tuple[EnvVar, ...]) -> list[YamlValue]:
    """Serialize env vars like Hermes' EnvRequirement.to_dict (omit required when True/default None)."""
    out: list[YamlValue] = []
    for var in env:
        entry: YamlMap = {"name": var.name, "description": var.description}
        if not var.required:
            entry["required"] = False
        if var.default is not None:
            entry["default"] = var.default
        out.append(entry)
    return out


def build_manifest(template: Template) -> YamlMap:
    """Assemble the flat distribution manifest mapping for ``template``."""
    dist = template.distribution
    version = dist.get("version")
    manifest: YamlMap = {
        "name": template.name,
        "version": version if isinstance(version, str) else "0.1.0",
        "hermes_requires": HERMES_REQUIRES,
    }
    for key in ("description", "author", "license"):
        value = dist.get(key)
        if isinstance(value, str) and value:
            manifest[key] = value
    if template.env:
        manifest["env_requires"] = _env_requires(template.env)
    # Own the generated README (carries the post-install block) so `profile update` refreshes it;
    # own skill-bundles/skills.sh.json when emitted so curated bundles + hub labels stay current.
    owned: list[str] = [*DEFAULT_DIST_OWNED, "README.md"]
    if any(ref.vendored for ref in template.skills.include):
        owned.append("skills")
    if template.skills.include or template.bundles:
        owned.append("skills.sh.json")
    if template.bundles:
        owned.append("skill-bundles")
    if template.post_install:
        owned.append("skills.install.json")
    sorted_owned: list[YamlValue] = [*sorted(owned)]
    manifest["distribution_owned"] = sorted_owned
    return manifest


def build_skills_install(template: Template) -> YamlMap:
    """Build the machine-readable apply-time install list the bootstrap scripts consume.

    Lists every referenced (bucket 3) skill/tap so the apply flow can auto-run
    ``hermes skills install <id>`` / ``hermes skills tap add <tap>`` after the user confirms.
    """
    skills: list[YamlValue] = []
    for ref in template.post_install:
        entry: YamlMap = {"id": ref.id, "tap": ref.is_tap}
        if ref.note:
            entry["note"] = ref.note
        skills.append(entry)
    return {"skills": skills}


def build_skills_sh(template: Template) -> YamlMap:
    """Build a skills.sh.json body whose ``groupings`` become Skills Hub category labels.

    Groupings are derived from vendored skill categories; bundles are surfaced as their own group so
    a published persona tap presents real labels instead of tag-derived guesses.
    """
    by_category: dict[str, list[str]] = {}
    for ref in template.skills.include:
        by_category.setdefault(ref.category or "custom", []).append(ref.skill_name)
    groupings: list[YamlValue] = []
    for category, names in sorted(by_category.items()):
        skills: list[YamlValue] = [*sorted(set(names))]
        groupings.append({"name": category, "skills": skills})
    for bundle in template.bundles:
        bundle_skills: list[YamlValue] = [*bundle.skills]
        groupings.append({"name": f"bundle:{bundle.name}", "skills": bundle_skills})
    description = template.distribution.get("description")
    return {
        "$schema": "https://skills.sh/schemas/skills.sh.schema.json",
        "name": template.name,
        "description": description if isinstance(description, str) else template.name,
        "groupings": groupings,
    }


def build_env_example(env: tuple[EnvVar, ...]) -> str:
    """Generate a ``.env.EXAMPLE`` body matching Hermes' _env_template_from_manifest format."""
    lines = [
        "# Environment variables required by this Hermes distribution.",
        "# Copy to `.env` and fill in your own values before running.",
        "",
    ]
    for var in env:
        if var.description:
            lines.append(f"# {var.description}")
        lines.append(f"# ({'required' if var.required else 'optional'})")
        default = var.default if var.default is not None else ""
        prefix = "" if var.required else "# "
        lines.append(f"{prefix}{var.name}={default}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"
