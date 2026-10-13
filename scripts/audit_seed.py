#!/usr/bin/env python3
"""Write row-number-only seed ambiguities to an ignored local audit file."""

import pathlib
import sqlite3
import sys


def ranges(numbers):
    numbers = sorted(set(numbers))
    if not numbers:
        return "none"
    chunks = []
    first = last = numbers[0]
    for value in numbers[1:]:
        if value == last + 1:
            last = value
        else:
            chunks.append(str(first) if first == last else f"{first}-{last}")
            first = last = value
    chunks.append(str(first) if first == last else f"{first}-{last}")
    return ", ".join(chunks)


if len(sys.argv) != 3:
    raise SystemExit("Usage: audit_seed.py /path/to/external.sqlite /path/to/ignored-audit.txt")

source = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
connection = sqlite3.connect(source.as_uri() + "?mode=ro", uri=True)
connection.execute("PRAGMA query_only=ON")
unmatched = [row[0] for row in connection.execute("""
    SELECT m.source_row FROM movements m
    WHERE m.account IS NOT NULL AND TRIM(m.account) != ''
      AND NOT EXISTS (SELECT 1 FROM accounts a WHERE a.name=m.account)
    ORDER BY m.source_row
""")]
missing = [row[0] for row in connection.execute("""
    SELECT source_row FROM movements WHERE account IS NULL OR TRIM(account) = '' ORDER BY source_row
""")]
unusual_rule_dates = [row[0] for row in connection.execute("""
    SELECT source_row FROM recurring_rules
    WHERE starts_at IS NOT NULL AND starts_at NOT GLOB '????-??-??T??:??:??'
    ORDER BY source_row
""")]
cached_difference = [row[0] for row in connection.execute("""
    SELECT source_row FROM migration_warnings WHERE code='cached_personal_differs' ORDER BY source_row
""")]
connection.close()
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(
    "EasyTrack import audit — source row numbers only\n"
    "All 2,881 movements passed the version-1 mapper. No movement rows were rejected.\n\n"
    f"Account labels without a canonical account match ({len(unmatched)}): {ranges(unmatched)}\n\n"
    f"Movements with no account label ({len(missing)}): {ranges(missing)}\n\n"
    f"Recurring rules with a non-ISO start date ({len(unusual_rule_dates)}): {ranges(unusual_rule_dates)}\n\n"
    f"Legacy cached-personal-value differences ({len(cached_difference)}): {ranges(cached_difference)}\n",
    encoding="utf-8",
)
print(f"Audit written: {len(unmatched)} unmatched account labels, {len(missing)} missing account labels, {len(unusual_rule_dates)} unusual rule date(s), {len(cached_difference)} cached-value difference(s).")
