# Importing an Excel history

[EasyTrack](../../README.md) · [Documentation](README.md) · English / [Italiano](../it/EXCEL_IMPORT.md)

EasyTrack's iPhone app imports a **SQLite seed**, not an `.xlsx` file. The local converter creates that seed from a mapped workbook:

```text
XLSX workbook → Python converter → SQLite seed → EasyTrack preview → Confirm import
```

The converter runs on your computer, uses only the Python 3 standard library, and never changes the workbook. Keep your real workbook, mapping, generated seed, and audit report outside the repository; they contain financial information.

## Try the working example

Download [EasyTrack-example-import.xlsx](../examples/EasyTrack-example-import.xlsx) and its [matching mapping](../examples/simple-import-mapping.json). The workbook contains one `Movements` sheet and three fictional rows: an expense, income, and PAC investment. The values are examples, not app defaults.

| Column | Required? | What to enter |
| --- | --- | --- |
| `Source ID` | Yes | A unique, permanent identifier for each movement. Keep it unchanged across exports and reimports. |
| `Date` | Yes | An Excel date or `YYYY-MM-DD`; the converter also accepts ISO date-time and `DD/MM/YYYY` text. |
| `Type` | Yes | `Expense`, `Income`, or `PAC investment` in this simple mapping. |
| `Description` | Yes | A non-empty merchant or description. |
| `Amount (EUR)` | Yes | A **positive amount in euros**, such as `24.90`, not cents. Type sets the direction. |
| `Category` | No | A label you can review or change in EasyTrack. |

The example mapping sets every row's currency to EUR and interprets dates in `Europe/Rome`. Its `Amount (EUR)` value `24.90` becomes **2,490 integer cents** in the seed. Do not enter `2490` to mean €24.90. Keep IDs stable when correcting an existing row; a changed row with the same ID requires an explicit decision in EasyTrack rather than silently replacing a local edit.

From the repository root, run:

```sh
python3 Tools/HistoricalImportConverter/convert_xlsx.py \
  --input docs/examples/EasyTrack-example-import.xlsx \
  --mapping docs/examples/simple-import-mapping.json \
  --output /path/you/control/example-seed.sqlite
```

Replace `/path/you/control/` with an existing private folder. The command writes `example-seed.sqlite` and `example-seed-import-audit.txt` alongside it. It refuses to overwrite an existing output unless you deliberately pass `--replace-output`. Inspect the printed counts and the audit report; fix any `UNREPRESENTABLE_ROW`, duplicate ID, or other warning before importing. The example itself converts to **3 movements and 0 warnings**.

Move the SQLite seed into a location visible in the iPhone **Files** picker (for example, a private Files location). In EasyTrack, open **Settings → Historical import → Choose SQLite seed**. Review counts, changed rows, possible duplicates, missing account labels, and any recurring overlaps. Make each required decision, then tap **Import 3 movements**. Nothing enters the live ledger until confirmation. Selecting the same unchanged seed again is a no-op; missing rows in a later seed are not silently deleted.

The one-sheet example has no account master list, so its rows have no account assignment. You can assign managed accounts in EasyTrack after import. For a real history, add an `Accounts` worksheet and account mapping when account links matter.

## Adapt a real workbook

Copy the [full mapping example](../../Tools/HistoricalImportConverter/mapping.example.json) to a private file and change its sheet names, header names, and optional fields to match your workbook. Each configured worksheet must exist. The full mapping illustrates optional `Accounts`, `Trips`, and `Recurring` sheets; they are **not required** by the simple example. A mapped field marked `required` needs both a column header and a value in each imported row. An unmapped extra column is preserved in the source row audit but does not become an app field.

The full converter mapping recognizes seven movement types: expense, income, PAC investment, advance for others, reimbursement, deposit, and deposit refund. Its `values` table maps workbook labels to the exact kinds EasyTrack understands; edit the left-hand labels for your workbook, leaving the target kinds intact. Never map an unfamiliar type to expense just to make conversion pass.

For advanced mappings, supported currencies are EUR, USD, GBP, CNY, JPY, CHF, CAD, AUD, THB, and KWD. The converter accepts Excel serial dates using the declared `1900` or `1904` date system, ISO date or date-time text, and `DD/MM/YYYY` with an optional time. Naive dates use the sheet's declared `source_timezone`; offset-aware timestamps are converted to the app's Europe/Rome wall-time format. Monetary columns mapped as `minor` still take **normal currency units** from Excel. The converter applies the currency's precision: JPY has zero decimal places, KWD three, and the others two. For foreign-currency movements, supply a trustworthy EUR value if you want them included in EUR summaries; EasyTrack does not invent a historical conversion.

The converter currently writes **seed schema v3**. EasyTrack accepts seed schemas **v1, v2, and v3**; [the older mapping notes](IMPORT_MAPPING.md) describe a specific v1 source and are retained for compatibility. The [converter reference](../../Tools/HistoricalImportConverter/README.md) covers private mappings, audit files, date handling, and source provenance in more detail.
