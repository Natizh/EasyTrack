# Install and update with SideStore

[EasyTrack](../../README.md) · [Documentation](README.md) · English / [Italiano](../it/SIDESTORE_INSTALL.md)

SideStore is recommended for everyday use because routine signing refresh can happen on the iPhone after initial setup. It does not require opening Xcode for every renewal. Xcode remains the right tool to build or debug the app.

## Before you start

You need an iPhone supported by both EasyTrack (**iOS 17+**) and the installed SideStore release, an Apple account, and a compatible unsigned EasyTrack IPA. Follow the official [prerequisites](https://docs.sidestore.io/docs/installation/prerequisites) and [installation guide](https://docs.sidestore.io/docs/installation/install.html) for computer-assisted setup, pairing, Developer Mode where required, and the local VPN. SideStore requirements can differ from EasyTrack's minimum iOS version.

**This repository currently has no prebuilt IPA release.** If you are compiling the app yourself, use the [Xcode guide](XCODE_INSTALL.md#build-an-unsigned-ipa). An unsigned IPA cannot launch on an iPhone until signed and installed. SideStore handles that signing step, not compilation.

## Install EasyTrack

1. Complete the official SideStore setup and confirm SideStore can refresh itself.
2. Transfer the EasyTrack IPA to a Files location accessible on your iPhone.
3. In SideStore's **My Apps** page, use the add/import control and select the IPA. Complete signing with the configured Apple account.
4. Open EasyTrack once. For English, choose **Impostazioni → Lingua → English**.
5. Create an account, record a fictional test entry if useful, and verify that the app appears among SideStore's active apps.

With a free account, SideStore documents a three-active-app limit including SideStore itself, plus App ID limits. Check the [official FAQ](https://docs.sidestore.io/docs/faq.html) for current conditions rather than assuming unlimited installations.

## Refresh is different from updating

**Refresh** renews the installed build's provisioning. With free signing, do this before the seven-day period expires. Check the remaining time and a successful refresh in SideStore; background refresh is not guaranteed. Use the network and local VPN required by your SideStore version. EasyTrack's ordinary ledger use does not need the local signing VPN or a running Xcode session.

**Update** installs a newer EasyTrack build from another IPA. Refreshing alone does not download or compile new EasyTrack code.

## Update an existing ledger

1. In the installed EasyTrack, export a fresh [JSON backup](BACKUP_RESTORE.md) to Files **outside the app's own folder**. Verify it is present and readable before continuing.
2. Obtain the new IPA. Repository-built packages retain the original bundle ID `local.easytrack.finance`.
3. Use the same SideStore installation, Apple account and app identity. Import the new package **over the existing EasyTrack app**. Do not uninstall first and do not override its identity to create a second app.
4. Open EasyTrack and check several transactions, accounts and totals. Keep the backup until verification is complete.
5. If you use Shortcuts, confirm its EasyTrack action still points to the intended installation and test capture with fictional input.

The original bundle ID alone is not a guarantee: signing tools may rewrite identifiers, and a different signing identity can produce a separate installation. If two EasyTrack icons appear or one opens an empty ledger, stop deleting or replacing apps. Keep the installation containing your data, export it, and follow [backup and restore](BACKUP_RESTORE.md) to transfer it deliberately.

## Troubleshooting

| Symptom | Next step |
| --- | --- |
| EasyTrack no longer opens | Check signing expiry and refresh status in SideStore. Do not uninstall the app holding the ledger. |
| Refresh fails | Check network, local VPN, pairing and account state against [SideStore troubleshooting](https://docs.sidestore.io/docs/troubleshooting). Pairing may need replacement after an OS update or reset. |
| The app is absent from active apps | Confirm installation completed; do not assume a separate Xcode installation is managed by SideStore. |
| An update opens an empty ledger | Check for a second app identity; export from the original app before choosing a restore destination. |
| EasyTrack action is missing in Shortcuts | Open the signed app once, reopen Shortcuts and check the [notification guide](SHORTCUTS_SETUP.md). |

Keep IPA builds separate from financial backups. Device acceptance coverage and outstanding checks are tracked in [issue #8](https://github.com/Natizh/EasyTrack/issues/8).

Issue #8 records user-reported installation and in-place data-preservation checks, and the later resolution of My Apps visibility. These reports are narrower than the full acceptance checklist: subsequent refresh and notification reliability still require their own evidence.
