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
        case .expenseRequired: "Expected reimbursement can be set only on an active expense or advance for others."
        case .conversionRequired: "A verified EUR value is required; no exchange rate was guessed."
        case .invalidExpectedAmount: "Expected reimbursement must be positive and no greater than the expense."
        case .missingPlan: "This expense has no expected reimbursement."
        case .reimbursementRequired: "Choose an active reimbursement transaction."
        case .alreadyLinked: "This reimbursement is already linked to an expense."
        case .overpayment: "The reimbursement exceeds the amount still expected."
        case .accountMismatch: "The reimbursement account could not be reconciled."
        case .linkedReceiptRequiresUnlink: "Unlink this reimbursement before changing its amount, account, currency, or type."
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
