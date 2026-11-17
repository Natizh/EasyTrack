#!/usr/bin/env python3
"""Rebuild the small, entirely fictional XLSX example without third-party packages."""

from pathlib import Path
from xml.sax.saxutils import escape
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "docs/examples/EasyTrack-example-import.xlsx"
ROWS = [
    ["Source ID", "Date", "Type", "Description", "Amount (EUR)", "Category"],
    ["example-expense-001", "2026-01-08", "Expense", "Cedar Cafe", 24.90, "Food & drink"],
    ["example-income-001", "2026-01-09", "Income", "Bluebird Studio", 2450.00, "Income"],
    ["example-pac-001", "2026-01-12", "PAC investment", "Northstar Index", 150.00, "Investments"],
]


def cell(column: int, row: int, value: str | float) -> str:
    ref = f"{chr(65 + column)}{row}"
    if isinstance(value, (int, float)):
        return f'<c r="{ref}"><v>{value:.2f}</v></c>'
    return f'<c r="{ref}" t="inlineStr"><is><t>{escape(value)}</t></is></c>'


def write_archive(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = "".join(
        f'<row r="{index}">{"".join(cell(column, index, value) for column, value in enumerate(row))}</row>'
        for index, row in enumerate(ROWS, 1)
    )
    worksheet = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" '
        'activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
        '<cols><col min="1" max="1" width="24" customWidth="1"/>'
        '<col min="2" max="3" width="18" customWidth="1"/>'
        '<col min="4" max="4" width="24" customWidth="1"/>'
        '<col min="5" max="6" width="20" customWidth="1"/></cols>'
        f'<sheetData>{rows}</sheetData><autoFilter ref="A1:F4"/></worksheet>'
    )
    parts = {
        "[Content_Types].xml": (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '</Types>'
        ),
        "_rels/.rels": (
            '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
            'Target="xl/workbook.xml"/></Relationships>'
        ),
        "xl/workbook.xml": (
            '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="Movements" sheetId="1" r:id="rId1"/></sheets></workbook>'
        ),
        "xl/_rels/workbook.xml.rels": (
            '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
            'Target="worksheets/sheet1.xml"/></Relationships>'
        ),
        "xl/worksheets/sheet1.xml": worksheet,
    }
    with ZipFile(path, "w", ZIP_DEFLATED) as archive:
        for name, content in parts.items():
            info = ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            archive.writestr(info, content)


if __name__ == "__main__":
    write_archive(OUTPUT)
    print(OUTPUT)
