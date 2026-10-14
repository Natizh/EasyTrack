# EasyTrack

A native SwiftUI iPhone finance app with an offline SQLite ledger. Home, Activity, editable transaction details, Automations, and Settings are implemented. Historical import and a local notification parser are available. The app does not bundle the seed or the user's spreadsheet.

## Notification automations

The **Capture Payment Notification** App Intent accepts source app, title, subtitle, message, and optional notification date from Shortcuts. EasyTrack commits the raw capture first. An active notification-format rule can then create a EUR transaction locally; without a suitable rule, the sample stays on its source page as **Set up notification format**, **Add notification format**, or **Could not create transaction**. It never invents missing amounts or descriptions. The app sends no financial data to a server and uses no paid API.

Each notification source application maps to one EasyTrack account. An exact name match to an existing account is proposed automatically; otherwise first setup offers to create an account with the source name or choose an existing one. The mapping is confirmed once and shared by every format under that source. Changing it affects future transactions only. An application can have several formats, such as outgoing payments, incoming transfers, refunds, and investments. A format is identified by stable wording, while amount and merchant or counterparty are extracted anew from each event. One outgoing-payment rule can therefore handle many merchants.

Open **Automations → source → Set up format** after the first capture. The builder proposes an amount and description from that sample. Its seven cards cover **Notification input → Source/account → Direction/type → Amount → Merchant/description → Duplicate protection → Create transaction**. **Test automation** runs a live preview before activation. Activation offers to create the first sample's transaction exactly once or leave that sample unadded. Later matching captures run automatically through the App Intent. Each source can have multiple named format rules with priorities, enable switches, editing, reordering, and confirmed soft deletion. Editing increments the rule version and never reinterprets earlier transactions. Deleted formats do not delete transactions.

The payment application is not a spending category. Parsed transactions are valid with **no category**; the database stores SQL `NULL` for that field. Home shows a small **Uncategorized** section with a count and recent items. Opening a transaction lets the user choose an existing category or enter one, and it leaves that section immediately after Save. Category assignment is separate from parsing; automatic merchant-based categorization is deferred.

EUR extraction accepts a symbol or `EUR` before or after the number, comma or period decimals, and unambiguous thousands grouping. Matching conditions include contains, begins with, and ends with; short, restricted regular expressions live under **Advanced matching**. The parser uses the supplied notification date when available, otherwise capture time. A full diagnostic attempt remains on the source page for unmatched, failed, and duplicate captures. There is no general review inbox. Details and limits are in [the parser design](docs/NOTIFICATION_PARSER_DESIGN.md).

Two persistent checks prevent duplicate transactions. The exact key normalizes source and notification text, with the supplied notification date included when present. Exact replays with a supplied date remain duplicates; when no date is supplied, exact checks use a bounded window because identical text may be a later real purchase. The semantic key uses integer EUR cents, normalized description, and mapped account. It checks a symmetric **10-minute default window**, configurable to 5 or 30 minutes. Different amounts and matching payments outside the window are allowed. Deduplication records, the transaction, event link, result, and operation log commit atomically. A processing failure rolls back those writes while retaining the raw capture and a failed diagnostic.

The local SQLite database upgrades non-destructively to schema version **4**. Existing schema-3 rule JSON and version history remain intact while source-level account mappings are backfilled. JSON backup format version **4** includes local accounts, source mappings, current rules, rule versions, and captured attempts along with the existing ledger and import provenance. Backups contain raw notification text: keep them private. Restore is still planned. The fictional notification menu exists only in Debug builds; Release has no sample buttons.

## Historical import

The inspected seed has schema version 1. Its [field mapping and validation rules](docs/IMPORT_MAPPING.md) cover seven movement kinds, original and historical EUR amounts, personal spending, recoverable amounts, currencies, accounts, trips, recurring rules, exchange rates, and spreadsheet provenance. The local database is schema version 4; the historical import mapping remains version 1.

On an iPhone, choose **Settings → Choose SQLite seed**. EasyTrack uses the system document picker, takes a coordinated read-only SQLite snapshot in temporary app storage, validates it, and displays counts. Tap **Import** only after checking the preview. The import inserts all related tables and replaces the three Demo records in one local transaction. A failure rolls back, leaving existing data intact. The temporary snapshot is removed after import or **Discard preview**; stale snapshots are removed when the import service next starts. The operational database remains in the app's private Application Support folder. EasyTrack's Documents folder is visible in Files for transferring a seed; its operational database is never placed there.

Historical source IDs map to stable transaction UUIDs and are kept with source sheet/row and fingerprint. Importing the exact same seed again adds zero records and leaves local edits intact. A changed seed or changed identity is rejected rather than silently overwriting an edited transaction. Historical import identity is separate from notification deduplication.

The 11 recurring rules are definitions only: no historical expected occurrences or duplicate transactions are generated. A future occurrence will need its own ID and an optional one-to-one match to a real movement; matched expectations must never add to spending totals. The 303 rate records and each movement's original rate and EUR value are preserved. Editing does not silently recalculate historic conversion or personal share.

Home shows **personal spending** from the seed's signed personal EUR field. Its **all expenses** figure includes `Spesa` only; income includes `Entrata` only; PAC investment is shown separately. Reimbursements adjust personal spending but are not income. Advances for others, deposits, and deposit refunds keep their own kinds and do not become expenses. Activity supports text search and kind, category, account-label, trip, and original-currency filters. Activity displays each movement's stored EUR value. Every imported movement opens in the editor, where one clearly labeled EUR amount, classification, date, description, account label, trip, and note can be corrected. The editor accepts comma or period decimals, stores integer cents, and shows inline validation or save errors. A successful Save closes the editor and updates Home and Activity immediately. The UI currently edits **EUR only**; ISO currency, historical EUR/rate, source values, and spreadsheet provenance remain in storage and the backup. Changing a foreign-currency movement's EUR amount sets its current currency to EUR while retaining the original imported values in provenance. Legacy `needs_review` and warnings stay as import metadata; there is no review queue.

The three master accounts, ten trips, and eleven recurring rules can be inspected under **Settings → Imported reference data**. Movement account labels are preserved even where they do not match a master account; no relationship is invented. JSON backup export includes transactions, tombstones, operation IDs, notification events and parser attempts, rule versions, historical provenance, original source rows, reference tables, rates, and warnings. It contains sensitive data; keep it private. Backup restore is not implemented yet.

## Architecture

| Area | Location | Responsibility |
| --- | --- | --- |
| UI | `EasyTrack/UI` | Home, Activity, transaction editing, system document picker, import preview, source diagnostics, Settings |
| Shared model | `EasyTrack/Shared` | Integer minor-unit money, stable IDs, kinds, totals, backup models |
| Local persistence | `EasyTrack/Persistence` | SQLite WAL database, edits, tombstones, operation log, atomic import |
| Import | `EasyTrack/Import` | Version-1 mapper, validation, read-only staging snapshot |
| Notification intake | `EasyTrack/Intake` | App Intent captures raw events and applies active local rules |
| Parser | `EasyTrack/Shared/NotificationParser.swift` | Bounded deterministic extraction, preview, validation, fingerprints |
| Automation storage | `EasyTrack/Persistence` | Versioned rules, diagnostic attempts, atomic creation and duplicate records |
| Automation UI | `EasyTrack/UI/AutomationBuilder.swift` | Source cards, sample diagnostics, live block builder |
| Folder probe | `EasyTrack/Exchange` | User-selected Files folder bookmark and coordinated test write/read |

Coordinated file work runs off the main actor. The app uses no paid API, backend, CloudKit entitlement, or network request. The Files folder probe is **not synchronization**. A backup export creates a separate JSON file; it does not update the selected folder automatically or restore data.

## Build and Mac verification

Requires Xcode 26.5 or newer. The app targets iOS 17 or newer; the notification automation trigger requires iOS 27. Keep the seed outside this project. From the project root:

```sh
export EASYTRACK_SEED_PATH="/absolute/path/outside/EasyTrack/spese_app_seed.sqlite"
swift test --disable-sandbox --scratch-path "$PWD/.build"
sh scripts/test_database.sh
python3 scripts/audit_seed.py "$EASYTRACK_SEED_PATH" DerivedData/import-audit.txt
xcodebuild -project EasyTrack.xcodeproj -scheme EasyTrack -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$PWD/DerivedData" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EasyTrack.xcodeproj -scheme EasyTrack -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$PWD/DerivedData" CODE_SIGNING_ALLOWED=NO build
```

`EASYTRACK_SEED_PATH` is optional for the synthetic tests; it enables the disposable real-seed import test. Do not place the seed in `EasyTrack/`, the Xcode project, build assets, CI, or Git. `DerivedData/import-audit.txt` is ignored and contains **source row numbers only** for unresolved account links and source-format anomalies. No test prints movement descriptions or amounts.

### Verified on this Mac — 13 October 2026

- The external seed was read in place and staged to temporary test storage. Schema version 1 and SQLite integrity passed validation.
- All **2,881 movements**, **3 accounts**, **10 trips**, **11 recurring rules**, **303 exchange rates**, **2,881 original source rows**, and **254 legacy warning rows** imported into a disposable local database. **Zero movement rows were rejected.**
- The real-seed test verified per-movement kind, original amount/currency, EUR amount, personal and recoverable values, and source row; it also verified totals, an edit/reopen with provenance retained, no-op reimport, Demo removal, and rejection of a deliberately corrupted temporary seed.
- Synthetic tests cover exact type mapping, minor-unit and signed amounts, idempotency, changed-source rejection, and rollback after a mid-import constraint failure.
- Seven Swift tests passed with the real-seed path set. The SQLite smoke test passed. Debug and Release generic-iOS-device builds passed without signing during the import milestone.
- These were Mac-only checks before Xcode 27 and the simulator were installed. Physical iPhone, Shortcuts, SideStore, iCloud Drive, signing, and app-update behavior remain untested.

### Source ambiguities

All 2,881 movement records are mapped without forcing a kind or recomputing a value. **2,573** movement account labels do not exactly match the three master account names; **51** have no account label. The original labels remain intact and editable, but canonical account links cannot be inferred safely. One recurring rule has a non-ISO start-date string, preserved as text; one legacy cached personal value differs from the source's mapped personal value, and both source fields are retained. The seed's movement timestamps omit timezone information; the Date-based interface currently interprets them in Europe/Rome while preserving the original text. Exact source row numbers for these ambiguities are in the ignored local audit file generated above.

## iOS 27 simulator checks — 13 October 2026

Xcode 27.0 and the already installed iOS 27.0 runtime were used with the existing **iPhone 17 Pro** simulator. No runtime or simulator was downloaded or created. EasyTrack built, installed, and launched. The simulator initially had only the three Demo records; its container was inspected before installation and before import.

- **Automated UI, Demo-only:** four XCUITests passed for Home, Activity text search and kind filtering, a transaction edit persisted across app relaunch, an Automations demo diagnostic event, and Settings navigation. The test result is ignored under `DerivedData/UITests-Demo-2.xcresult`. Activity search was made explicitly visible after the iOS 27 UI test exposed a hidden `.searchable` control. These tests now skip if history is imported; a skip was verified on the synthetic imported database.
- **Automated UI, synthetic import:** a non-personal one-movement fixture was placed in the simulator's EasyTrack Documents folder. The system Files picker selected it, the preview offered **Import 1 movements**, and confirmation committed it. A read-only database check found **1 imported movement, 1 account, 0 Demo records, and 1 import operation**. Relaunch kept the movement. The app's temporary staged SQLite files were removed.
- **Persistence layer plus automated UI:** EasyTrack's `SQLiteDatabase.save` edited only the synthetic simulator movement and preserved its source identity and row. The second picker preview offered **Confirm no changes**; after confirmation the database still had **1 movement, 2 operations** (import plus edit), and the edit and provenance link remained. Result bundles are ignored under `DerivedData/UITests-SyntheticImport-2.xcresult` and `DerivedData/UITests-SyntheticReimport.xcresult`.
- **EUR editor regression:** Automated UI tests on the synthetic movement confirmed comma-decimal amount and description editing, Save returning to Activity, immediate Activity and Home totals, and persistence after relaunch. Empty, zero, negative, and malformed amounts showed inline errors and kept the editor open. Read-only SQLite inspection confirmed the saved integer EUR cents, stable source identity, and retained provenance. The former duplicate editable historical EUR field caused Save to reject an amount-only edit; it and the normal editor's “Historical values” section are now removed.
- **Files folder prototype:** An XCUITest selected the Files-visible EasyTrack folder, ran a coordinated write/read, terminated and relaunched the app, and ran the write/read again without reselecting. Both readbacks passed. Read-only host inspection decoded `easytrack-folder-probe.json` as schema 1 with an operation ID; the file timestamp advanced after relaunch. This verifies the simulator's On My iPhone provider, not iCloud Drive or synchronization.
- **JSON backup export:** A focused XCUITest tapped **Export local data as JSON** and saved a new uniquely named file. Read-only host inspection decoded the exported schema-2 JSON with one synthetic transaction, one provenance row, one historical account, one source row, and no real-seed records. A failed exporter result is wired to a visible app alert, but the failure branch has not been simulated. Restore remains unimplemented.
- **Final regression run:** All seven Swift tests passed with the external seed path supplied; the SQLite smoke test passed. Debug build-for-testing and Release simulator build passed under Xcode 27. The two focused editor UI tests, folder probe across relaunch, and unique-name JSON export UI test each passed against the synthetic simulator database. An in-place simulator install retained Demo records and diagnostic events during the earlier check, but this does not establish SideStore update preservation.

The initial import milestone saved Demo [Home](DerivedData/SimulatorScreenshots/home-demo.png), [Activity search](DerivedData/SimulatorScreenshots/activity-demo-search.png), and [Settings](DerivedData/SimulatorScreenshots/settings-demo-only.png) screenshots. Parser debugging added only fictional screenshot attachments under ignored `DerivedData/`. **No personal transaction was captured in a screenshot or test attachment.** The real historical seed stayed outside the simulator and app assets; its full import remains verified only by the disposable Mac database test. The Files picker first showed a blank sheet while the simulator's document service loaded, then opened normally after several seconds. Even with the Demo-test skip guard, avoid running UI tests against personal data because XCTest failures may capture the screen.

To reproduce the synthetic picker test, use the existing ignored `DerivedData/TestFixtures/synthetic_seed.sqlite` or generate a new fixture with a different filename using `python3 scripts/make_synthetic_seed.py <ignored-output.sqlite>`. Check that the simulator app contains no user data before running import tests, then place the fixture in its Files-visible Documents folder. Run only the matching `EasyTrackUITests` cases on that simulator. The generated fixture, screenshots, test results, and build output stay under ignored `DerivedData/`.

## Parser verification — 14 October 2026

The parser suite used only fictional payment text. **19 Swift tests passed** with the external historical seed test enabled. They cover schema migration, one format handling multiple merchants, outgoing and incoming formats sharing one source account, two distinct source accounts, account remapping without rewriting old transactions, rule priority and atomic reordering, exact and semantic duplicates, no-date fallback, allowed later payments, version history, soft deletion, retry, and rollback after a forced SQLite failure. The SQLite smoke test passed. Generic iOS Debug and Release builds passed without signing. The Release binary was checked for the absence of fictional sample controls and the Debug-only fault hook.

On the existing **iPhone 17 Pro, iOS 27.0** simulator, the multi-merchant XCUITest captured a fictional outgoing notification, confirmed one source account and one format, created the first transaction, survived relaunch, ignored a replay, and automatically created a different merchant's transaction from the same format. Both began uncategorized on Home. Categorizing only one removed it from that section immediately. A separate XCUITest injected one Debug-only first-sample save failure, confirmed the builder stayed open with an error and the source showed a retryable failed diagnostic, then retried to one transaction under one rule. The editor total regression and schema-4 JSON Files export also passed in focused reruns.

Before installing schema 4 in place, an ignored synthetic-only schema-3 SQLite snapshot was taken. A disposable migration and the in-place simulator update preserved counts across eight ledger/parser tables, transaction values and source links, rule JSON and version history, with zero foreign-key violations. Three existing fictional rule sources received source-level account mappings. The real historical seed was never installed in this simulator; its only historical row is the synthetic fixture. The newest Files backup decoded as readable schema-4 JSON with local accounts, parser sources/rules/attempts, and synthetic-only transactions.

The simulator test did not invoke the physical iOS Shortcuts notification trigger or establish what a real payment app supplies. Parser screenshots and Xcode results use fictional data and remain under ignored `DerivedData/`; none are bundled or committed. The App Intent path is compiled and wired to the same capture method, but actual Shortcuts delivery and locked-device execution still need an iPhone.

## Pending iPhone tests

1. Set up [SideStore with iLoader](https://docs.sidestore.io/docs/installation/install). First rebuild **Release for generic iOS device** using the command above, then package an unsigned IPA locally with `sh scripts/package_unsigned_ipa.sh`, import it into SideStore, and confirm installation. No Apple credentials belong in this repository. The older unsigned IPA was removed after simulator-only code changes so it cannot be mistaken for a current build.
2. Place the external seed in Files on the iPhone. Select it in EasyTrack Settings, verify the preview counts, import, reopen the app, edit an imported transaction, and confirm the edit and source row remain. Select the same seed again and verify **0 new movements**. Export a private backup before testing an in-place app update. Keep the same app identifier; never delete the app to update it.
3. On iOS 27, test the [Shortcuts Notification trigger](https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/10.0/ios/27) and EasyTrack's **Capture Payment Notification** action with a harmless notification. Confirm which title, subtitle, message, app, and date fields Shortcuts actually supplies and whether it runs while locked. The action captures a diagnostic and may create a transaction when an active matching rule has complete fields; physical-device delivery remains unverified.
4. Select an On My iPhone or iCloud Drive folder in Settings, write/reread the test file, relaunch, and test the saved bookmark on a physical device. Cross-device synchronization has not been implemented or verified. SideStore refresh and update preservation also remain device tests.

## Recommended next work

After device validation, resolve account aliases and the historical timezone convention with the user; add backup restore and a versioned exchange format; then build recurring expected-occurrence matching, analytics and reports, budgets, multi-currency editing and conversion, and the macOS companion. Continue to keep expected occurrences separate from actual transactions. Real bank notification formats, physical-device Shortcuts delivery, iCloud Drive behavior, SideStore installation, and update preservation remain unverified. The builder's compatibility depends on the fields Shortcuts actually delivers for each source.
