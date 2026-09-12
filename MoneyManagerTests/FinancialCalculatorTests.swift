import XCTest
@testable import MoneyManager

final class FinancialCalculatorTests: XCTestCase {
    func testBalanceUsesTransactionHistory() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let account = Account(context: context)
        account.id = UUID()
        account.name = "Checking"
        account.kind = "Checking"
        account.currencyCode = "USD"
        account.openingBalance = 10
        account.createdAt = Date()
        let transaction = FinancialTransaction(context: context)
        transaction.id = UUID()
        transaction.account = account
        transaction.date = Date()
        transaction.amount = -3.25
        transaction.kind = TransactionKind.expense.rawValue

        XCTAssertEqual(FinancialCalculator.balance(account: account, transactions: [transaction]), Decimal(string: "6.75"))
    }

    func testCashFlowExcludesTransfers() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let account = Account(context: context)
        account.id = UUID()
        account.name = "Checking"
        account.kind = "Checking"
        account.currencyCode = "USD"
        account.openingBalance = 0
        account.createdAt = Date()
        let income = FinancialTransaction(context: context)
        income.id = UUID()
        income.account = account
        income.date = Date()
        income.amount = 100
        income.kind = TransactionKind.income.rawValue
        let transfer = FinancialTransaction(context: context)
        transfer.id = UUID()
        transfer.account = account
        transfer.date = Date()
        transfer.amount = -40
        transfer.kind = TransactionKind.transfer.rawValue

        let flow = FinancialCalculator.cashFlow([income, transfer])

        XCTAssertEqual(flow.income, 100)
        XCTAssertEqual(flow.expense, 0)
    }
}
