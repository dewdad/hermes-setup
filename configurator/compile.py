"""CLI entry point: ``python -m configurator {compile,list,verify,ingest,update-locks}``.

The compiler resolves each template's inheritance chain and emits a native Hermes profile
distribution into ``dist/<name>/``. Output is deterministic so ``dist/`` diffs cleanly in git.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path
from tempfile import TemporaryDirectory

from configurator.catalog import CATALOG_FILENAME, build_catalog
from configurator.emit import emit_distribution
from configurator.errors import ConfiguratorError
from configurator.loader import discover_templates, load_and_resolve, ref_for_name
from configurator.model import Template
from configurator.secretscan import scan_text
from configurator.yamlio import dump_json, write_text

REPO_ROOT = Path(__file__).resolve().parent.parent


def _write_catalog(root: Path, registry: dict[str, Template]) -> None:
    """Write the repo-root ``profiles.json`` from the FULL registry (every leaf, not just targets).

    Regenerated on every non-dry-run compile so the catalogue never drifts from ``dist/`` even after
    a single-template compile. Secret-scanned before writing, like every other emitted artifact.
    """
    templates = [load_and_resolve(ref, registry) for ref in sorted(registry)]
    text = dump_json(build_catalog(templates))
    scan_text(text, where=CATALOG_FILENAME)
    write_text(root / CATALOG_FILENAME, text)


def run(
    root: Path, targets: Sequence[str], *, all_templates: bool, dry_run: bool,
) -> list[str]:
    """Compile the requested templates (or all) and return the emitted distribution names."""
    from configurator.sources import vendor_skills  # noqa: PLC0415 (avoid cycle; lazy)

    registry = discover_templates(root / "templates")
    refs = sorted(registry) if all_templates else [ref_for_name(t, registry) for t in targets]
    written: list[str] = []
    for ref in refs:
        merged = load_and_resolve(ref, registry)
        payloads = vendor_skills(merged, root)
        if dry_run:
            with TemporaryDirectory() as tmp:
                emit_distribution(merged, Path(tmp) / merged.name, payloads)
        else:
            emit_distribution(merged, root / "dist" / merged.name, payloads)
        written.append(merged.name)
    if not dry_run:
        _write_catalog(root, registry)
    return written


def _cmd_compile(args: argparse.Namespace) -> int:
    names = run(
        root=args.root, targets=args.targets, all_templates=args.all, dry_run=args.dry_run,
    )
    verb = "would compile" if args.dry_run else "compiled"
    print(f"{verb}: {', '.join(names) if names else '(none)'}")
    return 0


def _cmd_list(args: argparse.Namespace) -> int:
    registry = discover_templates(args.root / "templates")
    for ref in sorted(registry):
        tpl = registry[ref]
        print(f"{ref:32} kind={tpl.kind:8} name={tpl.name}")
    return 0


def _cmd_verify(args: argparse.Namespace) -> int:
    from configurator.verify import run_verify  # noqa: PLC0415

    return run_verify(args.root)


def _cmd_ingest(args: argparse.Namespace) -> int:
    from configurator.ingest import run_ingest  # noqa: PLC0415

    return run_ingest(args.root, profile=args.profile)


def _cmd_update_locks(args: argparse.Namespace) -> int:
    from configurator.sources import update_locks  # noqa: PLC0415

    return update_locks(args.root, targets=args.targets)


def _load_yaml_or_empty(path: Path | None) -> dict[str, object]:
    from configurator.yamlio import load_yaml  # noqa: PLC0415

    return load_yaml(path) if path is not None and path.exists() else {}


def _provenance_hash(path: Path | None) -> str | None:
    """Read ``config.last_written_normalized_sha256`` from the installer's profile-state sidecar."""
    import json  # noqa: PLC0415

    if path is None or not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    cfg = data.get("config") if isinstance(data, dict) else None
    stamp = cfg.get("last_written_normalized_sha256") if isinstance(cfg, dict) else None
    return stamp if isinstance(stamp, str) else None


def _cmd_merge_config(args: argparse.Namespace) -> int:
    """Pure config.yaml merge for the EXTEND apply flow. Reads/writes only the paths passed in."""
    import json  # noqa: PLC0415

    from configurator.profile_merge import apply_decisions, normalized_hash, plan_merge  # noqa: PLC0415
    from configurator.yamlio import dump_yaml  # noqa: PLC0415

    existing = _load_yaml_or_empty(args.existing)
    incoming = _load_yaml_or_empty(args.incoming)
    if args.action == "plan":
        plan = plan_merge(
            existing, incoming,
            default=_load_yaml_or_empty(args.default) or None,
            provenance_hash=_provenance_hash(args.provenance),
        )
        if args.candidate is not None:
            write_text(args.candidate, dump_yaml(plan.merged))
        result: dict[str, object] = {
            "schema": 1, "status": "ok", "strategy": plan.strategy, "pristine": plan.pristine,
            "candidate": str(args.candidate) if args.candidate else None,
            "added": list(plan.added), "list_appended": list(plan.list_appended),
            "conflicts": [c.as_json() for c in plan.conflicts], "warnings": list(plan.warnings),
            "normalized_sha256": normalized_hash(plan.merged),
            "source_config_sha256": normalized_hash(incoming),
        }
    else:
        raw = json.loads(args.decisions.read_text(encoding="utf-8")) if args.decisions else {}
        dec_raw = raw.get("decisions", []) if isinstance(raw, dict) else []
        if isinstance(dec_raw, dict):  # PowerShell ConvertTo-Json renders a 1-element array as an object
            dec_raw = [dec_raw]
        decisions = {
            str(d["path"]): str(d["choice"])
            for d in dec_raw if isinstance(d, dict) and "path" in d and "choice" in d
        }
        merged = apply_decisions(existing, incoming, decisions)
        if args.out is not None:
            write_text(args.out, dump_yaml(merged))
        result = {"schema": 1, "status": "ok", "out": str(args.out) if args.out else None,
                  "normalized_sha256": normalized_hash(merged)}
    print(dump_json(result), end="")
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="configurator", description=__doc__)
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help="repo root (default: package root)")
    sub = parser.add_subparsers(dest="command", required=True)

    compile_p = sub.add_parser("compile", help="compile templates into dist/")
    compile_p.add_argument("targets", nargs="*", help="template refs or names")
    compile_p.add_argument("--all", action="store_true", help="compile every template")
    compile_p.add_argument("--dry-run", action="store_true", help="emit to a temp dir, write nothing")
    compile_p.set_defaults(func=_cmd_compile)

    sub.add_parser("list", help="list discovered templates").set_defaults(func=_cmd_list)

    verify_p = sub.add_parser("verify", help="run config/secret/lock/DOX gates")
    verify_p.add_argument("--dox", action="store_true", help="(accepted; DOX chain is always checked)")
    verify_p.set_defaults(func=_cmd_verify)

    ingest_p = sub.add_parser("ingest", help="diff the live config.yaml against base/general")
    ingest_p.add_argument("--profile", default=None, help="named profile to read (default: default home)")
    ingest_p.set_defaults(func=_cmd_ingest)

    locks_p = sub.add_parser("update-locks", help="re-resolve skill sources and rewrite locks/")
    locks_p.add_argument("targets", nargs="*", help="template refs or names (default: all)")
    locks_p.set_defaults(func=_cmd_update_locks)

    mc = sub.add_parser(
        "merge-config",
        help="merge a distribution config.yaml into a live profile config (pure; no hermes calls)",
    )
    mc.add_argument("action", choices=["plan", "apply-decisions"], help="plan a merge or apply user decisions")
    mc.add_argument("--existing", type=Path, required=True, help="the live profile config.yaml (may not exist)")
    mc.add_argument("--incoming", type=Path, required=True, help="the distribution's config.yaml")
    mc.add_argument("--default", type=Path, default=None, help="the base/general config.yaml (pristine reference)")
    mc.add_argument("--provenance", type=Path, default=None, help="profile-state.json sidecar (pristine reference)")
    mc.add_argument("--candidate", type=Path, default=None, help="[plan] write the merged candidate here")
    mc.add_argument("--decisions", type=Path, default=None, help="[apply-decisions] JSON of per-conflict choices")
    mc.add_argument("--out", type=Path, default=None, help="[apply-decisions] write the resolved config here")
    mc.set_defaults(func=_cmd_merge_config)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Parse args and dispatch. Configurator errors render at this boundary as exit code 1."""
    args = _build_parser().parse_args(argv)
    try:
        result: int = args.func(args)
    except ConfiguratorError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    return result


if __name__ == "__main__":
    sys.exit(main())
