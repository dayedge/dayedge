#!/usr/bin/env python3
"""Validate module-owned native localization resources without Xcode."""
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Packages/DayEdge/Sources"
ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.S)
SPEC = re.compile(r'%(?:(\d+)\$)?(@|lld|ld|d|f|g)')
errors = []


def signature(text):
    """Argument slots/types; reordered placeholders are intentionally allowed."""
    result = {}
    for offset, match in enumerate(SPEC.finditer(text.replace("%%", "")), 1):
        slot = int(match[1]) if match[1] else offset
        kind = match[2]
        if slot in result and result[slot] != kind:
            errors.append(f"Conflicting argument types: {text}")
        result[slot] = kind
    return result


def load(folder):
    table = {}
    path = folder / "Localizable.strings"
    if path.exists():
        source = re.sub(r'/\*.*?\*/', '', path.read_text(), flags=re.S)
        for match in ENTRY.finditer(source):
            key, value = [json.loads('"' + text + '"') for text in match.groups()]
            if key in table:
                errors.append(f"Duplicate key {key}: {path}")
            table[key] = signature(value)
        if ENTRY.sub('', source).strip():
            errors.append(f"Invalid strings syntax: {path}")
    path = folder / "Localizable.stringsdict"
    if path.exists():
        for key, rule in plistlib.loads(path.read_bytes()).items():
            count = rule.get("count", {})
            if (rule.get("NSStringLocalizedFormatKey") != "%#@count@"
                    or count.get("NSStringFormatSpecTypeKey") != "NSStringPluralRuleType"
                    or count.get("NSStringFormatValueTypeKey") != "lld"
                    or "other" not in count):
                errors.append(f"Invalid plural rule {key}: {path}")
            slots = {1: "lld"}
            for category, value in count.items():
                if category.startswith("NSString"):
                    continue
                for slot, kind in signature(value).items():
                    if slot in slots and slots[slot] != kind:
                        errors.append(f"Plural argument mismatch {key}/{category}: {path}")
                    slots[slot] = kind
            table[key] = slots
    return table


for module in sorted(SOURCES.iterdir()):
    resources = module / "Localization"
    if not resources.exists():
        continue
    english = load(resources / "en.lproj")
    for source in module.rglob("*.swift"):
        for key in re.findall(r'L10n\.tr\(\s*"([^"\n]+)"', source.read_text()):
            if key not in english:
                errors.append(f"Missing English key {key}: {source.relative_to(ROOT)}")
    for folder in resources.glob("*.lproj"):
        if folder.name == "en.lproj":
            continue
        translated = load(folder)
        for key in english.keys() - translated.keys():
            errors.append(f"Missing translation {key}: {folder.relative_to(ROOT)}")
        for key in translated.keys() - english.keys():
            errors.append(f"Unknown translation {key}: {folder.relative_to(ROOT)}")
        for key in english.keys() & translated.keys():
            if english[key] != translated[key]:
                errors.append(f"Placeholder mismatch {key}: {folder.relative_to(ROOT)}")

info = plistlib.loads((ROOT / "App/Info.plist").read_bytes())
for language in info.get("CFBundleLocalizations", []):
    path = ROOT / "App" / f"{language}.lproj" / "InfoPlist.strings"
    entries = dict((json.loads('"' + a + '"'), json.loads('"' + b + '"')) for a, b in ENTRY.findall(path.read_text()))
    for key in info:
        if key.startswith("NS") and key.endswith("UsageDescription") and key not in entries:
            errors.append(f"Missing permission description {key}: {path}")
    for module in SOURCES.iterdir():
        if (module / "Localization").exists() and not (module / "Localization" / f"{language}.lproj").exists():
            errors.append(f"Advertised language {language} missing in {module.name}")

if errors:
    raise SystemExit("\n".join(errors))
print("Localization resources: keys, plural rules, placeholders and app language declarations are valid.")
