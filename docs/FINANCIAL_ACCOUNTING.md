# Financial accounting policy

EasyTrack stores each real movement in integer currency minor units. The original transaction kind, amount, account, date, source and reimbursement links remain in the ledger. An expected refund is a receivable; it never creates an income transaction.

| Value | Definition |
| --- | --- |
| Income | Confirmed `income` and `reimbursement` movements with a known EUR value, on each movement's receipt date. A linked reimbursement appears once. |
| Gross Expenses | Actual `expense` movements with a known EUR value, at the expense date. Reimbursable and fully refunded expenses remain visible at their gross amount. |
| Net Expenses | The personal cost of expenses after refunds actually received. A planned refund alone does not reduce cost. |
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

## Dates and categories

Cash-flow Income, Gross Expenses and Net use each real movement's own date. For example, a €100 expense in December and a €40 reimbursement in January give December cash Net −€100 and January cash Net +€40. The January receipt is never moved into December's Income.

For personal-cost reports, a **linked** refund reduces the original expense's Net Expenses at that expense's original date. In the example, December Net Expenses becomes €60 after the January receipt. Category, merchant, daily spending and budgets use this same retrospective personal-cost attribution. This can revise a historical report when a refund is linked or unlinked. An unlinked reimbursement retains its separate negative personal-spending adjustment at its own receipt date until linked; the link removes that adjustment and applies it to the original expense. A write-off removes the outstanding receivable but does not create another expense: the unpaid cost was already included.

Home's Income, Expenses, Net Expenses, Net and PAC controls open Activity with the selected period and only movements used by the metric. Daily average opens its Net Expenses numerator and explains the elapsed-day divisor. Activity shows each movement's signed EUR contribution and the selected aggregate; where an expense has received refunds, it also distinguishes gross expense, received reimbursement and attributed personal cost. Search, details and export remain available. Chart selections use the same contribution semantics, including category, daily, monthly, merchant and trip selections. A monthly tap asks whether to inspect Income, Expenses or PAC because the horizontal position alone cannot identify the intended series. The optional pending-reimbursements widget shows all currently outstanding plans across dates; the period total in financial analytics attributes a plan to its original expense or advance date.

## Data compatibility

SQLite remains schema 13. On opening an older ledger, EasyTrack recalculates only the stored, derived personal-cost value for expenses with reimbursement plans. It does not change real amounts, dates, accounts, kinds, links, transaction revisions or operation history. New JSON backups use format 15. Valid format-14 backups are checksum-checked and converted to the new derived value before restore; older supported formats follow their existing versioned upgrades first. Replace and Merge still validate a disposable database and maintain their existing conflict rules. Exported CSV/XLSX rows keep original movement identity; their Income summaries include actual reimbursements.

Foreign-currency movements without a known EUR value remain visibly unconverted and are not assigned an invented EUR total. Linking a foreign-currency reimbursement still requires an explicit verified EUR value; integer-cent aggregation rejects overflow.
