# Documentation

[EasyTrack](../../README.md) · [Documentation](README.md) · English / [Italiano](../it/README.md)

Start with [SideStore](SIDESTORE_INSTALL.md) to use EasyTrack on an iPhone, or [Xcode](XCODE_INSTALL.md) to build it. The app starts in Italian; switch to English in **Impostazioni → Lingua**.

## Install and use

| Guide | What you will find |
| --- | --- |
| [SideStore installation](SIDESTORE_INSTALL.md) | IPA availability, initial setup, refresh, updates and troubleshooting. |
| [Xcode installation](XCODE_INSTALL.md) | Requirements, simulator, physical device and unsigned IPA packaging. |
| [Shortcuts setup](SHORTCUTS_SETUP.md) | Source/account mapping, dynamic notification fields and format activation. |
| [Backup and restore](BACKUP_RESTORE.md) | Save your ledger, preview a restore, choose Replace or Merge. |
| [Excel import](EXCEL_IMPORT.md) | Working fictional workbook, column mapping and import preview. |
| [Transaction export](TRANSACTION_EXPORT.md) | CSV/XLSX choices, filters, columns and limits. |
| [App language](LOCALIZATION.md) | Language preference, formats and backup behavior. |

## Understand the behavior

| Reference | Scope |
| --- | --- |
| [Financial accounting](FINANCIAL_ACCOUNTING.md) | Income, gross/net Expenses, actual reimbursements, surplus and dates. |
| [Notification parser](NOTIFICATION_PARSER_DESIGN.md) | Local extraction, rule versions, duplicate checks and failure behavior. |
| [Recurring reconciliation](RECURRING_RECONCILIATION.md) | Expected dates, actual payments, matching, import conflicts and migration history. |
| [Legacy import mapping](IMPORT_MAPPING.md) | Historical seed-v1 contract; use the Excel guide for a new import. |

## Develop and maintain

| Guide | Scope |
| --- | --- |
| [Development](DEVELOPMENT.md) | Source map, tests, contribution workflow and bilingual documentation conventions. |
| [Showcase assets](SHOWCASE_ASSETS.md) | Regenerate screenshots from the running app with fictional data. |
| [Converter reference](../../Tools/HistoricalImportConverter/README.md) | Advanced workbook mappings and local conversion. |

The current app uses **SQLite schema 13**, **JSON backup format 15** and accepts **seed schemas 1–3**. Older schema numbers in migration sections describe history, not current defaults. A backup, an import seed and a transaction export serve different purposes; do not substitute one for another.
