"""Detect key-shaped literals in emitted output.

The config contract is that secrets appear only as ``${VAR}`` / ``key_env`` references. Any literal
that looks like a real credential fails the build. Values containing a ``${...}`` reference are
always treated as clean; model ids and URLs (which carry ``/`` or ``://``) never match the generic
token shape, so false positives are rare.
"""

from __future__ import annotations

import re

from configurator.errors import SecretLeakError
from configurator.yamlio import YamlValue

# Known credential prefixes seen across the providers this repo touches and common ecosystems.
_PREFIX = re.compile(
    r"(sk-[A-Za-z0-9]|sk-ant-|sk-proj-|ghp_|gho_|ghs_|github_pat_|glpat-|xox[baprs]-|"
    r"AKIA|ASIA|AIza[0-9A-Za-z\-_]|hf_[A-Za-z0-9]|nvapi-|r8_[A-Za-z0-9]|dop_v1_|ya29\.|"
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----)",
)
# A bare, high-entropy single token of credential length. Excludes hyphens (which word-break
# slugs like ``israeli-accessibility-compliance``) and requires a digit — real API keys/tokens are
# mixed alphanumeric, whereas identifiers/slugs are not.
_TOKEN = re.compile(r"^[A-Za-z0-9_+/=]{32,}$")


def looks_like_secret(value: str) -> str | None:
    """Return a human hint if the string looks like a credential literal, else None."""
    if "${" in value:
        return None
    if _PREFIX.search(value):
        return "matches a known API-key/token prefix"
    token = value.strip()
    if _TOKEN.match(token) and any(c.isdigit() for c in token):
        return "looks like a high-entropy credential token; use ${VAR} / key_env instead"
    return None


def scan_config(data: YamlValue, where: str, key_path: str = "") -> None:
    """Recursively scan a value tree; raise :class:`SecretLeakError` on the first literal secret."""
    match data:
        case dict():
            for key, value in data.items():
                scan_config(value, where, f"{key_path}.{key}" if key_path else str(key))
        case list():
            for index, item in enumerate(data):
                scan_config(item, where, f"{key_path}[{index}]")
        case str():
            hint = looks_like_secret(data)
            if hint is not None:
                raise SecretLeakError(where=where, key_path=key_path or "<root>", hint=hint)
        case _:
            return


def scan_text(text: str, where: str) -> None:
    """Scan free-form emitted text (SOUL, README, bundles, scripts) token-by-token for secrets."""
    for lineno, line in enumerate(text.splitlines(), start=1):
        for token in line.split():
            hint = looks_like_secret(token.strip("\"'`,;()[]{}<>"))
            if hint is not None:
                raise SecretLeakError(where=where, key_path=f"line {lineno}", hint=hint)
