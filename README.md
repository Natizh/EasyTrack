# EasyTrack

EasyTrack is a local-first SwiftUI iPhone finance tracker using SQLite.

## Features

- Accounts, transactions, categories and explicit offline category suggestions.
- Reports, budgets, recurring expenses and expected reimbursements.
- Manual JSON backup/restore, CSV/XLSX exports and local receipt OCR.
- User-configured iOS Shortcuts notification automations with local parsing.
- Appearance customization and guided setup.

## Data privacy

The operational ledger stays in the app's local database. Backups are manually exported through Files and are not live synchronization. Keep financial records, imported dataset metrics, computer-specific diagnostics and credentials outside this repository. All committed test examples should be synthetic.

Notification automations require explicit user setup in Apple Shortcuts. Source labels identify configured accounts, while available notification fields must be passed using live Shortcuts variables rather than hardcoded example text.

## Source layout

- `EasyTrack/App`: app entry.
- `EasyTrack/UI`: SwiftUI screens.
- `EasyTrack/Shared`: models, parsers and analytics.
- `EasyTrack/Persistence`: SQLite schema and backup logic.
- `EasyTrack/Intake`: Shortcuts App Intent.
- `EasyTrack/Export`, `EasyTrack/Import`: data exchange.
- `Tests` and `EasyTrackUITests`: synthetic validation.

## Reference documentation

- [Backup and restore](docs/BACKUP_RESTORE.md)
- [Import mapping](docs/IMPORT_MAPPING.md)
- [Notification parser](docs/NOTIFICATION_PARSER_DESIGN.md)
- [Recurring reconciliation](docs/RECURRING_RECONCILIATION.md)
- [CSV/XLSX export](docs/TRANSACTION_EXPORT.md)
- [Product roadmap](https://github.com/Natizh/EasyTrack/issues/9)
