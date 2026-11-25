# Build and install with Xcode

[EasyTrack](../../README.md) · [Documentation](README.md) · English / [Italiano](../it/XCODE_INSTALL.md)

Use Xcode to develop EasyTrack, run the simulator or prepare an unsigned IPA for [SideStore](SIDESTORE_INSTALL.md). For routine iPhone signing refresh after setup, SideStore is the recommended route.

## Requirements

- A Mac and **Xcode 26 or later**. The project targets **iOS 17+** and uses iOS 26 SwiftUI APIs behind availability checks; the deployment target is not the required SDK version.
- A macOS version supported by your chosen Xcode release. Consult [Apple's compatibility table](https://developer.apple.com/xcode/system-requirements/) rather than assuming every Xcode release works on the same Mac.
- An installed iPhone simulator/runtime for simulation, or an iPhone with compatible iOS and development signing for device installation.
- Command-line Python 3 for IPA validation. The packaging helper uses macOS `ditto`.

## Open the project

```sh
git clone https://github.com/Natizh/EasyTrack.git
cd EasyTrack
open EasyTrack.xcodeproj
```

Select the shared **EasyTrack** scheme. No third-party application runtime packages are required.

## Run in the simulator

Choose an already installed iPhone simulator and **Run**. Find available UUIDs with `xcrun simctl list devices available`. Reuse an existing simulator rather than creating a new one for each test. No Apple-account signing is needed for a simulator build.

## Run on a physical iPhone

Select the connected device, choose your team in **Signing & Capabilities**, enable Developer Mode when iOS requests it, and choose **Run**. A unique bundle ID may be necessary for your signing team. Changing the ID or signing identity may create a separate installation with an empty database; it does not migrate the SideStore app's history.

Free Personal Team provisioning lasts **seven days**; renew by re-signing/reinstalling when needed ([Apple guidance](https://developer.apple.com/help/account/basics/about-your-developer-account/)). Before changing or removing an installation, save an external [JSON backup](BACKUP_RESTORE.md).

## Build an unsigned IPA

Run from the repository root on macOS. This builds a Release app for a physical iPhone, not a simulator:

```sh
xcodebuild -project EasyTrack.xcodeproj -scheme EasyTrack -configuration Release   -destination 'generic/platform=iOS' -derivedDataPath DerivedData   PRODUCT_BUNDLE_IDENTIFIER=local.easytrack.finance CODE_SIGNING_ALLOWED=NO build
EASYTRACK_IPA_OUTPUT=DerivedData/EasyTrack-0.2-build11-unsigned.ipa   sh scripts/package_unsigned_ipa.sh
```

The example filename matches the current source version **0.2 (11)**. A filename does not set the build version; `EasyTrack/Info.plist` does. Choose a fresh filename for each generated package; the helper refuses to overwrite an existing IPA.

The helper validates the Release app before packaging and the IPA afterward: app version/build against source, original bundle ID, device platform, unsigned package structure, ZIP integrity, and exclusion of database, spreadsheet, backup and signing files. These packaging checks do not replace runtime tests.

If you use a different build directory, pass it with `EASYTRACK_DERIVED_DATA` and set a matching output path. Install the resulting IPA using the [SideStore guide](SIDESTORE_INSTALL.md). Preserve the existing app/signing identity when updating; changing only the filename cannot ensure data continuity.

See [Development](DEVELOPMENT.md) for tests, source organization and contribution guidance.
