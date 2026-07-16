"""The generated finish-setup meta-skill: frontmatter, tiering, discovery, determinism."""

from __future__ import annotations

import unittest

import yaml

from configurator.errors import SecretLeakError
from configurator.parse import parse_template
from configurator.secretscan import scan_text
from configurator.setup_skill import (
    FINISH_SETUP_NAME,
    build_finish_setup_skill,
)


def _tpl(**extra: object) -> object:
    data: dict[str, object] = {"name": "general", "kind": "base"}
    data.update(extra)
    return parse_template(data)  # type: ignore[arg-type]


def _split_frontmatter(text: str) -> tuple[dict[str, object], str]:
    assert text.startswith("---\n")
    _, block, body = text.split("---\n", 2)
    meta = yaml.safe_load(block)
    return meta, body


class Frontmatter(unittest.TestCase):
    def test_frontmatter_fields(self) -> None:
        meta, _ = _split_frontmatter(build_finish_setup_skill(_tpl()))  # type: ignore[arg-type]
        self.assertEqual(meta["name"], FINISH_SETUP_NAME)
        self.assertEqual(meta["metadata"], {"hermes": {"category": "meta"}})
        self.assertEqual(meta["tags"], ["setup", "onboarding"])

    def test_description_is_short(self) -> None:
        meta, _ = _split_frontmatter(build_finish_setup_skill(_tpl()))  # type: ignore[arg-type]
        self.assertLessEqual(len(str(meta["description"])), 60)


class EnvTable(unittest.TestCase):
    def test_env_vars_render_as_key_lines(self) -> None:
        tpl = _tpl(env=[
            {"name": "ZENMUX_API_KEY", "description": "primary at https://zenmux.ai"},
            {"name": "NVIDIA_API_KEY", "description": "fallback"},
        ])
        text = build_finish_setup_skill(tpl)  # type: ignore[arg-type]
        self.assertIn("**ZENMUX_API_KEY**", text)
        self.assertIn("**NVIDIA_API_KEY**", text)
        # Honest Tier-0: free chat baseline is the Nous Portal free plan; adding any ONE key is
        # optional (unlocks higher-tier free models); browser/web are keyless.
        self.assertIn("Nous Portal", text)
        self.assertIn("any one", text.lower())
        self.assertIn("keyless", text.lower())

    def test_no_env_states_no_keys_needed(self) -> None:
        text = build_finish_setup_skill(_tpl())  # type: ignore[arg-type]
        self.assertIn("no provider keys", text.lower())


class PortalAuth(unittest.TestCase):
    def test_portal_base_renders_oauth_login_not_keys(self) -> None:
        tpl = _tpl(portal_auth=True, env=[])
        text = build_finish_setup_skill(tpl)  # type: ignore[arg-type]
        self.assertIn("### 1. Nous Portal login (required)", text)
        self.assertIn("paid Nous Portal subscription", text)
        self.assertIn("hermes setup --portal", text)
        self.assertNotIn("### 1. Provider keys (optional)", text)

    def test_free_base_renders_provider_keys_not_portal_login(self) -> None:
        tpl = _tpl(env=[{"name": "ZENMUX_API_KEY", "description": "primary"}])
        text = build_finish_setup_skill(tpl)  # type: ignore[arg-type]
        self.assertIn("### 1. Provider keys (optional)", text)
        self.assertNotIn("### 1. Nous Portal login (required)", text)


class TieredSkillList(unittest.TestCase):
    def _text(self) -> str:
        tpl = _tpl(post_install=[
            {"id": "skills-sh/dewdad/open-skills/web-search-api", "note": "SearXNG", "tier": 0},
            {"id": "official/research/duckduckgo-search", "note": "fallback"},  # default tier 0
            {"id": "skills-sh/dewdad/beeper-desktop-api-skill/beeper-desktop-api",
             "note": "messaging", "tier": 1},
        ])
        return build_finish_setup_skill(tpl)  # type: ignore[arg-type]

    def test_tier0_and_tier1_sections_present(self) -> None:
        text = self._text()
        self.assertIn("Tier 0", text)
        self.assertIn("Tier 1", text)

    def test_tier0_before_tier1(self) -> None:
        text = self._text()
        self.assertLess(text.index("Tier 0"), text.index("Tier 1"))

    def test_tier1_skill_grouped_under_tier1(self) -> None:
        text = self._text()
        # The beeper (tier 1) id must appear after the Tier 1 heading, not in the Tier 0 block.
        self.assertGreater(text.index("beeper-desktop-api"), text.index("Tier 1"))
        self.assertLess(text.index("web-search-api"), text.index("Tier 1"))

    def test_tap_ref_uses_tap_add_verb(self) -> None:
        tpl = _tpl(post_install=[{"id": "obra/superpowers", "tap": True}])
        self.assertIn("hermes skills tap add obra/superpowers", build_finish_setup_skill(tpl))  # type: ignore[arg-type]


class SetupStepsSection(unittest.TestCase):
    def test_setup_step_rendered_with_command(self) -> None:
        tpl = _tpl(setup_steps=[{
            "id": "rtk", "label": "RTK (Rust Token Killer)", "note": "token saver", "tier": 0,
            "posix_run": "rtk init --agent hermes",
            "windows_run": "rtk init --agent hermes",
        }])
        text = build_finish_setup_skill(tpl)  # type: ignore[arg-type]
        self.assertIn("Local tools", text)
        self.assertIn("RTK (Rust Token Killer)", text)
        self.assertIn("rtk init --agent hermes", text)

    def test_tier1_setup_step_marked_opt_in(self) -> None:
        tpl = _tpl(setup_steps=[{"id": "x", "label": "X", "tier": 1, "posix_run": "do-x"}])
        self.assertIn("Tier 1", build_finish_setup_skill(tpl))  # type: ignore[arg-type]

    def test_no_setup_steps_no_local_tools_block(self) -> None:
        self.assertNotIn("Local tools", build_finish_setup_skill(_tpl()))  # type: ignore[arg-type]


class ExternalOptIn(unittest.TestCase):
    def test_multi_gws_guided_block_when_external_dir_present(self) -> None:
        tpl = _tpl(skills={"external_dirs": ["~/multi-gws-cli", "~/open-skills/skills"]})
        text = build_finish_setup_skill(tpl)  # type: ignore[arg-type]
        self.assertIn("multi-gws-cli", text)
        self.assertIn("open-skills", text)

    def test_no_guided_block_without_external_dirs(self) -> None:
        text = build_finish_setup_skill(_tpl())  # type: ignore[arg-type]
        self.assertNotIn("Google Workspace", text)


class AssistantSection(unittest.TestCase):
    _SURFACE_ENV = [
        {"name": "TELEGRAM_BOT_TOKEN", "description": "bot via @BotFather"},
        {"name": "TELEGRAM_HOME_CHANNEL", "description": "chat id"},
    ]
    _DELIVER_CRON = [
        {"name": "morning-brief", "schedule": "0 8 * * *", "prompt": "brief", "deliver": "telegram",
         "enabled": False},
        {"name": "followup-sweep", "schedule": "0 18 * * *", "prompt": "sweep", "deliver": "telegram",
         "enabled": False},
    ]

    def test_section_present_with_surface_env(self) -> None:
        text = build_finish_setup_skill(_tpl(env=self._SURFACE_ENV))  # type: ignore[arg-type]
        self.assertIn("Mobile chat & proactive reminders", text)
        self.assertIn("hermes gateway setup", text)

    def test_resume_commands_render_for_deliver_cron(self) -> None:
        text = build_finish_setup_skill(_tpl(cron=self._DELIVER_CRON))  # type: ignore[arg-type]
        self.assertIn("Mobile chat & proactive reminders", text)
        self.assertIn("hermes cron resume morning-brief", text)
        self.assertIn("hermes cron resume followup-sweep", text)

    def test_section_absent_without_surface_or_deliver_cron(self) -> None:
        # A non-messaging cron job (command/args, no deliver) must NOT trigger the section.
        tpl = _tpl(cron=[{"name": "sync", "schedule": "0 4 * * *", "command": "git"}])
        text = build_finish_setup_skill(tpl)  # type: ignore[arg-type]
        self.assertNotIn("Mobile chat & proactive reminders", text)

    def test_surface_env_without_deliver_cron_omits_resume_step(self) -> None:
        text = build_finish_setup_skill(_tpl(env=self._SURFACE_ENV))  # type: ignore[arg-type]
        self.assertNotIn("hermes cron resume", text)


class DiscoverMore(unittest.TestCase):
    def test_discovery_entries_render_as_links(self) -> None:
        tpl = _tpl(discovery=[
            {"label": "agentskills.co.il", "url": "https://agentskills.co.il", "note": "IL"},
        ])
        text = build_finish_setup_skill(tpl)  # type: ignore[arg-type]
        self.assertIn("[agentskills.co.il](https://agentskills.co.il)", text)

    def test_search_verbs_always_present(self) -> None:
        text = build_finish_setup_skill(_tpl())  # type: ignore[arg-type]
        self.assertIn("hermes skills search", text)
        self.assertIn("hermes skills install", text)


class Sections(unittest.TestCase):
    def test_standard_sections_present(self) -> None:
        text = build_finish_setup_skill(_tpl())  # type: ignore[arg-type]
        for heading in ("## When to Use", "## Procedure", "## Pitfalls", "## Verification"):
            self.assertIn(heading, text)


class PerProfileSessions(unittest.TestCase):
    def test_per_profile_sessions_note_present(self) -> None:
        # #5: finish-setup must explain sessions/auth are per-profile and how to switch, so a user
        # who installed a NEW profile does not think their history was wiped.
        text = build_finish_setup_skill(_tpl())  # type: ignore[arg-type]
        low = text.lower()
        self.assertIn("per-profile", low)
        self.assertIn("hermes profile use", text)
        self.assertIn("hermes -p", text)


class SecretScan(unittest.TestCase):
    def test_env_names_and_catalogue_urls_pass_scan(self) -> None:
        tpl = _tpl(
            env=[{"name": "ZENMUX_API_KEY", "description": "key at https://zenmux.ai/platform"},
                 {"name": "GOOGLE_API_KEY", "description": "AI Studio https://aistudio.google.com/app/apikey"}],
            post_install=[{"id": "skills-sh/dewdad/open-skills/web-search-api", "tier": 0}],
            discovery=[{"label": "agentskills.co.il", "url": "https://agentskills.co.il"}],
        )
        # Must not raise — env var NAMES and URLs are not credential literals.
        scan_text(build_finish_setup_skill(tpl), where="finish-setup/SKILL.md")  # type: ignore[arg-type]

    def test_planted_key_in_note_fails_scan(self) -> None:
        tpl = _tpl(post_install=[{"id": "a/b/c", "note": "AKIAIOSFODNN7EXAMPLE1234", "tier": 0}])
        with self.assertRaises(SecretLeakError):
            scan_text(build_finish_setup_skill(tpl), where="finish-setup/SKILL.md")  # type: ignore[arg-type]


class Determinism(unittest.TestCase):
    def test_build_twice_is_identical(self) -> None:
        tpl = _tpl(
            env=[{"name": "ZENMUX_API_KEY", "description": "primary"}],
            post_install=[{"id": "a/b/c", "tier": 0}, {"id": "d/e/f", "tier": 1}],
            discovery=[{"label": "X", "url": "https://x.example"}],
        )
        self.assertEqual(build_finish_setup_skill(tpl), build_finish_setup_skill(tpl))  # type: ignore[arg-type]


if __name__ == "__main__":
    unittest.main()
