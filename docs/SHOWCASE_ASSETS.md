# Rebuilding the GitHub showcase

The images in [`assets/showcase/`](assets/showcase/) are compositions of **real EasyTrack UI test captures**. All visible accounts, merchants, movements, notifications, and import rows come from fictional fixtures. No production database, personal workbook, backup, or real notification is used.

## Requirements

- macOS with Xcode and an **already installed** iPhone simulator and compatible iOS runtime.
- Python 3, available on the command line.
- ImageMagick 7 (`magick`) to draw the original device frames and compose PNGs. This is a documentation tool; it is not an app dependency.
- Enough free disk space for one Xcode build and UI test run. The script reports free space before and after heavy steps and reuses `.build/XcodeDerivedData`.

Find an existing simulator UUID with `xcrun simctl list devices available`. Do not create another simulator just for screenshots. From the repository root, run:

```sh
python3 scripts/capture_showcase.py --device <existing-iPhone-simulator-UUID>
```

Use `--replace` to regenerate only the eight showcase PNGs after reviewing the previous output. The script refuses to overwrite them by default.

The workflow builds a temporary copy of the Xcode project with bundle ID `local.easytrack.finance.showcase`; it verifies that the app does not already exist on the simulator. The normal EasyTrack bundle ID, signing settings, and project file are untouched. A Swift test creates an isolated, internally checked ledger with six months of fictional activity, two accounts, categories, a budget, a recurring plan, PAC investments, two notification rules, and the working sample Excel import. Four dedicated UI tests open that app and attach six real screen captures. The script fixes the simulator's status-bar time for the run, extracts the XCTest attachments, renders consistent original phone frames, removes the temporary app, and restores the previous light/dark setting and boot state.

Generated files:

| File | Purpose |
| --- | --- |
| `hero.png` | Three-phone README opening, with Home as the central screen. |
| `phone-home.png`, `phone-activity.png`, `phone-analytics.png` | Financial overview, history, and reports. |
| `phone-quick-entry.png`, `phone-automation.png`, `phone-accounts.png` | Daily entry, notification rule setup, and the default-account picker. |
| `social-preview.png` | Ready-to-upload 1280 × 640 GitHub social preview. |

The renderer is also runnable on previously exported real captures:

```sh
python3 scripts/render_showcase.py \
  --screens /path/to/six-real-captures \
  --output docs/assets/showcase --replace
```

The input folder must contain `home.png`, `activity.png`, `analytics.png`, `quick-entry.png`, `automation.png`, and `accounts.png`. The renderer checks their dimensions and never draws a replacement app interface.

## GitHub repository presentation

The connected repository tools do not expose social-preview upload. If GitHub offers it for this repository, an admin can upload [`social-preview.png`](assets/showcase/social-preview.png) in **Repository → Settings → Social preview → Edit → Upload an image**. The file is 1280 × 640 and under 1 MB. [GitHub's social-preview guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview) limits uploads for private repositories and says private-repository previews cannot be shared publicly; keep the ready asset if the control is unavailable. The suggested repository description is:

> Private, native expense tracking for iPhone. Built with SwiftUI, SQLite, and user-configured Shortcuts automations.

Suggested topics: `ios`, `swift`, `swiftui`, `expense-tracker`, `personal-finance`, `sqlite`, `local-first`, `apple-shortcuts`. [Topic names are public](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics), even for a private repository; review that list before adding it under the repository's **About → Edit repository metadata** menu. Leave the homepage field empty until there is a real product page. Do not change repository visibility as part of the presentation update.
