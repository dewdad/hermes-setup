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
