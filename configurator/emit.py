"""Emit one resolved template as a native Hermes profile distribution under ``dist/<name>/``.

Everything is written deterministically (see ``yamlio``). Secrets are scanned before ``config.yaml``
is written, so a key-shaped literal fails the build. Vendored skills are copied verbatim into
``skills/<category>/<name>/``.
"""

from __future__ import annotations

import shutil
from collections.abc import Sequence
from pathlib import Path

from configurator import CONFIG_VERSION
from configurator.manifest import (
    build_env_example,
    build_manifest,
    build_skills_install,
    build_skills_sh,
)
from configurator.model import Bundle, Template
from configurator.readme import build_readme
from configurator.secretscan import scan_config, scan_text
from configurator.setup_scripts import (
    POSIX_SCRIPT_NAME,
    WINDOWS_SCRIPT_NAME,
    build_setup_script_posix,
    build_setup_script_windows,
)
from configurator.setup_skill import (
    FINISH_SETUP_NAME,
    META_SKILLS_DIRNAME,
    build_finish_setup_skill,
)
from configurator.soul import compose_soul
from configurator.yamlio import YamlMap, YamlValue, dump_json, dump_yaml, write_text

_GITIGNORE = """\
# Hermes profile distribution — safe artifacts only. Never commit secrets or runtime state.
.env
*.env
!.env.EXAMPLE
auth.json
models.json
desktop.json
state.db*
response_store.db*
sessions/
memories/
logs/
*.bak
*.bak.*
"""


def _slug(name: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "-" for c in name.strip().lower())


def _build_config(template: Template) -> YamlMap:
    """Merge the config fragment with the config version and skills.external_dirs from the template.

    The generated ``meta-skills`` dir (which carries ``finish-setup``) is prepended to
    ``external_dirs`` as a profile-relative path so Hermes discovers and slash-registers it. It is
    kept out of ``skills/`` on purpose so ``hermes profile update`` never touches user skills.
    """
    config: YamlMap = {**template.config, "_config_version": CONFIG_VERSION}
    external: list[YamlValue] = [META_SKILLS_DIRNAME]
    for entry in template.skills.external_dirs:
        if entry not in external:
            external.append(entry)
    existing = config.get("skills")
    skills_cfg: YamlMap = dict(existing) if isinstance(existing, dict) else {}
    skills_cfg["external_dirs"] = external
    config["skills"] = skills_cfg
    return config


def _write_bundle(out_dir: Path, bundle: Bundle) -> None:
    body: YamlMap = {"name": bundle.name, "skills": list(bundle.skills)}
    if bundle.description:
        body["description"] = bundle.description
    if bundle.instruction:
        body["instruction"] = bundle.instruction
    write_text(out_dir / "skill-bundles" / f"{_slug(bundle.name)}.yaml", dump_yaml(body))


def _write_cron(out_dir: Path, jobs: tuple[YamlMap, ...]) -> None:
    for index, job in enumerate(jobs):
        raw_name = job.get("name")
        name = _slug(raw_name) if isinstance(raw_name, str) and raw_name else f"job-{index}"
        write_text(out_dir / "cron" / f"{name}.json", dump_json(job))


def _copy_skills(out_dir: Path, skills: Sequence[tuple[str, Path]]) -> None:
    for rel_dest, src_dir in skills:
        dest = out_dir / "skills" / rel_dest
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(src_dir, dest)


def emit_distribution(
    template: Template, out_dir: Path, skills: Sequence[tuple[str, Path]] = (),
) -> None:
    """Write the full distribution for ``template`` into ``out_dir`` (clean rebuild).

    The dir is cleared first so removals (excluded skills, dropped files) propagate and no stale
    artifact survives — the emit is a pure function of the template.
    """
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_text(out_dir / "distribution.yaml", dump_yaml(build_manifest(template)))

    config = _build_config(template)
    scan_config(config, where="config.yaml")
    write_text(out_dir / "config.yaml", dump_yaml(config))

    soul = compose_soul(template.soul, template.name)
    if soul:
        write_text(out_dir / "SOUL.md", soul)

    if template.env:
        write_text(out_dir / ".env.EXAMPLE", build_env_example(template.env))
    # Hermes seeds bundled skills all-or-nothing via this marker. "all" seeds them; "none" or a
    # curated allowlist suppresses the bulk (the allowlisted skills arrive as vendored includes).
    if template.skills.bundled != "all":
        write_text(out_dir / ".no-bundled-skills", "")
    if template.mcp:
        scan_config(template.mcp, where="mcp.json")
        write_text(out_dir / "mcp.json", dump_json(template.mcp))
    _write_cron(out_dir, template.cron)
    for bundle in template.bundles:
        _write_bundle(out_dir, bundle)
    _copy_skills(out_dir, skills)

    # The generated finish-setup meta-skill (the reference-only carve-out). Scanned for secrets
    # before writing, like every other emitted artifact. Lives under meta-skills/ (NOT skills/) so
    # `hermes profile update` refreshes it without wiping the user's installed skills.
    finish_setup = build_finish_setup_skill(template)
    scan_text(finish_setup, where=f"{META_SKILLS_DIRNAME}/{FINISH_SETUP_NAME}/SKILL.md")
    write_text(out_dir / META_SKILLS_DIRNAME / FINISH_SETUP_NAME / "SKILL.md", finish_setup)

    if template.skills.include or template.bundles:
        write_text(out_dir / "skills.sh.json", dump_json(build_skills_sh(template)))
    if template.post_install:
        write_text(out_dir / "skills.install.json", dump_json(build_skills_install(template)))
    # Generated local-tool setup scripts (e.g. RTK). Secret-scanned before writing like every other
    # artifact; the apply-flow bootstrap runs the platform-matched one, gated by user confirmation.
    if template.setup_steps:
        posix_script = build_setup_script_posix(template.setup_steps)
        windows_script = build_setup_script_windows(template.setup_steps)
        scan_text(posix_script, where=POSIX_SCRIPT_NAME)
        scan_text(windows_script, where=WINDOWS_SCRIPT_NAME)
        write_text(out_dir / POSIX_SCRIPT_NAME, posix_script)
        write_text(out_dir / WINDOWS_SCRIPT_NAME, windows_script)
    write_text(out_dir / ".gitignore", _GITIGNORE)
    write_text(out_dir / "README.md", build_readme(template))
