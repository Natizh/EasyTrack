#!/usr/bin/env python3
"""Create a one-movement, non-personal SQLite fixture for simulator picker tests."""

import pathlib
import sqlite3
import sys


if len(sys.argv) != 2:
    raise SystemExit("Usage: make_synthetic_seed.py /path/to/ignored/synthetic_seed.sqlite")

output = pathlib.Path(sys.argv[1])
if output.exists():
    raise SystemExit("Refusing to overwrite an existing file")
output.parent.mkdir(parents=True, exist_ok=True)
db = sqlite3.connect(output)
db.executescript("""
CREATE TABLE migration_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE accounts (name TEXT PRIMARY KEY, kind TEXT, currency TEXT, opening_at TEXT,
  opening_eur_minor INTEGER, is_active INTEGER, note TEXT, source_sheet TEXT NOT NULL,
  source_row INTEGER NOT NULL, cell_values_json TEXT NOT NULL);
CREATE TABLE trips (id TEXT PRIMARY KEY, name TEXT NOT NULL, destination TEXT, starts_at TEXT,
  ends_at TEXT, currency TEXT, note TEXT, source_sheet TEXT NOT NULL,
  source_row INTEGER NOT NULL, cell_values_json TEXT NOT NULL);
CREATE TABLE recurring_rules (id TEXT PRIMARY KEY, rule_kind TEXT NOT NULL, name TEXT NOT NULL,
  amount_minor INTEGER NOT NULL, currency TEXT NOT NULL, frequency TEXT, nominal_day INTEGER,
  starts_at TEXT, ends_at TEXT, account TEXT, is_active INTEGER, investment_kind TEXT,
  date_rule TEXT, initial_contribution_minor INTEGER, initial_contribution_at TEXT,
  note TEXT, source_sheet TEXT NOT NULL, source_row INTEGER NOT NULL, cell_values_json TEXT NOT NULL);
CREATE TABLE exchange_rates (source_row INTEGER PRIMARY KEY, date TEXT NOT NULL,
  currency TEXT NOT NULL, eur_rate TEXT NOT NULL, status TEXT, origin TEXT,
  source_key TEXT, cell_values_json TEXT NOT NULL);
CREATE TABLE source_rows (source_sheet TEXT NOT NULL, source_row INTEGER NOT NULL,
  cell_values_json TEXT NOT NULL, PRIMARY KEY(source_sheet, source_row));
CREATE TABLE migration_warnings (source_sheet TEXT NOT NULL, source_row INTEGER NOT NULL,
  code TEXT NOT NULL, detail TEXT, PRIMARY KEY(source_sheet, source_row, code));
CREATE TABLE movements (id TEXT PRIMARY KEY, occurred_at TEXT NOT NULL,
  amount_minor INTEGER NOT NULL, currency TEXT NOT NULL, eur_minor INTEGER NOT NULL,
  exchange_rate_eur TEXT NOT NULL, description TEXT NOT NULL, kind TEXT NOT NULL,
  category TEXT, subcategory TEXT, account TEXT, trip_id TEXT, paid_by TEXT,
  affects_my_accounts INTEGER, personal_expense_eur_minor INTEGER NOT NULL,
  recoverable_eur_minor INTEGER NOT NULL, needs_review INTEGER NOT NULL,
  review_reason TEXT, origin TEXT, entered_at TEXT, note TEXT, home_type TEXT,
  source_sheet TEXT NOT NULL, source_row INTEGER NOT NULL UNIQUE,
  source_technical_id TEXT, cached_personal_value TEXT,
  import_fingerprint TEXT NOT NULL UNIQUE);
""")
db.execute("INSERT INTO migration_meta VALUES ('schema_version', '1')")
db.execute("INSERT INTO accounts VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
           ("Synthetic Account", "Test", "EUR", None, 0, 1, None, "SYNTHETIC", 2, "[]"))
db.execute("INSERT INTO source_rows VALUES ('SYNTHETIC', 9, '[]')")
movement = {
    "id": "synthetic-9", "occurred_at": "2026-10-13T12:00:00", "amount_minor": 1234,
    "currency": "EUR", "eur_minor": 1234, "exchange_rate_eur": "1",
    "description": "Synthetic Grocery", "kind": "Spesa", "category": "Synthetic",
    "subcategory": None, "account": "Synthetic Account", "trip_id": None,
    "paid_by": "Synthetic person", "affects_my_accounts": 1,
    "personal_expense_eur_minor": 1234, "recoverable_eur_minor": 0,
    "needs_review": 0, "review_reason": None, "origin": "Synthetic fixture",
    "entered_at": None, "note": "Not personal data", "home_type": None,
    "source_sheet": "SYNTHETIC", "source_row": 9,
    "source_technical_id": "synthetic-9", "cached_personal_value": None,
    "import_fingerprint": "synthetic-fingerprint-9",
}
columns = ",".join(movement)
placeholders = ",".join("?" for _ in movement)
db.execute(f"INSERT INTO movements ({columns}) VALUES ({placeholders})", tuple(movement.values()))
db.commit()
db.close()
print("Synthetic fixture created: 1 movement, 1 account; no personal data")
