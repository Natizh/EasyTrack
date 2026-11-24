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
    case reimbursementRequired, alreadyLinked, overpayment, accountMismatch
    case linkedReceiptRequiresUnlink

    var errorDescription: String? {
        switch self {
        case .expenseRequired: AppLanguage.localized("Expected reimbursement can be set only on an active expense or advance for others.")
        case .conversionRequired: AppLanguage.localized("A verified EUR value is required; no exchange rate was guessed.")
        case .invalidExpectedAmount: AppLanguage.localized("Expected reimbursement must be positive and no greater than the expense.")
        case .missingPlan: AppLanguage.localized("This expense has no expected reimbursement.")
        case .reimbursementRequired: AppLanguage.localized("Choose an active reimbursement transaction.")
        case .alreadyLinked: AppLanguage.localized("This reimbursement is already linked to an expense.")
        case .overpayment: AppLanguage.localized("The reimbursement exceeds the amount still expected.")
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
    let writtenOffEURMinor: Int64
    let outstandingEURMinor: Int64
    let linkedTransactionIDs: [UUID]
    let updatedAt: Date

    var title: String {
        if outstandingEURMinor > 0 && receivedEURMinor > 0 { return "Rimborso parziale" }
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
