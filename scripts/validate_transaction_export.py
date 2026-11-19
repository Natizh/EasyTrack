#!/usr/bin/env python3
"""Independent stdlib checks for the fictional CSV/XLSX fixture (no app dependency)."""

import csv
import datetime as dt
from decimal import Decimal
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile


def require(condition, message):
    if not condition:
        raise AssertionError(message)


folder = Path(sys.argv[1])
with (folder / "fictional-transactions.csv").open(encoding="utf-8-sig", newline="") as stream:
    csv_rows = list(csv.DictReader(stream))
require(len(csv_rows) == 9, "CSV must have nine fictional transaction rows")
require(all("Demo" not in row["Description"] for row in csv_rows), "Demo rows leaked")
require(all("deleted" not in row["Description"] for row in csv_rows), "Deleted rows leaked")
coffee = next(row for row in csv_rows if "café" in row["Description"])
require(coffee["Description"] == 'Fictional café, "Blue"\nPier', "Unicode/CSV escaping changed text")
require(coffee["Note"].startswith("\t"), "Formula-like text was not neutralized")
require(coffee["Current amount"] == "12.34", "CSV cents changed")
require(coffee["Personal spending EUR"] == "10.00", "Personal share changed")
pac = next(row for row in csv_rows if row["Kind"] == "PAC investment")
require(pac["Current amount"] == "35.00", "Original PAC amount must stay positive")
require(pac["Signed directional EUR"] == "-35.00", "PAC direction changed")
history = next(row for row in csv_rows if row["Source movement ID"] == "fictional-source-8")
require((history["Current amount"], history["Current currency"],
         history["Imported amount"], history["Imported currency"], history["Imported EUR amount"])
        == ("8.75", "EUR", "320.00", "THB", "8.00"), "Imported and edited amounts conflated")
missing = next(row for row in csv_rows if row["Current currency"] == "CNY")
require(missing["Current EUR amount"] == "", "Missing EUR was invented")
require(missing["Current amount"] == "25.00", "Original currency amount changed")

ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def read_rows(archive, name):
    root = ET.fromstring(archive.read(name))
    rows = []
    for row in root.findall(".//m:sheetData/m:row", ns):
        values = {}
        for cell in row.findall("m:c", ns):
            name = "".join(char for char in cell.attrib["r"] if char.isalpha())
            inline = cell.find("m:is/m:t", ns)
            value = cell.find("m:v", ns)
            if inline is not None:
                values[name] = (inline.text or "", "text")
            elif value is not None:
                values[name] = (value.text or "", "number")
        rows.append(values)
    require(not root.findall(".//m:f", ns), "Unexpected workbook formula")
    return root, rows


with zipfile.ZipFile(folder / "fictional-transactions.xlsx") as archive:
    require(archive.testzip() is None, "ZIP CRC check failed")
    names = set(archive.namelist())
    require({"[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/styles.xml",
             "xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml"} <= names,
            "Required Open XML parts are missing")
    for name in names:
        if name.endswith((".xml", ".rels")):
            ET.fromstring(archive.read(name))
    root, movements = read_rows(archive, "xl/worksheets/sheet1.xml")
    require(len(movements) == 10, "XLSX movement row count differs from CSV")
    require(root.find("m:autoFilter", ns) is not None, "XLSX movement filter is missing")
    require(root.find("m:sheetViews/m:sheetView/m:pane", ns).attrib.get("state") == "frozen",
            "XLSX header is not frozen")
    headers = {key: value for key, (value, _) in movements[0].items()}
    description_col = next(key for key, value in headers.items() if value == "Description")
    current_col = next(key for key, value in headers.items() if value == "Current amount")
    date_col = next(key for key, value in headers.items() if value == "Occurred at")
    source_col = next(key for key, value in headers.items() if value == "Source movement ID")
    note_col = next(key for key, value in headers.items() if value == "Note")
    xlsx_descriptions = [row[description_col][0] for row in movements[1:]]
    require(xlsx_descriptions == [row["Description"] for row in csv_rows], "CSV/XLSX selections differ")
    require(all(row[current_col][1] == "number" for row in movements[1:]), "Amount cells are text")
    require(all(row[date_col][1] == "number" for row in movements[1:]), "Date cells are text")
    source_row = next(row for row in movements[1:] if row.get(source_col, (None,))[0] == "fictional-source-8")
    require(Decimal(source_row[current_col][0]) == Decimal("8.75"), "XLSX edited amount differs")
    coffee_row = next(row for row in movements[1:] if "café" in row[description_col][0])
    require(coffee_row[note_col] == (" \t=2+2", "text"), "XLSX text was converted to a formula")
    serial = Decimal(coffee_row[date_col][0])
    local_time = dt.datetime(1899, 12, 30) + dt.timedelta(days=float(serial))
    require(local_time.date() == dt.date(2026, 10, 15) and local_time.hour == 12,
            "XLSX local date/time changed")

    _, summary = read_rows(archive, "xl/worksheets/sheet2.xml")
    require(summary[1]["B"] == ("9", "number"), "Summary count differs")
    expected = [Decimal("13.75"), Decimal("21.09"), Decimal("255.00"), Decimal("35.00")]
    actual = [Decimal(summary[index]["B"][0]) for index in range(2, 6)]
    require(actual == expected, f"Summary totals differ: {actual}")
    for heading in ("By category", "By account", "By month"):
        require(any(row.get("A", (None,))[0] == heading for row in summary), f"Missing {heading} grouping")
        section = next(index for index, row in enumerate(summary)
                       if row.get("A", (None,))[0] == heading)
        groups = []
        for row in summary[section + 2:]:
            if "A" not in row:
                break
            groups.append(row)
        require(groups, f"No {heading} data")
        require(sum(int(row["B"][0]) for row in groups) == 9, f"{heading} counts double-count")
        for column, expected_total in zip("CDEF", expected):
            actual_total = sum(Decimal(row[column][0]) for row in groups)
            require(actual_total == expected_total, f"{heading} {column} totals do not reconcile")

try:
    from openpyxl import load_workbook
except ImportError:
    print("CSV and XLSX passed independent Python csv/zipfile/XML checks (openpyxl unavailable)")
else:
    workbook = load_workbook(folder / "fictional-transactions.xlsx", data_only=True, read_only=False)
    require(workbook.sheetnames == ["Movimenti", "Riepilogo"], "Workbook sheet names changed")
    sheet = workbook["Movimenti"]
    require(sheet.freeze_panes == "A2", "Independent reader lost frozen header")
    require(sheet.auto_filter.ref is not None, "Independent reader lost autofilter")
    require(isinstance(sheet["F2"].value, (int, float)), "Independent reader sees amount as text")
    require(isinstance(sheet["A2"].value, dt.datetime), "Independent reader sees date as text")
    require("€" in sheet["H2"].number_format, "EUR cells lost their currency style")
    print("CSV and XLSX passed independent Python csv/zipfile/XML and openpyxl checks")
