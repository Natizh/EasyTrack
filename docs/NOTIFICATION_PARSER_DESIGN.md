# Future notification parser builder

The parser setup should feel like a Shortcuts workflow: a small, rearrangeable block pipeline with immediate feedback:

**Notification input → amount extraction → merchant extraction → account mapping → category rule → duplicate detection → transaction creation**

After the first notification from a source, open a source-specific builder with the raw event visible. Highlight the proposed amount, currency, merchant, date, account, and transaction type in the text. Tapping a highlight edits its rule or mapping. A live preview shows the resulting transaction and explains which block supplied each field. Additional sample notifications can test alternative formats before a rule is enabled. Multiple rules can coexist for one source.

Keep the original event and parser version for diagnostics and retries. Duplicate detection needs a source-specific stable fingerprint and must stay separate from historical import identity. Create a transaction only when required fields are known; otherwise keep the event on its source page with a retry or prefilled-create action. Every created transaction remains editable from its detail screen. There is no general review inbox. Parsing runs on-device without paid AI or a server. This note describes a future milestone; the current App Intent only saves diagnostic events.
