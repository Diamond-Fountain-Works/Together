#!/usr/bin/env python3
"""Bilingual static-resource gate; complements, never replaces, the copy audits.

Only the four named product resource files and their two review indexes are
opened. No stores, preferences, logs, media, user text or test fixtures are read.
The test suite injects an isolated root containing synthetic resource files.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APPLE_CATALOGS = (
    Path("packages/together-core-swift/Sources/TogetherCore/Resources/UI.xcstrings"),
    Path("apps/apple/macOS/Sources/TogetherApp/Resources/InfoPlist.xcstrings"),
)
ANDROID_RESOURCES = {
    "en": Path("apps/android/app/src/main/res/values/strings.xml"),
    "zh-Hans": Path("apps/android/app/src/main/res/values-zh-rCN/strings.xml"),
}
APPLE_REVIEW = Path("qa/ui_copy_review.json")
ANDROID_REVIEW = Path("qa/android_copy_review.json")
LANGUAGES = ("en", "zh-Hans")
# Exact ISO 4217 identifiers supported by FinanceCurrencies.json. A word is not
# exempt merely because it is uppercase or resembles an identifier. Adding a
# supported currency requires an explicit change here and its reviewed resource.
ISO_CURRENCY_CODES = frozenset("""
AED AFN ALL AMD AOA ARS AUD AWG AZN BAM BBD BDT BHD BIF BMD BND BOB BOV
BRL BSD BTN BWP BYN BZD CAD CDF CHE CHF CHW CLF CLP CNY COP COU CRC CUP
CVE CZK DJF DKK DOP DZD EGP ERN ETB EUR FJD FKP GBP GEL GHS GIP GMD GNF
GTQ GYD HKD HNL HTG HUF IDR ILS INR IQD IRR ISK JMD JOD JPY KES KGS KHR
KMF KPW KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK MNT
MOP MRU MUR MVR MWK MXN MXV MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN
PGK PHP PKR PLN PYG QAR RON RSD RUB RWF SAR SBD SCR SDG SEK SGD SHP SLE
SOS SRD SSP STN SVC SYP SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX
USD USN UYI UYU UYW UZS VED VES VND VUV WST XAD XAF XCD XCG XOF XPF YER
ZAR ZMW ZWG
""".split())
BRANDS = frozenset({"Together"})
FILE_EXTENSIONS = frozenset({
    "json", "png", "jpg", "jpeg", "heic", "m4a", "aac", "wav", "mp3",
    "mp4", "m4v", "pdf", "txt", "csv", "app", "dmg", "apk", "zip",
})
HAN = re.compile(r"[\u3400-\u9fff\uf900-\ufaff\U00020000-\U000323af]")
LATIN_WORD = re.compile(r"[A-Za-z]+(?:['’][A-Za-z]+)*")
# Foundation printf and java.util.Formatter conversions used by static product
# resources. Positional indexes, integer widths and argument order are retained.
PRINTF = re.compile(
    r"%(?:(?P<position>[1-9][0-9]*)\$)?(?P<flags>[-+#0 ,(<]*)"
    r"(?P<width>[0-9]+|\*)?(?:\.(?P<precision>[0-9]+|\*))?"
    r"(?P<length>hh|ll|[hlLqzjt])?(?P<conversion>[@diuoxXfFeEgGaAcCsSpbn%])"
)
# Definite reassurance/filler is an error. Longer limitation boilerplate is a
# warning for contextual review, not a ban on real consent or recovery guidance.
DEFENSIVE_ERRORS = re.compile(
    r"请放心|无需担心|敬请放心|精心为你打造|留一点空间给彼此|"
    r"\b(?:rest assured|do not worry|don’t worry|don't worry|"
    r"for your peace of mind|we['’]ve got you covered)\b", re.IGNORECASE
)
DEFENSIVE_WARNINGS = re.compile(
    r"现有数据已保留|已保留现有数据|本地数据仍可使用|不会生成替代身份|"
    r"不保证|无法保证|不能保证|不承诺|"
    r"\b(?:cannot guarantee|can’t guarantee|can't guarantee|not a guarantee|"
    r"does not mean|doesn’t mean|doesn't mean|no replacement identity was generated)\b",
    re.IGNORECASE,
)


def sha256(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def printf_signature(text):
    """Return ordered (argument index, precise conversion type) requirements."""
    result = []
    implicit = 1
    for match in PRINTF.finditer(text):
        conversion = match.group("conversion")
        if conversion in {"%", "n"}:
            continue
        for field in ("width", "precision"):
            if match.group(field) == "*":
                result.append((implicit, "int:*"))
                implicit += 1
        position = match.group("position")
        index = int(position) if position else implicit
        if not position:
            implicit += 1
        result.append((index, (match.group("length") or "") + conversion))
    return result


def chinese_latin_leaks(text):
    """Find ordinary English without exempting whole lines, keys or acronyms."""
    without_parameters = PRINTF.sub("", text)
    leaks = []
    for match in LATIN_WORD.finditer(without_parameters):
        word = match.group()
        # An extension is exempt only after a literal dot. "Open app" fails.
        extension = (match.start() > 0 and
                     without_parameters[match.start() - 1] == "." and
                     word.lower() in FILE_EXTENSIONS)
        if word not in BRANDS and word not in ISO_CURRENCY_CODES and not extension:
            leaks.append(word)
    return leaks


def audit(root=ROOT):
    root = Path(root)
    issues = []
    counts = {"appleKeys": 0, "androidKeys": 0, "localizedValues": 0}

    def issue(path, key, lang, kind, severity, suggestion):
        issues.append({"path": str(path), "key": key, "lang": lang,
                       "type": kind, "severity": severity,
                       "suggestion": suggestion})

    def read_json(path):
        try:
            return json.loads((root / path).read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            issue(path, "resource", "all", "missing_or_invalid_resource", "Error",
                  "Restore the static resource file: " + str(error))
            return {}

    apple_review = read_json(APPLE_REVIEW).get("entries", {})
    android_review = read_json(ANDROID_REVIEW)

    def check_text(path, key, lang, text, reviewed_hash):
        counts["localizedValues"] += 1
        if not text.strip():
            issue(path, key, lang, "empty_translation", "Error",
                  "Provide a complete translation.")
        if reviewed_hash != sha256(text):
            issue(path, key, lang, "changed_since_review", "Error",
                  "Review this exact language value and update its SHA-256.")
        if lang == "en" and HAN.search(text):
            issue(path, key, lang, "chinese_in_english", "Error",
                  "Translate the Chinese text into natural English.")
        if lang == "zh-Hans":
            leaks = chinese_latin_leaks(text)
            if leaks:
                issue(path, key, lang, "english_in_chinese", "Error",
                      "Translate ordinary English words: " + ", ".join(dict.fromkeys(leaks)))
        if DEFENSIVE_ERRORS.search(text):
            issue(path, key, lang, "defensive_filler", "Error",
                  "Remove reassurance or decorative filler; state the action or result.")
        elif DEFENSIVE_WARNINGS.search(text):
            issue(path, key, lang, "defensive_boilerplate", "Warning",
                  "Review this limitation/reassurance in context; keep necessary consent and recovery.")

    def compare_formats(path, key, texts):
        if not all(lang in texts for lang in LANGUAGES):
            return
        expected = printf_signature(texts["zh-Hans"])
        actual = printf_signature(texts["en"])
        if actual != expected:
            issue(path, key, "en", "format_arguments", "Error",
                  f"Match Chinese printf argument types and order: {expected}; found {actual}.")

    apple_keys = set()
    for path in APPLE_CATALOGS:
        entries = read_json(path).get("strings", {})
        if not isinstance(entries, dict):
            issue(path, "strings", "all", "invalid_catalog", "Error",
                  "Catalog strings must be an object.")
            continue
        for key, entry in entries.items():
            counts["appleKeys"] += 1
            if key in apple_keys:
                issue(path, key, "all", "duplicate_catalog_key", "Error",
                      "Give each product key a single owning catalog.")
            apple_keys.add(key)
            translations = entry.get("localizations", {})
            hashes = apple_review.get(key, {}).get("translationSHA256", {})
            texts = {}
            for lang in LANGUAGES:
                localized = translations.get(lang, {})
                value = localized.get("stringUnit", {}).get("value")
                if not isinstance(value, str):
                    issue(path, key, lang, "missing_translation", "Error",
                          "Provide an explicit reviewed translation; system fallback is insufficient.")
                    continue
                texts[lang] = value
                check_text(path, key, lang, value, hashes.get(lang))
                if localized.get("stringUnit", {}).get("state") not in {"translated", "reviewed"}:
                    issue(path, key, lang, "incomplete_translation", "Error",
                          "Finish the language translation and mark its state translated.")
            compare_formats(path, key, texts)

    android = {}
    for lang, path in ANDROID_RESOURCES.items():
        android[lang] = {}
        try:
            document = ET.parse(root / path).getroot()
        except (OSError, ET.ParseError) as error:
            issue(path, "resource", lang, "missing_or_invalid_resource", "Error",
                  "Restore the Android string resource: " + str(error))
            continue
        for node in document:
            key = node.get("name", "")
            if node.tag != "string" or not key:
                issue(path, key or node.tag, lang, "unsupported_resource", "Error",
                      "Add explicit per-variant bilingual review support for this static resource.")
                continue
            if key in android[lang]:
                issue(path, key, lang, "duplicate_resource_key", "Error",
                      "Use one value for this language key.")
            value = "".join(node.itertext()).replace("\\'", "'")
            android[lang][key] = value
            review_key = path.parent.name + "/" + key
            check_text(path, key, lang, value,
                       android_review.get(review_key, {}).get("sha256"))
    keys = set().union(*(set(entries) for entries in android.values()))
    counts["androidKeys"] = len(keys)
    for key in sorted(keys):
        texts = {}
        for lang, entries in android.items():
            if key not in entries:
                issue(ANDROID_RESOURCES[lang], key, lang, "missing_translation", "Error",
                      "Keep English and Chinese Android resource keys aligned.")
            else:
                texts[lang] = entries[key]
        compare_formats(ANDROID_RESOURCES["en"], key, texts)

    issues.sort(key=lambda item: (item["path"], item["key"], item["lang"], item["type"]))
    errors = sum(item["severity"] == "Error" for item in issues)
    warnings = sum(item["severity"] == "Warning" for item in issues)
    return {"status": "FAIL" if errors else "WARN" if warnings else "PASS",
            "errors": errors, "warnings": warnings, **counts, "issues": issues,
            "scope": "Static Apple/Android EN/ZH resources and exact-text review hashes only; user data excluded."}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", type=Path, help="Write the complete machine-readable report.")
    parser.add_argument("--root", type=Path, default=ROOT,
                        help="Source root (also used by isolated synthetic tests).")
    args = parser.parse_args(argv)
    report = audit(args.root)
    if args.json:
        path = args.json if args.json.is_absolute() else args.root / args.json
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Localization QA: {report['status']} ({report['appleKeys']} Apple keys; "
          f"{report['androidKeys']} Android keys; {report['errors']} errors; {report['warnings']} warnings)")
    for item in report["issues"]:
        print(f"{item['severity']}: {item['path']}:{item['key']} [{item['lang']}] "
              f"{item['type']}: {item['suggestion']}")
    return 1 if report["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
