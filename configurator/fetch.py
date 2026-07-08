"""Network fetchers for vendoring skills (stdlib only: urllib + tarfile).

Used exclusively by ``update-locks`` — never by ``compile`` (which reads the committed
``skills-vendor/`` cache). GitHub skills are pulled as a codeload tarball pinned to a ref; URL
skills are a single ``SKILL.md``. Failures raise :class:`SourceError`.
"""

from __future__ import annotations

import tarfile
import tempfile
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen

from configurator.errors import SourceError

_TIMEOUT = 30


def _read(url: str, source_id: str) -> bytes:
    try:
        with urlopen(url, timeout=_TIMEOUT) as resp:  # noqa: S310 (http(s)/file by design)
            return resp.read()
    except (URLError, OSError, ValueError) as exc:
        raise SourceError(source_id=source_id, reason=f"fetch failed for {url}: {exc}") from exc


def fetch_url(url: str, dest_dir: Path, source_id: str) -> None:
    """Fetch a single SKILL.md from ``url`` into ``dest_dir/SKILL.md``."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    (dest_dir / "SKILL.md").write_bytes(_read(url, source_id))


def fetch_github(repo: str, subpath: str, ref: str, dest_dir: Path, source_id: str) -> None:
    """Fetch ``subpath`` of ``owner/repo`` at ``ref`` via the codeload tarball into ``dest_dir``."""
    url = f"https://codeload.github.com/{repo}/tar.gz/{ref}"
    payload = _read(url, source_id)
    dest_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        archive = Path(tmp) / "src.tar.gz"
        archive.write_bytes(payload)
        with tarfile.open(archive, "r:gz") as tar:
            top = tar.getnames()[0].split("/", 1)[0]
            wanted = f"{top}/{subpath}".rstrip("/")
            members = [m for m in tar.getmembers() if m.name == wanted or m.name.startswith(wanted + "/")]
            if not members:
                raise SourceError(source_id=source_id, reason=f"subpath '{subpath}' not found in {repo}@{ref}")
            for member in members:
                rel = member.name[len(wanted):].lstrip("/")
                if member.isdir():
                    (dest_dir / rel).mkdir(parents=True, exist_ok=True)
                    continue
                extracted = tar.extractfile(member)
                if extracted is None:
                    continue
                target = dest_dir / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(extracted.read())


def resolve_well_known(endpoint: str, source_id: str) -> str:
    """Resolve a well-known endpoint (skills.sh/browse.sh) to a concrete SKILL.md URL.

    The public well-known endpoints already serve raw SKILL.md at the identifier URL, so the
    endpoint is returned as-is after a reachability check; callers then vendor it like a URL skill.
    """
    _read(endpoint, source_id)
    return endpoint
