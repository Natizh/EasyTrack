# Local backup and restoration

EasyTrack stores its ledger in a private SQLite database and runs offline. **Settings → Export local data as JSON** writes a separate backup through the native Files exporter. **Settings → Choose JSON backup to restore** opens the native Files picker, validates a coordinated read, and shows a preview before the ledger changes. Backups contain raw notification text, transaction notes, historical source rows, and parser diagnostics. Keep them private.

## Format and compatibility

- SQLite remains schema **5**. New JSON backups are format **6**. A format-6 file contains a stable export ID and timestamp, database schema version, SHA-256 content checksum, and all 22 persistent schema-5 tables with their columns and values. The table list includes transactions and tombstones, accounts, categories, local and historical recurrence, occurrence links, notification events and attempts, parser source mappings, current rules and revisions, exact and semantic deduplication rows, operations, import provenance and reference tables, raw source rows, exchange rates, warnings, and database metadata.
- Format **5** JSON files from the previous export implementation are accepted. They did not contain exact and semantic deduplication rows, expected-occurrence links, or metadata. EasyTrack reconstructs duplicate keys from captured parser attempts and restores known metadata. The preview explicitly warns that expected-occurrence links cannot be recovered from a format-5 file. The current historical import does not create expected occurrences, but a file cannot prove that none existed.
- Formats **2–4** are rejected as incomplete for safe restoration. Formats newer than 6 are rejected until the app supports them. The local SQLite migration path from versions 2–4 to schema 5 remains separate from JSON compatibility.

## Preview and conflict policy

The picker grants scoped access only while the file is read. A 100 MB limit prevents unbounded loading. EasyTrack checks the version, required fields, checksum, columns, app initialization marker, row types and readable model counts, cross-table links, foreign keys, and SQLite integrity on a disposable database. The preview shows transaction, event, rule, occurrence, historical identity, and operation counts, plus the number of current transactions. It does not modify the live database.

**Replace** deletes all current schema-5 rows and installs the selected backup in one SQLite transaction. A separate destructive confirmation names the current and incoming transaction counts. The app checks foreign keys, SQLite integrity, and exact row equality before commit, then reopens the database and checks again before reporting success.

**Merge** adds records whose primary key is absent and skips rows that are byte-for-byte equal across all stored columns. A different row with the same primary key, or any secondary uniqueness or foreign-key conflict, rejects the entire merge. It never overwrites local edits. Merging backups from independent installations can conflict on default category names with different IDs; use Replace only after reviewing the preview and preserving a separate copy of the current ledger.

The live database is fingerprinted at preview time. If it changes before confirmation, restoration stops and requests a new preview. SQL failures roll back the whole transaction. Repeated Replace or Merge of the same format-6 backup creates no duplicate transactions. A successful message appears only after a reopened database passes integrity checks.

## Verification and limits

Synthetic tests cover format-6 export → Replace → reopen → export equality across all 22 tables; parser deduplication after restore; historical source IDs; recurring occurrences; format-5 conversion; repeat restore; successful add-only and conflicting Merges; malformed, incomplete, and unsupported files; unreadable UUID and numeric rows; a changed live ledger; and an injected mid-restore SQLite failure. These tests use temporary databases and fictional records only. A focused Demo-only XCUITest passed the native Files export, selection, preview, confirmation, restore, and relaunch flow in light and dark appearance on iOS 27.

Backups are unencrypted JSON. The app does not synchronize them or delete older exported files. The native Files provider controls where a selected file is stored. A format-5 conversion cannot recover data that its exporter omitted; for the most complete recovery, use a format-6 backup. Physical-device Files providers, app update behavior, and Shortcuts delivery still require iPhone testing.

The design uses Apple's [coordinated file access](https://developer.apple.com/documentation/foundation/nsfilecoordinator) for Files reads and SQLite's [transaction](https://www.sqlite.org/lang_transaction.html), [foreign-key](https://www.sqlite.org/pragma.html#pragma_foreign_key_check), and [integrity](https://www.sqlite.org/pragma.html#pragma_integrity_check) checks for restoration.
