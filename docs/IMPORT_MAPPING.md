# Historical seed mapping (source schema version 1)

This mapping was recorded before importing the seed. The external SQLite file remains outside this repository and is never bundled. The importer accepts only the inspected schema version (`migration_meta.schema_version = 1`) and validates all rows before changing the local database.

## Movements

| Source `movements` field | Local representation | Rule |
| --- | --- | --- |
| `id`, `import_fingerprint` | `imported_movements.source_id`, `source_fingerprint`; stable local transaction UUID | Unique historical identity, separate from notification fingerprints. Reimport of the same identity and fingerprint is a no-op; a changed fingerprint is a conflict, never a silent overwrite. |
| `source_sheet`, `source_row`, `source_technical_id` | provenance on the transaction | Preserved verbatim for spreadsheet traceability. |
| `occurred_at` | `occurred_at` plus original `source_occurred_at` | Parse source `yyyy-MM-dd'T'HH:mm:ss` wall time in Europe/Rome for the current Date-based UI; preserve the exact source text because it has no timezone. |
| `kind` | `transactions.kind` and `source_kind` | Exact seven-value mapping below. Any new value rejects the import with its source row number. |
| `amount_minor`, `currency` | original amount and ISO currency | Preserve integer minor units. Supported source currencies are EUR, CNY, and THB, each with two decimal places. |
| `eur_minor`, `exchange_rate_eur` | historical EUR value and original decimal rate text | Preserve both. Never recompute imported historical values when opening or editing a transaction. |
| `personal_expense_eur_minor`, `recoverable_eur_minor` | separate integer EUR fields | Preserve signed personal amount (including negative reimbursements) and recoverable amount. Home totals use the source personal value directly. |
| `description`, `category`, `subcategory`, `note` | editable transaction fields | Preserve empty subcategory as absent. Description becomes the row title. |
| `account`, `trip_id`, `paid_by`, `affects_my_accounts` | transaction metadata and links | Preserve source account label exactly. Link a trip only when its ID exists. Do not invent an account link for labels absent from `accounts`. |
| `home_type`, `origin`, `entered_at`, `cached_personal_value` | provenance metadata | Preserved without displaying it in the main list. |
| `needs_review`, `review_reason` | import metadata | Preserved in provenance; no review screen, queue, or automatic recategorization. |

| Source `kind` | Local kind | Spending treatment |
| --- | --- | --- |
| `Spesa` (2,449) | expense | Cash out; personal amount from source. |
| `Entrata` (302) | income | Cash in; not spending. |
| `Investimento PAC` (118) | PAC investment | Cash out to investment; not spending. |
| `Anticipo per altri` (8) | advance for others | Cash out, recoverable; not personal spending unless source says otherwise. |
| `Rimborso` (2) | reimbursement | Cash in; signed personal spending adjustment from source. |
| `Deposito` (1) | deposit | Cash out, recoverable; not personal spending. |
| `Rimborso deposito` (1) | deposit refund | Cash in; not income or spending. |

No source movement is silently mapped to expense. A new or malformed kind aborts the whole import. The seven known kinds total 2,881 rows.

## Related tables

| Source table | Local table | Rule |
| --- | --- | --- |
| `accounts` (3) | `historical_accounts` | Retain source name, kind, currency, opening date/value, active flag, note, source sheet/row, and original cell JSON. The movement's account label remains independent when it does not match one of these names. |
| `trips` (10) | `historical_trips` | Retain source ID and all fields; movement `trip_id` must reference one of these IDs when populated. |
| `recurring_rules` (11) | `historical_recurring_rules` | Retain subscription/investment kind, amount/currency, schedule fields, PAC details, account, source row, and original cell JSON. These are definitions only; no historical occurrences or transactions are generated. The empty `expected_occurrences` table reserves stable occurrence IDs and a unique `matched_transaction_id` for future one-to-one matching; it never contributes to current totals. |
| `exchange_rates` (303) | `historical_exchange_rates` | Retain source row, date, currency, exact decimal rate text, status/origin/key, and original cell JSON. Existing movement EUR values and rates remain unchanged. |
| `source_rows` (2,881) | `historical_source_rows` | Preserve original spreadsheet cell JSON by sheet and row for traceability. |
| `migration_warnings` (254) | `historical_import_warnings` | Preserve code/detail by sheet and row as import metadata only. |
| `migration_meta` | validation only | Require `schema_version = 1`; do not execute prose stored in metadata as instructions. |

## Validation and ambiguities

Validation checks required tables/columns, source schema version, SQLite integrity, movement identity, exact kinds, EUR/CNY/THB currencies, movement and exchange-rate timestamps, positive original movement and rule amounts, nonnegative recoverable values, trip references, source-row coverage, recurring kinds, and valid preserved row JSON. Source table primary keys enforce source identity uniqueness. The importer stages a coordinated SQLite snapshot in temporary app storage, validates before showing a preview, then imports all tables and removes Demo records in one local transaction. Failure rolls back all changes. A staged snapshot is deleted after completion or cancellation. An exact reimport is a no-op; changed source identity/fingerprint or a changed seed digest is rejected without overwriting local edits.

Source dates have no timezone. The exact text is kept so a future date model can avoid the Europe/Rome display assumption. Of 2,830 movements with an account label, 2,573 labels do not exactly match one of the three `accounts` names; 51 movements have no account label. Those labels remain usable for display and filtering, but no canonical account relationship is invented. This does not prevent faithful import of the movement itself. One recurring rule has a non-ISO start-date string; it is preserved exactly and no occurrences are generated. One legacy cached personal value differs from the mapped personal value; both source fields are preserved, and Home uses `personal_expense_eur_minor` without recalculation. The source also carries 254 legacy warnings, including 101 rows without a technical ID; its own stable `movements.id` is used for all 2,881 rows.

**Mac verification:** all 2,881 movements passed the version-1 mapper; zero movement rows were rejected. The 3 accounts, 10 trips, 11 recurring rules, 303 exchange rates, 2,881 original source rows, and 254 warning rows were imported into a disposable local database. The source-row numbers for unresolved account links and date/cache ambiguities are written only to the ignored local file `DerivedData/import-audit.txt` by `scripts/audit_seed.py`. This audit file contains row numbers and counts, never transaction contents.

## Managed accounts and recurrence in local schema 6

On the schema-5 upgrade, each distinct historical master-account name is added to the managed account list if absent. The existing historical table and transaction labels are retained. No `transactions.account_id` is inferred for unmatched movement labels; the user can select a managed account when editing a specific movement. Account rename and archive preserve its stable ID and historical source rows.

Imported recurring definitions remain in `historical_recurring_rules` and generate no transactions. The user may explicitly create a new EUR local recurring template from one, choosing its account and start date. Its `historical_source_id` links the template to the imported definition, while local due dates use deterministic occurrence IDs. The original 11 definitions and their spreadsheet provenance stay intact. Due local dates are expected records with zero ledger effect.

Before a new historical import commits, EasyTrack checks whether its real movements plausibly overlap an **already counted** local recurring payment. The preview lists every blocking pair together, including both descriptions, dates, amounts, account labels, kind, and reason. A legacy label is not assumed to equal a managed account ID. Each pair must be marked **Same payment** or **Separate payment**; one real movement cannot settle two occurrences. The screen shows the combined change to personal spending, expenses, income, PAC, record counts, and provisional rows. No import writes occur until every pair is resolved and the user confirms. Same payment retains the imported transaction UUID, source sheet/row, original values, rate and personal share; it explicitly maps the confirmed managed account and soft-deletes the old counted estimate in the same SQLite transaction. Separate payment retains both movements. An unchanged seed remains a no-op, and any failed or cancelled import rolls back completely. Expected-only occurrences do not block import. See [reconciliation](RECURRING_RECONCILIATION.md).

**Simulator verification:** the iOS 27 Files picker, preview, atomic import, Demo removal, relaunch persistence, and no-op reimport were exercised with a clearly synthetic one-movement seed. The real 2,881-row seed was not copied into the simulator or captured by UI tests.

**Current editor behavior:** The normal editor accepts and displays one EUR amount and saves integer EUR cents. Source currency/amount, imported EUR value, historical rate, personal value, source row, and raw row JSON remain stored for provenance and backup. An edit to a foreign-currency movement sets the current transaction amount/currency to EUR while retaining the original imported fields in provenance. The “Historical values” editor section is intentionally absent. Imported separate personal shares are preserved rather than silently recalculated; a short note appears when that affects an expense.
