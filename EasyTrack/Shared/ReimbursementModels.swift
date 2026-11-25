import Foundation

enum NewReimbursementAccountPolicy {
    static func isEligible(_ account: LocalAccount) -> Bool {
        account.archivedAt == nil && account.nativeCurrency == "EUR"
    }

    static func proposed(expenseAccountID: UUID?, accounts: [LocalAccount]) -> LocalAccount? {
        guard let expenseAccountID else { return nil }
        return accounts.first { $0.id == expenseAccountID && isEligible($0) }
    }
}

enum ReimbursementError: LocalizedError, Equatable {
    case expenseRequired, conversionRequired, invalidExpectedAmount, missingPlan
    case reimbursementRequired, alreadyLinked, accountMismatch
    case linkedReceiptRequiresUnlink

    var errorDescription: String? {
        switch self {
        case .expenseRequired: AppLanguage.localized("Expected reimbursement can be set only on an active expense or advance for others.")
        case .conversionRequired: AppLanguage.localized("A verified EUR value is required; no exchange rate was guessed.")
        case .invalidExpectedAmount: AppLanguage.localized("Expected reimbursement must be positive and compatible with the existing plan.")
        case .missingPlan: AppLanguage.localized("This expense has no expected reimbursement.")
        case .reimbursementRequired: AppLanguage.localized("Choose an active reimbursement transaction.")
        case .alreadyLinked: AppLanguage.localized("This reimbursement is already linked to an expense.")
        case .accountMismatch: AppLanguage.localized("The reimbursement account could not be reconciled.")
        case .linkedReceiptRequiresUnlink: AppLanguage.localized("Unlink this reimbursement before changing its amount, account, currency, or type.")
        }
    }
}

struct ExpenseReimbursementStatus: Equatable, Identifiable {
    var id: UUID { expenseID }
    let expenseID: UUID
    let expectedEURMinor: Int64
    let receivedEURMinor: Int64
    let attributedPrincipalEURMinor: Int64
    let surplusEarningsEURMinor: Int64
    let writtenOffEURMinor: Int64
    let outstandingEURMinor: Int64
    let linkedTransactionIDs: [UUID]
    let updatedAt: Date

    init(expenseID: UUID, expectedEURMinor: Int64, receivedEURMinor: Int64,
         writtenOffEURMinor: Int64, outstandingEURMinor: Int64,
         linkedTransactionIDs: [UUID], updatedAt: Date,
         attributedPrincipalEURMinor: Int64? = nil) {
        self.expenseID = expenseID
        self.expectedEURMinor = expectedEURMinor
        self.receivedEURMinor = receivedEURMinor
        self.attributedPrincipalEURMinor = attributedPrincipalEURMinor ?? receivedEURMinor
        self.surplusEarningsEURMinor = receivedEURMinor - self.attributedPrincipalEURMinor
        self.writtenOffEURMinor = writtenOffEURMinor
        self.outstandingEURMinor = outstandingEURMinor
        self.linkedTransactionIDs = linkedTransactionIDs
        self.updatedAt = updatedAt
    }

    /// Allocates real receipts in link order. The full cash amount remains on
    /// the receipt; only the portion up to the original gross amount reduces cost.
    func allocation(for reimbursementID: UUID, grossEURMinor: Int64,
                    transactions: [Transaction]) -> (principal: Int64, earnings: Int64)? {
        var remaining = max(0, grossEURMinor)
        for id in linkedTransactionIDs {
            guard let item = transactions.first(where: { $0.id == id }),
                  let amount = FinancialContributions.eurValue(of: item), amount >= 0 else { return nil }
            let principal = min(amount, remaining)
            if id == reimbursementID { return (principal, amount - principal) }
            remaining -= principal
        }
        return nil
    }

    var title: String {
        if receivedEURMinor >= expectedEURMinor { return "Rimborsato" }
        if receivedEURMinor > 0 { return "Rimborso parziale" }
        if outstandingEURMinor > 0 { return "Rimborso in attesa" }
        if writtenOffEURMinor > 0 { return "Non rimborsato" }
        return "Rimborsato"
    }
}

struct ExpenseReimbursementLink: Equatable {
    let expenseID: UUID
    let reimbursementID: UUID
    let amountEURMinor: Int64
    let createdAt: Date
}

enum ReimbursementTotals {
    static func pending(_ statuses: [ExpenseReimbursementStatus]) throws -> Int64 {
        var total: Int64 = 0
        for status in statuses {
            guard status.outstandingEURMinor >= 0 else { throw ReimbursementError.invalidExpectedAmount }
            let (next, overflow) = total.addingReportingOverflow(status.outstandingEURMinor)
            guard !overflow else { throw FinancialAnalyticsError.amountOverflow }
            total = next
        }
        return total
    }
}
