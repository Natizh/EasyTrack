# Financial accounting policy

[EasyTrack](../../README.md) · [Documentation](README.md) · English / [Italiano](../it/FINANCIAL_ACCOUNTING.md)

EasyTrack stores each real movement in integer currency minor units. The original transaction kind, amount, account, date, source and reimbursement links remain in the ledger. An expected refund is a receivable; it never creates an income transaction.

| Value | Definition |
| --- | --- |
| Income | Confirmed `income` and `reimbursement` movements with a known EUR value, on each movement's receipt date. A linked reimbursement appears once at its full received amount, including any surplus earnings. |
| Gross Expenses | Actual `expense` movements with a known EUR value, at the expense date. Reimbursable and fully refunded expenses remain visible at their gross amount. |
| Net Expenses | The personal cost of expenses after refunds actually received. A planned refund alone does not reduce cost. Linked receipts reduce the original expense by at most its gross EUR value; surplus cannot turn that expense negative. |
| Net | Income minus Gross Expenses. Reimbursements already included in Income are never subtracted again. |
| Pending Reimbursements | The outstanding portion of an explicitly expected refund, after linked receipts and any written-off amount. It is not cash or income. |

PAC investments, advances paid for others, deposits and deposit returns keep their separate transaction kinds. They do not silently become ordinary Income or Gross Expenses. An advance can still have a pending receivable and a personal cost if part is written off. Transfers are not inferred from two unrelated movements.

## Examples

| Movements | Income | Gross Expenses | Net Expenses | Net | Pending |
| --- | ---: | ---: | ---: | ---: | ---: |
| €1,000 income; €600 expense | €1,000 | €600 | €600 | €400 | €0 |
| €100 expense; €100 expected, nothing received | €0 | €100 | €100 | −€100 | €100 |
| Same expense; €40 actually received and linked | €40 | €100 | €60 | −€60 | €60 |
| Same expense; remaining €60 received and linked | €100 | €100 | €0 | €0 | €0 |
| €1,000 ordinary income; €300 expenses, including a fully refunded €100 expense | €1,100 | €300 | €200 | €800 | €0 |
| €17 expense; €18 reimbursement received | €18 | €17 | €0 | €1 | €0 |

## Dates and categories

Cash-flow Income, Gross Expenses and Net use each real movement's own date. For example, a €100 expense in December and a €40 reimbursement in January give December cash Net −€100 and January cash Net +€40. The January receipt is never moved into December's Income.

For personal-cost reports, a **linked** refund reduces the original expense's Net Expenses at that expense's original date. In the example, December Net Expenses becomes €60 after the January receipt. Category, merchant, daily spending and budgets use this same retrospective personal-cost attribution. This can revise a historical report when a refund is linked or unlinked. An unlinked reimbursement retains its separate negative personal-spending adjustment at its own receipt date until linked; the link removes that adjustment and applies it to the original expense. A write-off removes the outstanding receivable but does not create another expense: the unpaid cost was already included.

An explicitly expected reimbursement may exceed the original expense. Real linked receipts keep their full cash amount, date, account and identity. The **attributed principal** is the smaller of gross expense and total linked receipts; any excess is **additional earnings** within those same receipt movements. For €17 spent and €18 received, €17 reduces the original expense's personal cost to zero and €1 is surplus earnings. Income is €18 once, Gross Expenses remains €17, and cash Net is +€1. With multiple receipts, allocation follows link order so each receipt's reimbursed portion and surplus can be shown without creating synthetic transactions. If a receipt is unlinked, edited or deleted, the derived allocation is recalculated from the remaining real links. Expected but unpaid amounts remain outside Income.

Home's Income, Expenses, Net Expenses, Net and PAC controls open Activity with the selected period and only movements used by the metric. Daily average opens its Net Expenses numerator and explains the elapsed-day divisor. Activity shows each movement's signed EUR contribution and the selected aggregate; where an expense has received refunds, it also distinguishes gross expense, received reimbursement and attributed personal cost. Search, details and export remain available. Chart selections use the same contribution semantics, including category, daily, monthly, merchant and trip selections. A monthly tap asks whether to inspect Income, Expenses or PAC because the horizontal position alone cannot identify the intended series. The optional pending-reimbursements widget shows all currently outstanding plans across dates; the period total in financial analytics attributes a plan to its original expense or advance date.

## Data compatibility

SQLite remains schema 13. On opening an older ledger, EasyTrack recalculates only the stored, derived personal-cost value for expenses with reimbursement plans. It does not change real amounts, dates, accounts, kinds, links, transaction revisions or operation history. New JSON backups use format 15. Valid format-14 backups are checksum-checked and converted to the new derived value before restore; older supported formats follow their existing versioned upgrades first. Replace and Merge still validate a disposable database and maintain their existing conflict rules. Exported CSV/XLSX rows keep original movement identity; their Income summaries include actual reimbursements.

The surplus policy changes no SQLite table or JSON backup shape. The existing link amount still equals the full real receipt amount. Principal and earnings are derived from the verified original gross amount and linked receipt total. Format-15 backup validation accepts an expected or received amount above gross, checks the nonnegative personal-cost cap and outstanding amount, then verifies the unchanged receipt/link identities. Older format-14 files retain their original stricter validation before conversion. CSV/XLSX exports keep one row per real receipt and the existing machine-readable columns; their Income totals include the full receipt and their personal-spending totals use the capped attributed cost.

Foreign-currency movements without a known EUR value remain visibly unconverted and are not assigned an invented EUR total. Linking a foreign-currency reimbursement still requires an explicit verified EUR value; integer-cent aggregation rejects overflow.
