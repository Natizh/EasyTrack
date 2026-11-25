# Local backup and restoration

[EasyTrack](../../README.md) · [Documentation](README.md) · English / [Italiano](../it/BACKUP_RESTORE.md)

EasyTrack keeps its ledger in a private SQLite database. **Settings → Export local data as JSON** writes a separate snapshot through Files. **Settings → Choose JSON backup to restore** validates a selected file and shows a preview before any live data changes. Backups can contain transaction notes, raw notification text, import rows and parser diagnostics; keep them private.

## Save a backup before updating

1. Open the installation containing your data and choose JSON export in Settings.
2. Save to a Files location outside EasyTrack’s own folder, optionally in iCloud Drive.
3. Verify that the file is present and readable. A CSV/XLSX transaction export is not a full backup.
4. Update without uninstalling, then check your ledger and accounts. Keep older copies until verification is complete.

## Current format and compatibility

The live database remains **SQLite schema 13**. New JSON backups are **format 15** and contain all 33 persistent tables, column names and values, a stable export ID, export time, source format when converted, and a SHA-256 content checksum. Financial amounts remain integer minor units. The format change does not alter the database table layout.

Formats **5–12 and 14** remain supported through their versioned conversions. Format 13 was never a released backup format and remains unsupported. The original format and checksum are verified before conversion. Format-14 files used the older rule that removed an expected refund from personal spending immediately. Conversion recalculates only the derived personal-cost field from the original expense and actual linked receipts, then creates a format-15 in-memory archive for preview and restore. It retains amounts, dates, accounts, kinds, links, source identity, and operation history. The same recalculation occurs when an existing schema-13 database is opened. Transaction revisions and operation records are not rewritten for a derived-value repair.

Current format-15 backups can contain an explicitly expected reimbursement above the original expense or a real linked receipt above the plan. The linked amount remains the full receipt; restore validates that the original expense's derived personal cost is capped at zero and any excess is surplus earnings within the existing Income receipt. No new table or backup field is required. Older format-14 backups keep their historical validation and upgrade path before current accounting is applied.

Older backups cannot reconstruct matching decisions or fields they never contained. Formats 2–4 are rejected as incomplete; a newer format requires a newer app. See the [financial accounting policy](FINANCIAL_ACCOUNTING.md) for the new Income, Net Expenses and cash Net definitions.

## Preview, Replace and Merge

The Files picker grants scoped access only while reading. A 100 MB limit prevents unbounded loading. EasyTrack checks version, original checksum, table and column shapes, app initialization marker, row types, readable model counts, cross-table links, foreign keys and SQLite integrity on a disposable database. Preview shows incoming and current counts and any Merge conflict. It does not modify the live ledger.

**Replace** installs the converted selected backup in one SQLite transaction after a separate confirmation. It verifies exact table equality, integrity, and foreign keys before commit, reopens the database, then verifies again. **Merge** inserts absent primary keys and accepts byte-for-byte identical existing rows; any different row with the same identity or secondary uniqueness conflict rejects the entire merge. It never overwrites local edits. A stale preview is rejected if the live database changed before confirmation. Repeating Replace or Merge does not create duplicate transactions.

A format-14 backup with an expected reimbursement may have a different derived personal-cost value after conversion. This is shown as format-15 accounting semantics during preview. The original receipt rows remain on their actual dates. For complete recovery, keep a recent external backup and verify the restored ledger before discarding older copies.

## Verification and limits

Synthetic tests cover old-format upgrades, format-15 round trips, Replace, Merge conflicts, idempotence, foreign keys, malformed rows, changed previews, rollback, linked reimbursements, and database reopen. No real financial data is used. Backups are unencrypted JSON and are not synchronized or deleted by the app. The selected Files provider controls storage. Physical iPhone Files providers, SideStore in-place updates, live Shortcuts delivery and VoiceOver remain device acceptance work in [Issue #8](https://github.com/Natizh/EasyTrack/issues/8).

The implementation uses Apple's [coordinated file access](https://developer.apple.com/documentation/foundation/nsfilecoordinator) and SQLite [transactions](https://www.sqlite.org/lang_transaction.html), [foreign-key checks](https://www.sqlite.org/pragma.html#pragma_foreign_key_check), and [integrity checks](https://www.sqlite.org/pragma.html#pragma_integrity_check).
