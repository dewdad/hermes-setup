"""Existing-preserving profile config.yaml merge semantics (EXTEND apply path)."""

from __future__ import annotations

import unittest

from configurator.profile_merge import (
    Conflict,
    apply_decisions,
    is_pristine,
    normalized_hash,
    plan_merge,
)


def _paths(conflicts: tuple[Conflict, ...]) -> set[str]:
    return {c.path for c in conflicts}


class AddsMissingKeys(unittest.TestCase):
    def test_missing_top_level_key_added(self) -> None:
        plan = plan_merge({"model": {"provider": "zenmux"}}, {"model": {"provider": "zenmux"}, "web": {"backend": "ddgs"}})
        self.assertEqual(plan.strategy, "merge")
        self.assertEqual(plan.merged["web"], {"backend": "ddgs"})
        self.assertIn("web", plan.added)
        self.assertEqual(plan.conflicts, ())

    def test_missing_subkey_added_without_touching_siblings(self) -> None:
        existing = {"model": {"provider": "openrouter"}}
        incoming = {"model": {"provider": "openrouter", "max_tokens": 128000}}
        plan = plan_merge(existing, incoming)
        self.assertEqual(plan.merged["model"], {"provider": "openrouter", "max_tokens": 128000})
        self.assertIn("model.max_tokens", plan.added)
        self.assertEqual(plan.conflicts, ())

    def test_equal_scalar_is_noop(self) -> None:
        plan = plan_merge({"a": {"b": 1}}, {"a": {"b": 1}})
        # equal to incoming => pristine overwrite, no conflicts
        self.assertEqual(plan.conflicts, ())


class ScalarAndTypeConflicts(unittest.TestCase):
    def test_scalar_diff_is_conflict_keeps_existing(self) -> None:
        existing = {"model": {"provider": "openrouter"}, "extra": 1}
        incoming = {"model": {"provider": "nous"}, "extra": 1}
        plan = plan_merge(existing, incoming)
        self.assertEqual(_paths(plan.conflicts), {"model.provider"})
        self.assertEqual(plan.merged["model"]["provider"], "openrouter")  # existing wins in the candidate
        self.assertEqual(plan.conflicts[0].kind, "scalar")

    def test_dict_vs_scalar_is_type_conflict(self) -> None:
        existing = {"web": {"backend": "ddgs"}, "x": 1}
        incoming = {"web": "off", "x": 2}
        plan = plan_merge(existing, incoming)
        kinds = {c.path: c.kind for c in plan.conflicts}
        self.assertEqual(kinds["web"], "type")
        self.assertEqual(kinds["x"], "scalar")
        self.assertEqual(plan.merged["web"], {"backend": "ddgs"})

    def test_sensitive_path_previews_redacted(self) -> None:
        existing = {"providers": {"zen": {"key_env": "AAA"}}, "n": 1}
        incoming = {"providers": {"zen": {"key_env": "BBB"}}, "n": 2}
        plan = plan_merge(existing, incoming)
        by_path = {c.path: c for c in plan.conflicts}
        self.assertTrue(by_path["providers.zen.key_env"].sensitive)
        self.assertEqual(by_path["providers.zen.key_env"].existing_preview, "<redacted>")
        self.assertFalse(by_path["n"].sensitive)


class ListPolicies(unittest.TestCase):
    def test_external_dirs_union_preserves_order_appends_missing(self) -> None:
        existing = {"skills": {"external_dirs": ["~/mine", "meta-skills"]}, "z": 1}
        incoming = {"skills": {"external_dirs": ["meta-skills", "~/open-skills/skills"]}, "z": 2}
        plan = plan_merge(existing, incoming)
        self.assertEqual(plan.merged["skills"]["external_dirs"], ["~/mine", "meta-skills", "~/open-skills/skills"])
        self.assertEqual(_paths(plan.conflicts), {"z"})  # list itself is not a conflict

    def test_fallback_providers_union_by_provider_model(self) -> None:
        existing = {"fallback_providers": [{"provider": "nvidia", "model": "glm-5.2"}], "z": 1}
        incoming = {
            "fallback_providers": [
                {"provider": "nvidia", "model": "glm-5.2"},
                {"provider": "nous", "model": "stepfun/step-3.7-flash:free"},
            ],
            "z": 2,
        }
        plan = plan_merge(existing, incoming)
        self.assertEqual(len(plan.merged["fallback_providers"]), 2)
        self.assertEqual(plan.merged["fallback_providers"][0]["provider"], "nvidia")  # order preserved
        self.assertTrue(any("fallback_providers" in a for a in plan.list_appended))

    def test_same_provider_identity_diff_fields_keeps_existing_and_warns(self) -> None:
        existing = {"fallback_providers": [{"provider": "nvidia", "model": "glm-5.2", "weight": 1}], "z": 1}
        incoming = {"fallback_providers": [{"provider": "nvidia", "model": "glm-5.2", "weight": 9}], "z": 2}
        plan = plan_merge(existing, incoming)
        self.assertEqual(plan.merged["fallback_providers"][0]["weight"], 1)
        self.assertTrue(plan.warnings)

    def test_unknown_list_diff_is_whole_list_conflict(self) -> None:
        existing = {"plugins": {"enabled": ["a"]}, "z": 1}
        incoming = {"plugins": {"enabled": ["b"]}, "z": 2}
        plan = plan_merge(existing, incoming)
        self.assertIn("plugins.enabled", _paths(plan.conflicts))
        self.assertEqual(plan.merged["plugins"]["enabled"], ["a"])


class ConfigVersion(unittest.TestCase):
    def test_lower_existing_version_upgraded_to_incoming(self) -> None:
        plan = plan_merge({"_config_version": 30, "a": 1}, {"_config_version": 33, "a": 2})
        self.assertEqual(plan.merged["_config_version"], 33)
        self.assertNotIn("_config_version", _paths(plan.conflicts))

    def test_higher_existing_version_preserved_with_warning(self) -> None:
        plan = plan_merge({"_config_version": 40, "a": 1}, {"_config_version": 33, "a": 2})
        self.assertEqual(plan.merged["_config_version"], 40)
        self.assertTrue(any("_config_version" in w for w in plan.warnings))


class PristineDetection(unittest.TestCase):
    def test_missing_existing_is_copy(self) -> None:
        plan = plan_merge({}, {"model": {"provider": "zenmux"}})
        self.assertEqual(plan.strategy, "copy")
        self.assertTrue(plan.pristine)

    def test_equal_to_default_overwrites(self) -> None:
        default = {"model": {"provider": "opencode-zen"}, "web": {"backend": "ddgs"}}
        existing = {"model": {"provider": "opencode-zen"}, "web": {"backend": "ddgs"}}
        incoming = {"model": {"provider": "opencode-zen"}, "web": {"backend": "ddgs"}, "new": 1}
        plan = plan_merge(existing, incoming, default=default)
        self.assertEqual(plan.strategy, "overwrite")
        self.assertEqual(plan.merged, incoming)

    def test_equal_to_provenance_hash_overwrites(self) -> None:
        existing = {"model": {"provider": "x"}}
        prov = normalized_hash(existing)
        plan = plan_merge(existing, {"model": {"provider": "y"}}, provenance_hash=prov)
        self.assertEqual(plan.strategy, "overwrite")
        self.assertTrue(plan.pristine)

    def test_order_and_comment_independent_hash(self) -> None:
        self.assertEqual(normalized_hash({"a": 1, "b": 2}), normalized_hash({"b": 2, "a": 1}))

    def test_customized_config_is_not_pristine(self) -> None:
        self.assertFalse(is_pristine({"model": {"provider": "custom"}}, {"model": {"provider": "z"}}, None, None))


class ApplyDecisions(unittest.TestCase):
    def test_take_incoming_for_one_conflict(self) -> None:
        existing = {"model": {"provider": "openrouter"}, "browser": {"backend": "chrome"}}
        incoming = {"model": {"provider": "nous"}, "browser": {"backend": "local"}}
        merged = apply_decisions(existing, incoming, {"model.provider": "incoming", "browser.backend": "existing"})
        self.assertEqual(merged["model"]["provider"], "nous")
        self.assertEqual(merged["browser"]["backend"], "chrome")

    def test_unknown_decision_path_ignored(self) -> None:
        merged = apply_decisions({"a": 1}, {"a": 2}, {"does.not.exist": "incoming"})
        self.assertEqual(merged["a"], 1)


if __name__ == "__main__":
    unittest.main()
