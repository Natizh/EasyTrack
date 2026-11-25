# Set up payment notifications with Shortcuts

[EasyTrack](../../README.md) · [Documentation](README.md) · English / [Italiano](../it/SHORTCUTS_SETUP.md)

EasyTrack does not independently read other apps' notifications. A personal automation in **Apple Shortcuts** must receive a selected app's notification and pass its fields to EasyTrack. Trigger availability, supplied fields and locked-device execution depend on iOS and the chosen app. **A captured notification is not yet a financial transaction.**

All names and amounts below are fictional. Keep passwords, card numbers, OTPs and real notification text out of tests and public issues.

## 1. Prepare the source in EasyTrack

1. Open EasyTrack once. In **Settings → Accounts**, create or choose the local account to receive this source's transactions. No bank credentials are requested.
2. In **Automations → Notification setup**, choose **EasyTrack account**, enter a stable **Source app label** such as `Northstar Pay (fictional)`, then tap **Save source and account → Copy name**. Copy it exactly, including case and spaces. This label identifies a source inside EasyTrack; it does not select an installed app.
3. Each source maps to one account and can have multiple formats, for example incoming and outgoing payments. A format recognizes messages; it does not assign categories. Changing the source account later affects future transactions only.

If there is no selectable account, create one in Settings first.

## 2. Choose the notification trigger

1. Open **Shortcuts → Automation → + / New Automation**. If iOS opens a shortcut editor instead, return to Automation or use the shortcut's **Edit → Automation** option where available.
2. If your iOS version offers **Notification → App / When I receive a notification from**, choose the actual installed bank/payment app. This app selection is separate from EasyTrack's source label. If the trigger is unavailable, this automatic workflow cannot be configured as described; manual action input can still test capture.
3. Initially avoid restrictive Title/Subtitle/Message trigger filters: these decide whether the automation runs, not which values the EasyTrack action receives.
4. Enable automatic or locked-device execution only where iOS offers it and after granting the requested permissions. EasyTrack cannot enable those options or guarantee delivery.

See Apple's [trigger reference](https://support.apple.com/guide/shortcuts/apd932ff833f/ios) and [automation guide](https://support.apple.com/guide/shortcuts/apdfbdbd7123/ios) for platform guidance; names and options vary by iOS version.

## 3. Add the EasyTrack action

Choose **Add Action**, search for **EasyTrack** and add **Capture Payment Notification**. The action summary may read **Capture notification from [source]**.

Paste the exact saved source label into **Source app** as fixed text. Do not put the notification variable here. The trigger app, the source label and the local account are three separate choices.

If the action is absent, open EasyTrack, reopen Shortcuts and check that the app is installed, trusted and has valid signing. For SideStore, check refresh without uninstalling the app that holds the ledger; save an external JSON backup first.

## 4. Bind the dynamic fields

For each parameter, tap its **value**, insert the blue **Notification** variable from the trigger, then tap that blue chip to open **Get** and select the required property. Repeat independently for each field.

| EasyTrack action field | Notification property | Italian Shortcuts label |
| --- | --- | --- |
| **Title** | Title | `Notifica → Titolo` |
| **Subtitle** | Subtitle; may be empty | `Notifica → Sottotitolo` |
| **Message** | Body; usually contains amount and description | `Notifica → Corpo` |
| **Notification date** | Date, only if supplied as a Date-typed value | `Notifica → Data` |

For example, insert the Notification chip in Title, tap it, and select Title. A chip still pointing at the entire notification is not yet bound to the right property. Do not type a sample amount or message as fixed text in the production automation.

The date picker may show **Medium** date and time formats with a preview such as `15 Sep 2026, 09:41:00`. Formatting does not prove that the App Intent receives a Date value. If the date property is absent or incompatible, leave this optional field empty: EasyTrack uses capture time. Do not type a localized date manually.

## 5. Verify capture separately from transaction creation

1. Save the automation. A manual run with fictional fixed values such as `Card purchase` and `Paid €12,34 at Cedar Books` checks only the EasyTrack action, not the trigger or dynamic bindings.
2. Generate a harmless notification you control from the selected app, where possible. Check **EasyTrack → Automations → [source] → Captured notifications**. Two notifications with different text reveal accidentally fixed fields. An empty subtitle may be normal.
3. Check each stage separately: the event arrives, an approved format recognizes it, and an actual payment appears exactly once in **Activity** on the right account. Compare with your payment source because Shortcuts may not deliver every event.

Simulator or manual-action tests do not establish real bank delivery, background or locked-device behavior. Verify those on a physical iPhone, including after relaunch, without logging private text.

## 6. Approve a format

Open the captured sample and choose **Set up format / Add notification format**; the source overview may offer **Set up this sample**. The builder has seven blocks: input, source/account, direction/type, amount, description, duplicate protection and transaction creation.

For `Paid €12,34 at Cedar Books`, check €12.34, `Cedar Books`, expense direction and the chosen account. Test a fictional promotional/OTP message too; it should create no expense. Run **Test automation**, then explicitly activate the format. Choose **Create first transaction** only for a genuine verified payment; choose **Activate without adding sample** for tests or nonfinancial events. Do not manually add another copy of a saved transaction.

Incoming and outgoing messages may need separate formats. The parser does not invent foreign-currency conversions. Unrecognized captures remain diagnostics. Raw text follows configurable retention and is cleaned at the next cleanup opportunity, which may require the app to run. Individual captured samples can be deleted without deleting saved transactions.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No Notification trigger or app choice | Check your iOS version and selected app's support. EasyTrack cannot add system triggers. |
| EasyTrack action missing | Open the signed app once and reopen Shortcuts. Check SideStore availability/refresh; do not delete the ledger installation. |
| No capture | Enabled automation, correct trigger app, permissions and filters. Test the action manually, then a harmless event. For locked-only failures, check iOS execution options. |
| **Captured · 0 active** | Capture succeeded but there is no active format. Configure the sample before investigating retention. |
| **Untitled notification** | Bind Title to the notification's Title property and confirm the original event has a title. |
| **No text in selected field** | Check the selected property; Subtitle can be empty. For Message, choose Body. |
| **No EUR amount found** | Check Message → Body first, then the format's amount anchors. No guessed amount is posted. |
| Source unknown or account absent | Source app must exactly match the saved fixed label and map to an active account. |
| Identical values each time | Replace fixed sample text with dynamic properties; compare two events. |
| **Duplicate skipped** | Inspect diagnostics and Activity before manually adding a transaction. |
| Capture without transaction | Check activation, direction, amount, description and ambiguity/rejection reason. |
| Notification date fails | Leave it empty if no compatible Date property is available; capture time is the fallback. |

Device acceptance work is tracked in [issue #8](https://github.com/Natizh/EasyTrack/issues/8). Report only fictional examples and nonsensitive counts.
