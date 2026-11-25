# App language

[EasyTrack](../../README.md) · [Documentation](README.md) · English / [Italiano](../it/LOCALIZATION.md)

EasyTrack opens in Italian on a new or existing installation until the user chooses another language. **Settings → Language / Impostazioni → Lingua** switches the interface between Italian and English immediately. The choice survives relaunch and does not change the financial ledger.

The language preference is kept locally in app settings, outside the SQLite ledger and format-15 JSON backup. Restoring a backup into an existing installation keeps that installation's language choice. A new installation starts in Italian, even when its restored backup was made on an English-language installation.

Dates and currency amounts shown in the app use the chosen language's locale. Parsed and stored amounts remain integer minor units. Merchant names, descriptions, accounts, custom categories, source labels, original notification text, parser rules, enum codes, CSV field names, and backup data are never translated. The App Intent and its parameter identifiers remain stable for existing Shortcuts; only human-readable action labels have translations. Shortcuts may use its own system language, so the notification field mapping remains the same even if its labels differ.

The native `Localizable.xcstrings` catalog is the source for interface translations. `InfoPlist.xcstrings` localizes the camera, microphone and speech permission explanations; iOS controls the language of its own permission sheet. Run `python3 scripts/audit_localization.py` to check literal UI keys, explicit lookup keys, Italian coverage, and format placeholders.
