#!/usr/bin/env python3
import hashlib
import json
import sqlite3
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

sys.path.insert(0, str(Path(__file__).parent))
from convert_xlsx import ConversionError, convert


def letters(index: int) -> str:
    result = ""
    while index:
        index, remainder = divmod(index - 1, 26)
        result = chr(65 + remainder) + result
    return result


def worksheet(rows):
    xml_rows = []
    for row_number, row in enumerate(rows, 1):
        cells = []
        for column, value in enumerate(row, 1):
            if value is None:
                continue
            reference = f"{letters(column)}{row_number}"
            if isinstance(value, tuple):
                formula, cached = value
                cells.append(f'<c r="{reference}"><f>{escape(formula)}</f><v>{cached}</v></c>')
            elif isinstance(value, (int, float)):
                cells.append(f'<c r="{reference}"><v>{value}</v></c>')
            else:
                cells.append(f'<c r="{reference}" t="inlineStr"><is><t>{escape(str(value))}</t></is></c>')
        xml_rows.append(f'<row r="{row_number}">{"".join(cells)}</row>')
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            f'<sheetData>{"".join(xml_rows)}</sheetData></worksheet>')


def workbook(path: Path):
    movement_headers = ["Stable ID", "Source ID", "Date", "Currency", "Amount", "EUR value",
                        "EUR source", "EUR rate", "Rate date", "Rate provider", "Description", "Type",
                        "Category", "Subcategory", "Account", "Account currency", "Account amount",
                        "Trip ID", "Paid by", "Affects my accounts", "Personal EUR", "Recoverable EUR", "Note"]
    movements = [movement_headers]
    movements += [
        ["m-eur", "src-eur", "2026-01-10", "EUR", ("1+2", "3.50"), None, None, None, None, None,
         "Synthetic groceries", "Expense", "Unknown synthetic", None, "EUR account", "EUR", "3.50", None, None, "yes", "3.50", "0", "formula amount"],
        ["m-usd", "src-usd", "2026-01-11", "USD", "12.34", "10.00", "confirmed", "0.8103727715", "2026-01-11", "Synthetic provider",
         "Synthetic income", "Income", "Synthetic", None, "USD account", "USD", "12.34", None, None, "yes", None, None, None],
        ["m-cny", "src-cny", "2026-01-12", "CNY", "88.80", None, None, None, None, None,
         "Synthetic PAC", "PAC", "Synthetic", None, "CNY account", "CNY", "88.80", None, None, "yes", None, None, None],
        ["m-gbp", "src-gbp", "2026-03-29T01:30:00", "GBP", "20.00", "23.00", "estimated", "1.15", "2026-03-28", "Synthetic provider",
         "Synthetic advance", "Advance", "Synthetic", None, "GBP account", "GBP", "20.00", "trip-1", "Synthetic person", "yes", "0", "23.00", "DST fixture"],
        ["m-jpy", "src-jpy", "2026-10-25T01:30:00", "JPY", "1250", "7.50", "historical", None, None, None,
         "Synthetic reimbursement", "Reimbursement", "Synthetic", None, "JPY account", "JPY", "1250", "trip-1", None, "yes", "-7.50", "0", None],
        ["m-deposit", "src-deposit", "2026-02-01", "EUR", "100", None, None, None, None, None,
         "Synthetic deposit", "Deposit", "Synthetic", None, "EUR account", "EUR", "100", None, None, "yes", "0", "100", None],
        ["m-deposit-refund", "src-deposit-refund", "2026-02-10", "EUR", "100", None, None, None, None, None,
         "Synthetic deposit refund", "Deposit refund", "Synthetic", None, "EUR account", "EUR", "100", None, None, "yes", "0", "0", None],
        ["m-eur-copy", "src-eur-copy", "2026-01-10", "EUR", "3.50", None, None, None, None, None,
         "Synthetic groceries", "Expense", "Unknown synthetic", None, "EUR account", "EUR", "3.50", None, None, "yes", "3.50", "0", None],
        ["m-eur", "src-repeat", "2026-01-13", "EUR", "4.00", None, None, None, None, None,
         "Repeated ID", "Expense", "Synthetic", None, "EUR account", "EUR", "4.00", None, None, "yes", "4.00", "0", None],
        ["missing-description", "src-missing", "2026-01-14", "EUR", "5.00", None, None, None, None, None,
         None, "Expense", "Synthetic", None, "EUR account", "EUR", "5.00", None, None, "yes", "5.00", "0", None]
    ]
    sheets = {
        "Movements": movements,
        "Accounts": [["Name", "Kind", "Currency", "Opening date", "Opening EUR", "Active", "Note"],
                     ["EUR account", "bank", "EUR", "2020-01-01", "100", "yes", "Synthetic"],
                     ["USD account", "bank", "USD", "2020-01-01", None, "yes", None]],
        "Trips": [["Trip ID", "Name", "Destination", "Start", "End", "Currency", "Note"],
                  ["trip-1", "Synthetic trip", "Test city", "2026-03-28", "2026-03-30", "GBP", "Synthetic"]],
        "Recurring": [["Rule ID", "Rule kind", "Name", "Currency", "Amount", "Frequency", "Nominal day", "Start", "End", "Account", "Active", "Note"],
                      ["rule-1", "investment", "Synthetic PAC", "CNY", "88.80", "monthly", 12, "2026-01-12", None, "CNY account", "yes", None]]
    }
    content_types = ['<?xml version="1.0" encoding="UTF-8"?>',
                     '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
                     '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
                     '<Default Extension="xml" ContentType="application/xml"/>',
                     '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>']
    workbook_sheets, relationships = [], []
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for index, (name, rows) in enumerate(sheets.items(), 1):
            archive.writestr(f"xl/worksheets/sheet{index}.xml", worksheet(rows))
            workbook_sheets.append(f'<sheet name="{escape(name)}" sheetId="{index}" r:id="rId{index}"/>')
            target = f"/xl/worksheets/sheet{index}.xml" if index == 1 else f"worksheets/sheet{index}.xml"
            relationships.append(f'<Relationship Id="rId{index}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="{target}"/>')
            content_types.append(f'<Override PartName="/xl/worksheets/sheet{index}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>')
        content_types.append("</Types>")
        archive.writestr("[Content_Types].xml", "".join(content_types))
        archive.writestr("_rels/.rels", '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        archive.writestr("xl/workbook.xml", '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>' + "".join(workbook_sheets) + "</sheets></workbook>")
        archive.writestr("xl/_rels/workbook.xml.rels", '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + "".join(relationships) + "</Relationships>")


class ConverterTests(unittest.TestCase):
    def test_synthetic_multicurrency_archive_is_deterministic_and_audited(self):
        with tempfile.TemporaryDirectory(prefix="EasyTrack-converter-") as directory:
            root = Path(directory)
            source = root / "synthetic.xlsx"
            output = root / "seed.sqlite"
            audit = root / "private-import-audit.txt"
            workbook(source)
            before = hashlib.sha256(source.read_bytes()).hexdigest()
            mapping = Path(__file__).with_name("mapping.example.json")
            result = convert(source, mapping, output, audit, False)
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), before)
            self.assertEqual(result["counts"]["movements"], 8)
            self.assertGreaterEqual(result["warnings"], 3)
            connection = sqlite3.connect(output)
            self.assertEqual(connection.execute("SELECT value FROM migration_meta WHERE key='schema_version'").fetchone()[0], "3")
            currencies = {row[0] for row in connection.execute("SELECT currency FROM movements")}
            self.assertTrue({"EUR", "USD", "CNY", "GBP", "JPY"}.issubset(currencies))
            self.assertEqual(connection.execute("SELECT amount_minor FROM movements WHERE id='m-jpy'").fetchone()[0], 1250)
            self.assertIsNone(connection.execute("SELECT eur_minor FROM movements WHERE id='m-cny'").fetchone()[0])
            self.assertEqual(connection.execute("SELECT occurred_at FROM movements WHERE id='m-gbp'").fetchone()[0],
                             "2026-03-29T01:30:00")
            raw = connection.execute("SELECT cell_values_json FROM source_rows WHERE source_row=2").fetchone()[0]
            self.assertIn('"formula":"1+2"', raw)
            codes = {row[0] for row in connection.execute("SELECT code FROM migration_warnings")}
            self.assertTrue({"CONFLICTING_STABLE_ID", "SUSPICIOUS_DUPLICATE", "UNREPRESENTABLE_ROW"}.issubset(codes))
            self.assertEqual(connection.execute("PRAGMA quick_check").fetchone()[0], "ok")
            connection.close()
            with self.assertRaises(ConversionError):
                convert(source, mapping, output, audit, False)


if __name__ == "__main__":
    unittest.main()
