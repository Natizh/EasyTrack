#!/usr/bin/env python3
"""Deterministic XLSX -> EasyTrack historical seed converter (stdlib only)."""

from __future__ import annotations

import argparse
import datetime as dt
import decimal
import hashlib
import json
import os
import re
import sqlite3
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any
from xml.etree import ElementTree as ET
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
      "p": "http://schemas.openxmlformats.org/package/2006/relationships"}
CURRENCIES = {"EUR": 2, "USD": 2, "GBP": 2, "CNY": 2, "JPY": 0,
              "CHF": 2, "CAD": 2, "AUD": 2, "THB": 2, "KWD": 3}
MOVEMENT_COLUMNS = [
    "id", "occurred_at", "amount_minor", "currency", "eur_minor", "exchange_rate_eur",
    "description", "kind", "category", "subcategory", "account", "trip_id", "paid_by",
    "affects_my_accounts", "personal_expense_eur_minor", "recoverable_eur_minor",
    "needs_review", "review_reason", "origin", "entered_at", "note", "home_type",
    "source_sheet", "source_row", "source_technical_id", "cached_personal_value",
    "import_fingerprint", "eur_value_source", "exchange_rate_date", "exchange_rate_provider",
    "account_amount_minor", "account_currency"
]
TABLE_COLUMNS = {
    "accounts": ["name", "kind", "currency", "opening_at", "opening_eur_minor", "is_active",
                 "note", "source_sheet", "source_row", "cell_values_json"],
    "trips": ["id", "name", "destination", "starts_at", "ends_at", "currency", "note",
              "source_sheet", "source_row", "cell_values_json"],
    "recurring_rules": ["id", "rule_kind", "name", "amount_minor", "currency", "frequency",
                        "nominal_day", "starts_at", "ends_at", "account", "is_active",
                        "investment_kind", "date_rule", "initial_contribution_minor",
                        "initial_contribution_at", "note", "source_sheet", "source_row",
                        "cell_values_json"],
    "exchange_rates": ["source_row", "date", "currency", "eur_rate", "status", "origin",
                       "source_key", "cell_values_json"]
}


class ConversionError(Exception):
    pass


@dataclass(frozen=True)
class Cell:
    coordinate: str
    value: Any
    formula: str | None
    cell_type: str | None
    style: int | None

    def original(self) -> dict[str, Any]:
        return {"coordinate": self.coordinate, "value": self.value, "formula": self.formula,
                "type": self.cell_type, "style": self.style}


def normalized(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value or "").strip()).casefold()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str)


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def column_index(reference: str) -> int:
    letters = "".join(ch for ch in reference if ch.isalpha()).upper()
    result = 0
    for letter in letters:
        result = result * 26 + ord(letter) - 64
    return result - 1


class XLSXWorkbook:
    def __init__(self, path: Path):
        self.path = path
        try:
            self.archive = zipfile.ZipFile(path)
            self.archive.testzip()
        except (OSError, zipfile.BadZipFile) as error:
            raise ConversionError(f"Input is not a readable XLSX archive: {error}") from error
        self.shared_strings = self._shared_strings()
        self.sheets = self._sheet_paths()

    def _xml(self, name: str) -> ET.Element:
        try:
            return ET.fromstring(self.archive.read(name))
        except (KeyError, ET.ParseError) as error:
            raise ConversionError(f"XLSX part is missing or invalid: {name}") from error

    def _shared_strings(self) -> list[str]:
        if "xl/sharedStrings.xml" not in self.archive.namelist():
            return []
        root = self._xml("xl/sharedStrings.xml")
        return ["".join(node.text or "" for node in item.findall(".//m:t", NS))
                for item in root.findall("m:si", NS)]

    def _sheet_paths(self) -> dict[str, str]:
        workbook = self._xml("xl/workbook.xml")
        relationships = self._xml("xl/_rels/workbook.xml.rels")
        targets = {node.attrib["Id"]: node.attrib["Target"] for node in relationships.findall("p:Relationship", NS)}
        result: dict[str, str] = {}
        for sheet in workbook.findall("m:sheets/m:sheet", NS):
            relation = sheet.attrib.get(f"{{{NS['r']}}}id")
            target = targets.get(relation or "")
            if target:
                normalized_target = target.lstrip("/")
                result[sheet.attrib["name"]] = (normalized_target if normalized_target.startswith("xl/") else
                    str(PurePosixPath("xl") / normalized_target)).replace("xl/xl/", "xl/")
        return result

    def rows(self, sheet_name: str) -> list[list[Cell | None]]:
        path = self.sheets.get(sheet_name)
        if not path:
            raise ConversionError(f"Mapped worksheet not found: {sheet_name}")
        root = self._xml(path)
        rows: list[list[Cell | None]] = []
        for row in root.findall("m:sheetData/m:row", NS):
            row_number = int(row.attrib.get("r", len(rows) + 1))
            while len(rows) < row_number - 1:
                rows.append([])
            cells: dict[int, Cell] = {}
            for node in row.findall("m:c", NS):
                ref = node.attrib.get("r", "")
                kind = node.attrib.get("t")
                style = int(node.attrib["s"]) if "s" in node.attrib else None
                formula_node = node.find("m:f", NS)
                value_node = node.find("m:v", NS)
                inline = node.find("m:is", NS)
                raw = value_node.text if value_node is not None else None
                if kind == "s" and raw is not None:
                    index = int(raw)
                    value: Any = self.shared_strings[index] if index < len(self.shared_strings) else None
                elif kind == "inlineStr" and inline is not None:
                    value = "".join(item.text or "" for item in inline.findall(".//m:t", NS))
                elif kind == "b" and raw is not None:
                    value = raw == "1"
                elif kind in {"str", "e"}:
                    value = raw
                elif raw is None:
                    value = None
                else:
                    try:
                        value = decimal.Decimal(raw)
                    except decimal.InvalidOperation:
                        value = raw
                cells[column_index(ref)] = Cell(ref, value,
                    formula_node.text if formula_node is not None else None, kind, style)
            width = max(cells.keys(), default=-1) + 1
            rows.append([cells.get(index) for index in range(width)])
        return rows


def excel_datetime(value: decimal.Decimal, date_system: str) -> dt.datetime:
    base = dt.datetime(1904, 1, 1) if date_system == "1904" else dt.datetime(1899, 12, 30)
    return base + dt.timedelta(days=float(value))


def decimal_value(value: Any) -> decimal.Decimal:
    if isinstance(value, bool):
        return decimal.Decimal(int(value))
    if isinstance(value, decimal.Decimal):
        return value
    text = str(value).strip().replace("\u00a0", "").replace(" ", "")
    if "," in text and "." in text:
        if text.rfind(",") > text.rfind("."):
            text = text.replace(".", "").replace(",", ".")
        else:
            text = text.replace(",", "")
    elif "," in text:
        text = text.replace(",", ".")
    try:
        return decimal.Decimal(text)
    except decimal.InvalidOperation as error:
        raise ConversionError(f"not a decimal: {value}") from error


def parse_datetime(value: Any, date_system: str, source_timezone: str) -> str:
    if isinstance(value, decimal.Decimal):
        parsed = excel_datetime(value, date_system)
    else:
        text = str(value).strip()
        parsed = None
        for pattern in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d", "%d/%m/%Y %H:%M:%S", "%d/%m/%Y"):
            try:
                parsed = dt.datetime.strptime(text, pattern)
                break
            except ValueError:
                pass
        if parsed is None:
            try:
                parsed = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
            except ValueError as error:
                raise ConversionError(f"not a supported date: {value}") from error
    try:
        source_zone = ZoneInfo(source_timezone)
        target_zone = ZoneInfo("Europe/Rome")
    except ZoneInfoNotFoundError as error:
        raise ConversionError(f"unknown timezone: {error}") from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=source_zone)
    return parsed.astimezone(target_zone).strftime("%Y-%m-%dT%H:%M:%S")


def convert_value(value: Any, specification: dict[str, Any], row: dict[str, Any],
                  date_system: str, source_timezone: str) -> Any:
    if value is None or str(value).strip() == "":
        return specification.get("default")
    kind = specification.get("type", "string")
    if kind == "string":
        result: Any = str(value).strip()
    elif kind == "currency":
        result = str(value).strip().upper()
        if result not in CURRENCIES:
            raise ConversionError(f"unsupported currency {result}")
    elif kind == "integer":
        result = int(decimal_value(value))
    elif kind == "decimal":
        result = format(decimal_value(value), "f")
    elif kind == "boolean":
        token = normalized(value)
        if token in {"1", "true", "yes", "y", "si", "sì"}:
            result = 1
        elif token in {"0", "false", "no", "n"}:
            result = 0
        else:
            raise ConversionError(f"not a boolean: {value}")
    elif kind == "datetime":
        result = parse_datetime(value, date_system, source_timezone)
    elif kind == "minor":
        currency_field = specification.get("currency_field", "currency")
        currency = str(row.get(currency_field) or specification.get("currency") or "EUR").upper()
        if currency not in CURRENCIES:
            raise ConversionError(f"minor amount has unsupported currency {currency}")
        scale = decimal.Decimal(10) ** CURRENCIES[currency]
        result = int((decimal_value(value) * scale).quantize(decimal.Decimal(1), rounding=decimal.ROUND_HALF_EVEN))
    else:
        raise ConversionError(f"unknown mapping type {kind}")
    values = specification.get("values")
    if values:
        key = normalized(result)
        normalized_values = {normalized(source): target for source, target in values.items()}
        if key not in normalized_values:
            raise ConversionError(f"unmapped value: {result}")
        result = normalized_values[key]
    return result


def create_schema(connection: sqlite3.Connection) -> None:
    connection.executescript("""
    PRAGMA journal_mode=DELETE;
    CREATE TABLE migration_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
    CREATE TABLE movements(
      id TEXT PRIMARY KEY,occurred_at TEXT,amount_minor INTEGER,currency TEXT,eur_minor INTEGER,
      exchange_rate_eur TEXT,description TEXT,kind TEXT,category TEXT,subcategory TEXT,account TEXT,
      trip_id TEXT,paid_by TEXT,affects_my_accounts INTEGER,personal_expense_eur_minor INTEGER,
      recoverable_eur_minor INTEGER,needs_review INTEGER,review_reason TEXT,origin TEXT,entered_at TEXT,
      note TEXT,home_type TEXT,source_sheet TEXT,source_row INTEGER,source_technical_id TEXT,
      cached_personal_value TEXT,import_fingerprint TEXT,eur_value_source TEXT,exchange_rate_date TEXT,
      exchange_rate_provider TEXT,account_amount_minor INTEGER,account_currency TEXT);
    CREATE TABLE accounts(name TEXT PRIMARY KEY,kind TEXT,currency TEXT,opening_at TEXT,
      opening_eur_minor INTEGER,is_active INTEGER,note TEXT,source_sheet TEXT,source_row INTEGER,
      cell_values_json TEXT);
    CREATE TABLE trips(id TEXT PRIMARY KEY,name TEXT,destination TEXT,starts_at TEXT,ends_at TEXT,
      currency TEXT,note TEXT,source_sheet TEXT,source_row INTEGER,cell_values_json TEXT);
    CREATE TABLE recurring_rules(id TEXT PRIMARY KEY,rule_kind TEXT,name TEXT,amount_minor INTEGER,
      currency TEXT,frequency TEXT,nominal_day INTEGER,starts_at TEXT,ends_at TEXT,account TEXT,
      is_active INTEGER,investment_kind TEXT,date_rule TEXT,initial_contribution_minor INTEGER,
      initial_contribution_at TEXT,note TEXT,source_sheet TEXT,source_row INTEGER,cell_values_json TEXT);
    CREATE TABLE exchange_rates(source_row INTEGER PRIMARY KEY,date TEXT,currency TEXT,eur_rate TEXT,
      status TEXT,origin TEXT,source_key TEXT,cell_values_json TEXT);
    CREATE TABLE source_rows(source_sheet TEXT,source_row INTEGER,cell_values_json TEXT,
      PRIMARY KEY(source_sheet,source_row));
    CREATE TABLE migration_warnings(source_sheet TEXT,source_row INTEGER,code TEXT,detail TEXT,
      PRIMARY KEY(source_sheet,source_row,code));
    CREATE TABLE reimbursement_reconciliations(
      link_id TEXT PRIMARY KEY,expense_source_id TEXT NOT NULL,expected_eur_minor INTEGER NOT NULL,
      receipt_source_id TEXT,received_eur_minor INTEGER NOT NULL,status TEXT NOT NULL,note TEXT);
    """)
    connection.execute("INSERT INTO migration_meta VALUES('schema_version','3')")


def locate_headers(rows: list[list[Cell | None]], entity: dict[str, Any]) -> tuple[int, dict[str, int]]:
    header_row = int(entity.get("header_row", 1)) - 1
    if not 0 <= header_row < len(rows):
        raise ConversionError("configured header row is outside the worksheet")
    headers = {normalized(cell.value): index for index, cell in enumerate(rows[header_row]) if cell and cell.value is not None}
    result: dict[str, int] = {}
    for field, raw_spec in entity.get("fields", {}).items():
        spec = {"header": raw_spec} if isinstance(raw_spec, str) else raw_spec
        candidates = [spec.get("header", field)] + list(spec.get("aliases", []))
        matches = [headers[normalized(candidate)] for candidate in candidates if normalized(candidate) in headers]
        if matches:
            result[field] = matches[0]
        elif spec.get("required") and "default" not in spec:
            raise ConversionError(f"required header for {field} was not found")
    return header_row, result


def mapped_rows(workbook: XLSXWorkbook, entity_name: str, entity: dict[str, Any],
                warnings: list[dict[str, Any]], diagnostics: dict[str, Any]) -> list[dict[str, Any]]:
    sheet = entity["sheet"]
    rows = workbook.rows(sheet)
    header_row, indexes = locate_headers(rows, entity)
    fields = entity.get("fields", {})
    output: list[dict[str, Any]] = []
    for offset, cells in enumerate(rows[header_row + 1:], start=header_row + 2):
        originals = {str(index + 1): cell.original() for index, cell in enumerate(cells) if cell is not None}
        if not originals or all(cell is None or cell.value in (None, "") for cell in cells):
            continue
        required_fields = [field for field, raw in fields.items()
                           if not isinstance(raw, str) and raw.get("required")]
        if required_fields and all(
            (indexes.get(field) is None or indexes[field] >= len(cells) or cells[indexes[field]] is None or
             cells[indexes[field]].value in (None, "")) for field in required_fields
        ):
            continue
        mapped = dict(entity.get("constants", {}))
        errors: list[str] = []
        for field, raw_spec in fields.items():
            spec = {"header": raw_spec} if isinstance(raw_spec, str) else dict(raw_spec)
            index = indexes.get(field)
            cell = cells[index] if index is not None and index < len(cells) else None
            if cell and cell.formula and cell.value is None:
                if spec.get("required"):
                    errors.append(f"{field}: formula has no cached value")
                value = None
            else:
                value = cell.value if cell else None
            try:
                mapped[field] = convert_value(value, spec, mapped, entity.get("date_system", "1900"),
                                              entity.get("source_timezone", "Europe/Rome"))
                if spec.get("required") and mapped[field] in (None, ""):
                    errors.append(f"{field}: required value is empty")
            except (ConversionError, ValueError, TypeError) as error:
                errors.append(f"{field}: {error}")
        stable = entity.get("stable_id")
        if stable and not mapped.get("id"):
            special = {"__source_sheet": sheet, "__source_row": offset}
            components = [str(special.get(field, mapped.get(field, ""))) for field in stable.get("fields", [])]
            if all(components):
                mapped["id"] = f"{stable.get('namespace', entity_name)}:{digest(components)}"
        raw_json = canonical_json({"sheet": sheet, "row": offset, "cells": originals})
        mapped.update(source_sheet=sheet, source_row=offset, cell_values_json=raw_json)
        if errors:
            detail = "; ".join(errors)
            warnings.append({"source_sheet": sheet, "source_row": offset,
                             "code": "UNREPRESENTABLE_ROW", "detail": detail})
            diagnostics["unrepresentable"].append({"entity": entity_name, "sheet": sheet,
                                                    "row": offset, "reasons": errors})
            continue
        output.append(mapped)
    return output


def insert_rows(connection: sqlite3.Connection, table: str, columns: list[str], rows: list[dict[str, Any]],
                warnings: list[dict[str, Any]], diagnostics: dict[str, Any]) -> None:
    seen: dict[str, str] = {}
    signatures: dict[str, str] = {}
    for row in rows:
        if table == "movements":
            source_id = str(row.get("id") or "")
            if not source_id:
                warnings.append({"source_sheet": row["source_sheet"], "source_row": row["source_row"],
                                 "code": "MISSING_STABLE_ID", "detail": "Movement was not imported."})
                continue
            fingerprint_fields = {key: row.get(key) for key in MOVEMENT_COLUMNS
                                  if key not in {"source_row", "import_fingerprint"}}
            fingerprint = digest(fingerprint_fields)
            if source_id in seen:
                code = "DUPLICATE_STABLE_ID" if seen[source_id] == fingerprint else "CONFLICTING_STABLE_ID"
                warnings.append({"source_sheet": row["source_sheet"], "source_row": row["source_row"],
                                 "code": code, "detail": "Repeated movement identity was not imported."})
                diagnostics["duplicates"].append({"id": source_id, "row": row["source_row"], "code": code})
                continue
            seen[source_id] = fingerprint
            row["import_fingerprint"] = fingerprint
            signature = digest([row.get("occurred_at"), row.get("kind"), row.get("amount_minor"),
                                row.get("currency"), normalized(row.get("description"))])
            if signature in signatures and signatures[signature] != source_id:
                warnings.append({"source_sheet": row["source_sheet"], "source_row": row["source_row"],
                                 "code": "SUSPICIOUS_DUPLICATE",
                                 "detail": "A different stable ID has the same date, kind, amount, currency, and description."})
                diagnostics["duplicates"].append({"id": source_id, "row": row["source_row"],
                                                  "code": "SUSPICIOUS_DUPLICATE"})
            signatures[signature] = source_id
            if row.get("currency") == "EUR" and row.get("eur_minor") is None:
                row["eur_minor"] = row.get("amount_minor")
                row["eur_value_source"] = row.get("eur_value_source") or "confirmed"
            row["account_amount_minor"] = row.get("account_amount_minor") or row.get("amount_minor")
            row["account_currency"] = row.get("account_currency") or row.get("currency")
            connection.execute("INSERT OR REPLACE INTO source_rows VALUES(?,?,?)",
                               (row["source_sheet"], row["source_row"], row["cell_values_json"]))
        values = [row.get(column) for column in columns]
        try:
            connection.execute(f"INSERT INTO {table}({','.join(columns)}) VALUES({','.join('?' for _ in columns)})", values)
        except sqlite3.IntegrityError as error:
            warnings.append({"source_sheet": row.get("source_sheet", ""), "source_row": row.get("source_row", 0),
                             "code": "IDENTITY_CONFLICT", "detail": str(error)})
            diagnostics["duplicates"].append({"entity": table, "row": row.get("source_row"), "error": str(error)})


def convert(input_path: Path, mapping_path: Path, output_path: Path, audit_path: Path, replace: bool) -> dict[str, Any]:
    if input_path.resolve() == output_path.resolve():
        raise ConversionError("Output must differ from the original workbook")
    if output_path.exists() and not replace:
        raise ConversionError("Output exists; pass --replace-output to replace only the generated SQLite file")
    mapping = json.loads(mapping_path.read_text(encoding="utf-8"))
    if mapping.get("mapping_version") != 1:
        raise ConversionError("mapping_version must be 1")
    workbook = XLSXWorkbook(input_path)
    diagnostics: dict[str, Any] = {"input_sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
                                   "mapping_sha256": hashlib.sha256(mapping_path.read_bytes()).hexdigest(),
                                   "sheets": sorted(workbook.sheets), "unrepresentable": [], "duplicates": [],
                                   "counts": {}}
    warnings: list[dict[str, Any]] = []
    temporary = output_path.with_name(output_path.name + ".tmp")
    if temporary.exists():
        temporary.unlink()
    try:
        connection = sqlite3.connect(temporary)
        create_schema(connection)
        entities = mapping.get("entities", {})
        for table in ["accounts", "trips", "recurring_rules", "exchange_rates", "movements"]:
            entity = entities.get(table)
            if not entity:
                diagnostics["counts"][table] = 0
                continue
            rows = mapped_rows(workbook, table, entity, warnings, diagnostics)
            columns = MOVEMENT_COLUMNS if table == "movements" else TABLE_COLUMNS[table]
            insert_rows(connection, table, columns, rows, warnings, diagnostics)
            diagnostics["counts"][table] = connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        for warning in warnings:
            connection.execute("INSERT OR REPLACE INTO migration_warnings VALUES(?,?,?,?)",
                               (warning["source_sheet"], warning["source_row"], warning["code"], warning.get("detail")))
        connection.commit()
        if connection.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise ConversionError("Generated SQLite failed quick_check")
        connection.close()
        if output_path.exists():
            output_path.unlink()
        os.replace(temporary, output_path)
    except Exception:
        if temporary.exists():
            temporary.unlink()
        raise
    diagnostics["warnings"] = len(warnings)
    audit_path.write_text(json.dumps(diagnostics, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    return diagnostics


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--mapping", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--audit", type=Path, help="Private JSON diagnostics; defaults to *-import-audit.txt")
    parser.add_argument("--replace-output", action="store_true")
    arguments = parser.parse_args()
    audit = arguments.audit or arguments.output.with_name(arguments.output.stem + "-import-audit.txt")
    try:
        result = convert(arguments.input, arguments.mapping, arguments.output, audit, arguments.replace_output)
    except (ConversionError, OSError, json.JSONDecodeError, sqlite3.Error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    print(canonical_json({"output": str(arguments.output), "audit": str(audit),
                          "counts": result["counts"], "warnings": result["warnings"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
