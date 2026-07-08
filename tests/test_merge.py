"""Merge + inheritance resolution semantics."""

from __future__ import annotations

import unittest

from configurator.errors import MergeError
from configurator.merge import merge_config, resolve
from configurator.model import Template, TemplateKind
from configurator.parse import parse_template


def _tpl(name: str, kind: str, extends: str | None, **extra: object) -> Template:
    data: dict[str, object] = {"name": name, "kind": kind}
    if extends is not None:
        data["extends"] = extends
    data.update(extra)
    return parse_template(data)  # type: ignore[arg-type]


class MergeConfigDeepMerge(unittest.TestCase):
    def test_child_scalar_overrides_parent(self) -> None:
        parent = {"model": {"provider": "zenmux", "max_tokens": 8192}}
        child = {"model": {"provider": "openai"}}
        result = merge_config(parent, child)
        self.assertEqual(result["model"], {"provider": "openai", "max_tokens": 8192})

    def test_child_adds_new_key(self) -> None:
        result = merge_config({"a": 1}, {"b": 2})
        self.assertEqual(result, {"a": 1, "b": 2})

    def test_parent_not_mutated(self) -> None:
        parent = {"nested": {"x": 1}}
        merge_config(parent, {"nested": {"y": 2}})
        self.assertEqual(parent, {"nested": {"x": 1}})


class MergeConfigLists(unittest.TestCase):
    def test_list_set_union_appends_new(self) -> None:
        parent = {"fallback_providers": [{"provider": "a"}]}
        child = {"fallback_providers": [{"provider": "b"}]}
        result = merge_config(parent, child)
        self.assertEqual(result["fallback_providers"], [{"provider": "a"}, {"provider": "b"}])

    def test_list_union_dedups(self) -> None:
        result = merge_config({"xs": ["a"]}, {"xs": ["a", "c"]})
        self.assertEqual(result["xs"], ["a", "c"])

    def test_list_remove_marker_prunes_parent_item(self) -> None:
        parent = {"xs": [{"provider": "a"}, {"provider": "b"}]}
        child = {"xs": [{"!remove": {"provider": "a"}}, {"provider": "c"}]}
        result = merge_config(parent, child)
        self.assertEqual(result["xs"], [{"provider": "b"}, {"provider": "c"}])


class ResolveInheritance(unittest.TestCase):
    def setUp(self) -> None:
        self.base = _tpl(
            "general",
            "base",
            None,
            config={"model": {"provider": "zenmux"}, "security": {"redact_secrets": True}},
            env=[{"name": "ZENMUX_API_KEY", "required": False}],
            skills={"bundled": "none", "include": [
                {"source": "github", "id": "org/repo/skills/keep"},
                {"source": "github", "id": "org/repo/skills/drop"},
            ]},
        )
        self.locale = _tpl(
            "il",
            "locale",
            "base/general",
            config={"model": {"default": "anthropic/claude-sonnet-5-free"}},
            skills={"exclude": ["drop"], "include": [
                {"source": "github", "id": "org/repo/skills/hebrew"},
            ]},
        )
        self.registry = {"base/general": self.base, "locale/il": self.locale}

    def _resolver(self, ref: str) -> Template:
        return self.registry[ref]

    def test_config_deep_merged_root_first(self) -> None:
        merged = resolve(self.locale, self._resolver)
        self.assertEqual(merged.config["model"], {
            "provider": "zenmux",
            "default": "anthropic/claude-sonnet-5-free",
        })
        self.assertEqual(merged.config["security"], {"redact_secrets": True})

    def test_skill_exclude_prunes_inherited(self) -> None:
        merged = resolve(self.locale, self._resolver)
        ids = [s.id for s in merged.skills.include]
        self.assertIn("org/repo/skills/keep", ids)
        self.assertIn("org/repo/skills/hebrew", ids)
        self.assertNotIn("org/repo/skills/drop", ids)

    def test_base_resolves_to_itself(self) -> None:
        merged = resolve(self.base, self._resolver)
        self.assertEqual(merged.name, "general")
        self.assertEqual(merged.kind, TemplateKind.BASE)


class PostInstallMerge(unittest.TestCase):
    def test_child_exclude_prunes_inherited_post_install(self) -> None:
        base = _tpl(
            "general", "base", None,
            post_install=[{"id": "official/research/duckduckgo-search"}],
        )
        child = _tpl(
            "therapist", "persona", "base/general",
            skills={"exclude": ["duckduckgo-search"]},
        )
        merged = resolve(child, lambda _ref: base)
        self.assertEqual([p.id for p in merged.post_install], [])

    def test_child_post_install_appends_and_dedups_by_id(self) -> None:
        base = _tpl("general", "base", None, post_install=[{"id": "a/b/docx"}])
        child = _tpl(
            "il", "locale", "base/general",
            post_install=[{"id": "a/b/docx", "note": "override"}, {"id": "c/d/rtl"}],
        )
        merged = resolve(child, lambda _ref: base)
        self.assertEqual([p.id for p in merged.post_install], ["a/b/docx", "c/d/rtl"])
        self.assertEqual(merged.post_install[0].note, "override")


class DiscoveryMerge(unittest.TestCase):
    def test_discovery_set_union_base_then_locale(self) -> None:
        base = _tpl("general", "base", None, discovery=[
            {"label": "Hub", "url": "https://skills.sh"},
        ])
        locale = _tpl("il", "locale", "base/general", discovery=[
            {"label": "IL", "url": "https://agentskills.co.il"},
        ])
        merged = resolve(locale, lambda _ref: base)
        self.assertEqual(
            [d.url for d in merged.discovery],
            ["https://skills.sh", "https://agentskills.co.il"],
        )

    def test_discovery_dedups_by_url_child_overrides(self) -> None:
        base = _tpl("general", "base", None, discovery=[{"label": "old", "url": "https://x"}])
        child = _tpl("il", "locale", "base/general", discovery=[{"label": "new", "url": "https://x"}])
        merged = resolve(child, lambda _ref: base)
        self.assertEqual([(d.label, d.url) for d in merged.discovery], [("new", "https://x")])


class TierMerge(unittest.TestCase):
    def test_post_install_tier_carried_through_merge(self) -> None:
        base = _tpl("general", "base", None, post_install=[{"id": "a/b/c", "tier": 1}])
        child = _tpl("il", "locale", "base/general", post_install=[{"id": "d/e/f", "tier": 0}])
        merged = resolve(child, lambda _ref: base)
        by_id = {p.id: p.tier for p in merged.post_install}
        self.assertEqual(by_id, {"a/b/c": 1, "d/e/f": 0})


class SetupStepsMerge(unittest.TestCase):
    def test_child_setup_steps_append_and_dedup_by_id(self) -> None:
        base = _tpl("general", "base", None, setup_steps=[{"id": "rtk", "note": "base"}])
        child = _tpl(
            "dev", "persona", "base/general",
            setup_steps=[{"id": "rtk", "note": "override"}, {"id": "other"}],
        )
        merged = resolve(child, lambda _ref: base)
        self.assertEqual([s.id for s in merged.setup_steps], ["rtk", "other"])
        self.assertEqual(merged.setup_steps[0].note, "override")

    def test_child_exclude_prunes_inherited_setup_step_by_id(self) -> None:
        base = _tpl("general", "base", None, setup_steps=[{"id": "rtk"}])
        child = _tpl("min", "persona", "base/general", skills={"exclude": ["rtk"]})
        merged = resolve(child, lambda _ref: base)
        self.assertEqual([s.id for s in merged.setup_steps], [])


class ResolveGuards(unittest.TestCase):
    def test_cycle_detected(self) -> None:
        a = _tpl("a", "persona", "p/b")
        b = _tpl("b", "persona", "p/a")
        registry = {"p/a": a, "p/b": b}
        with self.assertRaises(MergeError):
            resolve(a, lambda ref: registry[ref])

    def test_illegal_kind_ordering_rejected(self) -> None:
        # A locale extending a persona inverts the base -> locale -> persona ordering.
        base = _tpl("g", "base", None)
        persona = _tpl("p", "persona", "b/g")
        child = _tpl("l", "locale", "x/p")
        registry = {"b/g": base, "x/p": persona}
        with self.assertRaises(MergeError):
            resolve(child, lambda ref: registry[ref])


if __name__ == "__main__":
    unittest.main()
