#!/usr/bin/env python3
"""Check native catalog coverage for literal UI and explicit localization keys."""

import json
from pathlib import Path
import plistlib
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "EasyTrack/Resources/Localizable.xcstrings"
SWIFT = list((ROOT / "EasyTrack").rglob("*.swift"))

UI_LITERAL = re.compile(
    r'\b(?:Text|Label|Button|Section|NavigationLink|Picker|Toggle|TextField|SecureField|'
    r'ContentUnavailableView|LabeledContent|navigationTitle|accessibilityLabel|'
    r'accessibilityHint|confirmationDialog|alert|filterChip|ChartEmptyState)\s*\(\s*'
    r'"((?:\\.|[^"\\])*)"'
)
EXPLICIT = re.compile(r'AppLanguage\.(?:localized|formatted)\(\s*"([^"\n]*)"')
PLACEHOLDER = re.compile(r'%(?:\d+\$)?(?:@|lld|ld|d|f)')


def main() -> int:
    catalog = json.loads(CATALOG.read_text())
    entries = catalog["strings"]
    problems = []
    if catalog.get("sourceLanguage") != "en":
        problems.append("Catalog source language must be English")
    for key, item in entries.items():
        locales = item.get("localizations", {})
        italian = locales.get("it", {}).get("stringUnit", {}).get("value")
        if italian is None:
            problems.append(f"Missing Italian translation: {key}")
            continue
        if len(PLACEHOLDER.findall(key)) != len(PLACEHOLDER.findall(italian)):
            problems.append(f"Placeholder count differs: {key}")
    for path in SWIFT:
        source = path.read_text()
        for key in EXPLICIT.findall(source):
            if key not in entries:
                problems.append(f"Explicit key missing ({path.relative_to(ROOT)}): {key}")
        if "/UI/" not in str(path):
            continue
        for key in UI_LITERAL.findall(source):
            if "\\(" not in key and key not in entries:
                problems.append(f"UI literal missing ({path.relative_to(ROOT)}): {key}")
    info = plistlib.loads((ROOT / "EasyTrack/Info.plist").read_bytes())
    info_catalog = json.loads((ROOT / "EasyTrack/Resources/InfoPlist.xcstrings").read_text())
    for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription",
                "NSSpeechRecognitionUsageDescription"):
        if not info.get(key) or not info_catalog["strings"].get(key, {}).get(
                "localizations", {}).get("it", {}).get("stringUnit", {}).get("value"):
            problems.append(f"Missing permission explanation: {key}")
    for problem in problems:
        print(problem, file=sys.stderr)
    print(f"Catalog entries: {len(entries)}; issues: {len(problems)}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
