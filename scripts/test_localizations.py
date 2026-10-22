#!/usr/bin/env python3
"""Negative fixtures prove the bilingual gate fails; no application data used."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

import audit_localizations as gate


class LocalizationGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="together-localization-fixture-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.apple = {"fixture.action": {"en": "Save", "zh-Hans": "保存"}}
        self.permission = {"NSMicrophoneUsageDescription": {
            "en": "Record a voice gift for your love.", "zh-Hans": "为伴侣录制爱意礼物。"}}
        self.android = {"fixture_action": {"en": "Save", "zh-Hans": "保存"}}

    def write(self):
        reviews = {}
        for relative, entries in zip(gate.APPLE_CATALOGS, (self.apple, self.permission)):
            catalog = {"sourceLanguage": "zh-Hans", "version": "1.0", "strings": {}}
            for key, translations in entries.items():
                catalog["strings"][key] = {"localizations": {
                    lang: {"stringUnit": {"state": "translated", "value": text}}
                    for lang, text in translations.items()}}
                reviews[key] = {"translationSHA256": {
                    lang: gate.sha256(text) for lang, text in translations.items()}}
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(catalog, ensure_ascii=False))
        path = self.root / gate.APPLE_REVIEW
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"entries": reviews}))
        android_reviews = {}
        for lang, relative in gate.ANDROID_RESOURCES.items():
            resources = ET.Element("resources")
            for key, translations in self.android.items():
                if lang not in translations:
                    continue
                text = translations[lang]
                ET.SubElement(resources, "string", name=key).text = text
                android_reviews[relative.parent.name + "/" + key] = {"sha256": gate.sha256(text)}
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            ET.ElementTree(resources).write(path, encoding="utf-8", xml_declaration=True)
        (self.root / gate.ANDROID_REVIEW).write_text(json.dumps(android_reviews))

    def report(self):
        self.write()
        return gate.audit(self.root)

    def assertIssue(self, report, kind, lang=None):
        self.assertEqual(report["status"], "FAIL")
        self.assertTrue(any(item["type"] == kind and (lang is None or item["lang"] == lang)
                            for item in report["issues"]), report)

    def test_complete_bilingual_resources_pass(self):
        report = self.report()
        self.assertEqual(report["status"], "PASS", report)
        self.assertEqual(report["localizedValues"], 6)

    def test_missing_apple_english_fails(self):
        del self.apple["fixture.action"]["en"]
        self.assertIssue(self.report(), "missing_translation", "en")

    def test_missing_permission_chinese_fails(self):
        del self.permission["NSMicrophoneUsageDescription"]["zh-Hans"]
        self.assertIssue(self.report(), "missing_translation", "zh-Hans")

    def test_missing_android_chinese_fails(self):
        del self.android["fixture_action"]["zh-Hans"]
        self.assertIssue(self.report(), "missing_translation", "zh-Hans")

    def test_changed_apple_english_review_fails(self):
        self.write()
        path = self.root / gate.APPLE_CATALOGS[0]
        doc = json.loads(path.read_text())
        doc["strings"]["fixture.action"]["localizations"]["en"]["stringUnit"]["value"] = "Keep"
        path.write_text(json.dumps(doc))
        self.assertIssue(gate.audit(self.root), "changed_since_review", "en")

    def test_missing_per_language_review_fails(self):
        self.write()
        path = self.root / gate.APPLE_REVIEW
        doc = json.loads(path.read_text())
        del doc["entries"]["fixture.action"]["translationSHA256"]["en"]
        path.write_text(json.dumps(doc))
        self.assertIssue(gate.audit(self.root), "changed_since_review", "en")

    def test_changed_android_chinese_review_fails(self):
        self.write()
        path = self.root / gate.ANDROID_RESOURCES["zh-Hans"]
        path.write_text(path.read_text().replace("保存", "存储"))
        self.assertIssue(gate.audit(self.root), "changed_since_review", "zh-Hans")

    def test_apple_format_type_change_fails(self):
        self.apple["fixture.action"] = {"zh-Hans": "%@ 项", "en": "%d items"}
        self.assertIssue(self.report(), "format_arguments", "en")

    def test_apple_integer_width_change_fails(self):
        self.apple["fixture.action"] = {"zh-Hans": "%lld 项", "en": "%d items"}
        self.assertIssue(self.report(), "format_arguments", "en")

    def test_android_argument_order_change_fails(self):
        self.android["fixture_action"] = {"zh-Hans": "%1$s · %2$d 项", "en": "%2$d items by %1$s"}
        self.assertIssue(self.report(), "format_arguments", "en")

    def test_escaped_percent_does_not_consume_argument(self):
        self.apple["fixture.action"] = {"zh-Hans": "%@ · 50%%", "en": "%@ · 50%%"}
        self.assertEqual(self.report()["status"], "PASS")

    def test_chinese_in_english_fails_for_both_platforms(self):
        self.apple["fixture.action"]["en"] = "Save 保存"
        self.android["fixture_action"]["en"] = "Save 保存"
        report = self.report()
        self.assertIssue(report, "chinese_in_english", "en")
        self.assertEqual(sum(item["type"] == "chinese_in_english" for item in report["issues"]), 2)

    def test_english_in_chinese_fails_for_both_platforms(self):
        self.apple["fixture.action"]["zh-Hans"] = "打开 Settings"
        self.android["fixture_action"]["zh-Hans"] = "Pending"
        report = self.report()
        self.assertIssue(report, "english_in_chinese", "zh-Hans")
        self.assertEqual(sum(item["type"] == "english_in_chinese" for item in report["issues"]), 2)

    def test_unlisted_uppercase_is_not_an_exception(self):
        self.apple["fixture.action"]["zh-Hans"] = "连接 VPN"
        self.assertIssue(self.report(), "english_in_chinese", "zh-Hans")

    def test_exact_brand_currency_and_filename_extension_pass(self):
        self.apple["fixture.action"]["zh-Hans"] = "Together-设备.json · CNY / USD"
        self.assertEqual(self.report()["status"], "PASS")

    def test_brand_substrings_do_not_bypass_gate(self):
        self.apple["fixture.action"]["zh-Hans"] = "Togetherly"
        self.assertIssue(self.report(), "english_in_chinese", "zh-Hans")

    def test_extension_word_without_dot_is_english(self):
        self.apple["fixture.action"]["zh-Hans"] = "打开 app"
        self.assertIssue(self.report(), "english_in_chinese", "zh-Hans")

    def test_missing_static_resource_fails(self):
        self.write()
        (self.root / gate.APPLE_CATALOGS[0]).unlink()
        self.assertIssue(gate.audit(self.root), "missing_or_invalid_resource")

    def test_definite_defensive_filler_fails(self):
        self.apple["fixture.action"] = {"zh-Hans": "请放心，已经保存。", "en": "Rest assured, it’s saved."}
        self.assertIssue(self.report(), "defensive_filler")

    def test_limitation_boilerplate_warns_without_disabling_gate(self):
        self.apple["fixture.action"]["zh-Hans"] = "现有数据已保留，请重试。"
        report = self.report()
        self.assertEqual(report["status"], "WARN")
        self.assertEqual(report["errors"], 0)
        self.assertTrue(any(item["type"] == "defensive_boilerplate" for item in report["issues"]))

    def test_real_permission_and_identity_recovery_are_not_filler(self):
        self.apple["fixture.action"] = {
            "zh-Hans": "设备密钥不可用，请恢复原身份文件后重试。",
            "en": "Device key unavailable. Restore the original identity file and retry."}
        self.android["fixture_action"] = {
            "zh-Hans": "请在系统设置中允许麦克风权限。",
            "en": "Allow microphone access in system settings."}
        self.assertEqual(self.report()["status"], "PASS")

    def test_cli_writes_complete_json_and_failure_exit_code(self):
        self.apple["fixture.action"]["zh-Hans"] = "打开 Settings"
        self.write()
        with contextlib.redirect_stdout(io.StringIO()):
            code = gate.main(["--root", str(self.root), "--json", "result.json"])
        self.assertEqual(code, 1)
        report = json.loads((self.root / "result.json").read_text())
        self.assertIssue(report, "english_in_chinese", "zh-Hans")
        self.assertTrue({"path", "key", "lang", "severity"}.issubset(report["issues"][0]))

    def test_scanner_never_visits_private_or_generated_data(self):
        self.write()
        private = self.root / "qa/results/private-user-data.json"
        private.parent.mkdir(parents=True)
        private.write_text("not JSON; PRIVATE TASK TITLE")
        self.assertEqual(gate.audit(self.root)["status"], "PASS")


if __name__ == "__main__":
    unittest.main(verbosity=2)
