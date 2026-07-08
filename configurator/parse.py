"""Strict parsing/validation of raw ``template.yaml`` mappings into :class:`Template`.

Parse, don't validate: every value becomes a typed object here or the parse raises
:class:`TemplateError`. The rest of the compiler trusts the resulting objects.
"""

from __future__ import annotations

from pathlib import Path

from configurator.errors import TemplateError
from configurator.model import (
    Bundle,
    EnvVar,
    PostInstallRef,
    SkillRef,
    SkillsSpec,
    SkillSourceKind,
    SoulFragment,
    Template,
    TemplateKind,
)
from configurator.yamlio import YamlMap, YamlValue


def _require_str(data: YamlMap, key: str, name: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        raise TemplateError(template=name, field=key, reason="missing or not a non-empty string")
    return value.strip()


def _as_map(value: YamlValue, name: str, key: str) -> YamlMap:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise TemplateError(template=name, field=key, reason="must be a mapping")
    return value


def _parse_env(raw: YamlValue, name: str) -> tuple[EnvVar, ...]:
    if raw is None:
        return ()
    if not isinstance(raw, list):
        raise TemplateError(template=name, field="env", reason="must be a list")
    out: list[EnvVar] = []
    for entry in raw:
        if not isinstance(entry, dict):
            raise TemplateError(template=name, field="env", reason="each entry must be a mapping")
        desc = entry.get("description", "")
        default = entry.get("default")
        out.append(EnvVar(
            name=_require_str(entry, "name", name),
            description=desc if isinstance(desc, str) else "",
            required=bool(entry.get("required", False)),
            default=default if isinstance(default, str) else None,
        ))
    return tuple(out)


def _parse_skill_ref(entry: YamlMap, name: str) -> SkillRef:
    raw_source = _require_str(entry, "source", name)
    try:
        source = SkillSourceKind(raw_source)
    except ValueError:
        raise TemplateError(
            template=name, field="skills.include.source",
            reason=f"unknown source '{raw_source}'",
        ) from None
    category = entry.get("category")
    lic = entry.get("license")
    ref = entry.get("ref")
    return SkillRef(
        source=source,
        id=_require_str(entry, "id", name),
        category=category if isinstance(category, str) else None,
        license=lic if isinstance(lic, str) else None,
        redistributable=bool(entry.get("redistributable", True)),
        ref=ref if isinstance(ref, str) and ref.strip() else "main",
    )


def _parse_bundled(value: YamlValue, name: str) -> str | tuple[str, ...]:
    if value is None:
        return "none"
    if isinstance(value, str):
        if value not in {"none", "all"}:
            raise TemplateError(
                template=name, field="skills.bundled", reason="string form must be 'none' or 'all'",
            )
        return value
    if isinstance(value, list):
        return tuple(str(item) for item in value)
    raise TemplateError(template=name, field="skills.bundled", reason="must be 'none'|'all'|list")


def _parse_skills(raw: YamlValue, name: str) -> SkillsSpec:
    data = _as_map(raw, name, "skills")
    include_raw = data.get("include", [])
    if not isinstance(include_raw, list):
        raise TemplateError(template=name, field="skills.include", reason="must be a list")
    includes = tuple(
        _parse_skill_ref(_as_map(e, name, "skills.include"), name) for e in include_raw
    )
    ext = data.get("external_dirs", [])
    exclude = data.get("exclude", [])
    return SkillsSpec(
        bundled=_parse_bundled(data.get("bundled"), name),
        external_dirs=tuple(str(d) for d in ext) if isinstance(ext, list) else (),
        include=includes,
        exclude=tuple(str(x) for x in exclude) if isinstance(exclude, list) else (),
    )


def _parse_bundles(raw: YamlValue, name: str) -> tuple[Bundle, ...]:
    if raw is None:
        return ()
    if not isinstance(raw, list):
        raise TemplateError(template=name, field="bundles", reason="must be a list")
    out: list[Bundle] = []
    for entry in raw:
        emap = _as_map(entry, name, "bundles")
        skills_raw = emap.get("skills", [])
        desc = emap.get("description", "")
        instr = emap.get("instruction", "")
        out.append(Bundle(
            name=_require_str(emap, "name", name),
            skills=tuple(str(s) for s in skills_raw) if isinstance(skills_raw, list) else (),
            description=desc if isinstance(desc, str) else "",
            instruction=instr if isinstance(instr, str) else "",
        ))
    return tuple(out)


def _parse_soul(raw: YamlValue, name: str, source_dir: Path | None) -> tuple[SoulFragment, ...]:
    data = _as_map(raw, name, "soul")
    frags = data.get("fragments", [])
    if not isinstance(frags, list):
        raise TemplateError(template=name, field="soul.fragments", reason="must be a list")
    base = source_dir / "soul" if source_dir is not None else None
    return tuple(
        SoulFragment(name=str(f), path=(base / str(f)) if base is not None else None)
        for f in frags
    )


def _parse_post_install(raw: YamlValue, name: str) -> tuple[PostInstallRef, ...]:
    if raw is None:
        return ()
    if not isinstance(raw, list):
        raise TemplateError(template=name, field="post_install", reason="must be a list")
    out: list[PostInstallRef] = []
    for entry in raw:
        emap = _as_map(entry, name, "post_install")
        note = emap.get("note", "")
        out.append(PostInstallRef(
            id=_require_str(emap, "id", name),
            note=note if isinstance(note, str) else "",
            is_tap=bool(emap.get("tap", False)),
        ))
    return tuple(out)


def _parse_kind(data: YamlMap, name: str) -> TemplateKind:
    raw_kind = _require_str(data, "kind", name)
    try:
        return TemplateKind(raw_kind)
    except ValueError:
        raise TemplateError(template=name, field="kind", reason=f"unknown kind '{raw_kind}'") from None


def parse_template(data: YamlMap, source_dir: Path | None = None) -> Template:
    """Parse and validate a raw manifest mapping into a frozen :class:`Template`."""
    raw_name = data.get("name")
    name = raw_name.strip() if isinstance(raw_name, str) and raw_name.strip() else "<unnamed>"
    name = _require_str(data, "name", name)
    kind = _parse_kind(data, name)
    extends_val = data.get("extends")
    extends = extends_val.strip() if isinstance(extends_val, str) and extends_val.strip() else None
    if kind is TemplateKind.BASE and extends is not None:
        raise TemplateError(template=name, field="extends", reason="base templates must not extend")
    if kind is not TemplateKind.BASE and extends is None:
        raise TemplateError(
            template=name, field="extends", reason=f"{kind} template must extend a parent",
        )
    cron_raw = data.get("cron", [])
    cron = tuple(_as_map(c, name, "cron") for c in cron_raw) if isinstance(cron_raw, list) else ()
    return Template(
        name=name,
        kind=kind,
        extends=extends,
        distribution=_as_map(data.get("distribution"), name, "distribution"),
        config=_as_map(data.get("config"), name, "config"),
        env=_parse_env(data.get("env"), name),
        soul=_parse_soul(data.get("soul"), name, source_dir),
        skills=_parse_skills(data.get("skills"), name),
        bundles=_parse_bundles(data.get("bundles"), name),
        mcp=_as_map(data.get("mcp"), name, "mcp"),
        cron=cron,
        post_install=_parse_post_install(data.get("post_install"), name),
        source_dir=source_dir,
    )
