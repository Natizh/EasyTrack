# Development and contributions

[EasyTrack](../../README.md) · [Documentation](README.md) · English / [Italiano](../it/DEVELOPMENT.md)

Use the [Xcode guide](XCODE_INSTALL.md) to open or build the project. EasyTrack uses SwiftUI, Charts, App Intents, Vision, Speech and SQLite through Apple system frameworks, with no third-party app runtime packages. Amounts are integer currency minor units.

## Source map

| Path | Responsibility |
| --- | --- |
| `EasyTrack/App/` | Application entry and lifecycle. |
| `EasyTrack/UI/` | Screens, editors and navigation. |
| `EasyTrack/Shared/` | Models, accounting, parsers and shared logic. |
| `EasyTrack/Persistence/` | SQLite storage, migrations, backup and reconciliation. |
| `EasyTrack/Intake/` | Shortcuts App Intent for notification capture. |
| `EasyTrack/Import/`, `EasyTrack/Export/` | Seed validation/import and transaction export. |
| `EasyTrack/Resources/` | App resources and localization catalogs. |
| `Tests/`, `EasyTrackUITests/` | Core tests and simulator journeys with fictional data. |
| `Tools/HistoricalImportConverter/` | Standard-library Python XLSX-to-SQLite converter. |
| `scripts/` | Packaging, audits, UI runners and screenshot generation. |
| `docs/en/`, `docs/it/` | Matching English and Italian guides. |
| `docs/assets/`, `docs/examples/` | Shared screenshots and fictional import fixtures. |

## Verification

Run commands from the repository root. Swift/Xcode app checks need the appropriate Apple toolchain; the converter uses Python 3 only.

```sh
swift test --jobs 2
python3 -m unittest Tools/HistoricalImportConverter/test_converter.py
python3 scripts/audit_localization.py
```

For focused CSV/XLSX generation and independent file validation:

```sh
sh scripts/test_transaction_export.sh
```

Use an **existing simulator UUID** from `xcrun simctl list devices available`. Replace the placeholder before running:

```sh
python3 scripts/test_accounting_ui.py --device <existing-iPhone-simulator-UUID>
python3 scripts/test_pr35_ui.py --device <existing-iPhone-simulator-UUID>
```

The first runner checks Home metric navigation; the second covers notification and reimbursement journeys. Both use separate app identities and fictional ledgers, refuse a pre-existing test app and clean up their own installation. Disable parallel testing for direct Xcode UI runs to avoid simulator clones. See [showcase assets](SHOWCASE_ASSETS.md) for reproducible real UI screenshots.

Run the checks appropriate to a change and report what was actually run. Simulator tests do not prove real bank notifications, locked-device execution, physical Files-provider behavior or hands-on VoiceOver acceptance. Device work is tracked in [issue #8](https://github.com/Natizh/EasyTrack/issues/8).

## Propose a change

Check [existing issues](https://github.com/Natizh/EasyTrack/issues), describe the concrete behavior and use fictional examples. Keep changes focused, preserve financial identities/provenance, and explain validation and remaining limits in the pull request. Never commit personal ledgers, notifications, workbooks, backups, signing files or credentials.

## Documentation conventions

- Keep `README.md` and `README.it.md` equivalent in scope and link each to the other.
- Keep matching filenames in `docs/en/` and `docs/it/`, with a direct language switch and local index link on every page.
- Update both languages when behavior changes. Keep identifiers, commands, CSV headers and fixture filenames unchanged across translations.
- Share assets and fictional examples; use relative links so branch previews work.
- Keep old `docs/*.md` navigation pages for existing external links. Put new content in the language folders.
- Distinguish the current SQLite schema, JSON backup format and import seed schema. Mark historical migration details explicitly.
- Do not add a license badge, release download or completed validation claim unless the repository actually provides it.
