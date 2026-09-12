import XCTest
import CoreData
@testable import MoneyManager

final class FinancialCalculatorTests: XCTestCase {
    func testFormattingUsesExactIDRAndUSDOutput() {
        XCTAssertEqual(CurrencyFormatter.string(Decimal(string: "1250000")!, code: "IDR"), "Rp1.250.000")
        XCTAssertEqual(CurrencyFormatter.string(Decimal(string: "1234.5")!, code: "USD"), "$1,234.50")
    }

    func testCurrencyConversionUsesManualUSDIDRRate() {
        let defaults = UserDefaults(suiteName: "ExchangeRateServiceTests")!
        defaults.removePersistentDomain(forName: "ExchangeRateServiceTests")
        let rates = ExchangeRateService(defaults: defaults)
        rates.setUSDIDRRate(Decimal(string: "15000")!, source: "Manual")

        XCTAssertEqual(rates.convert(2, from: "USD", to: "IDR"), 30000)
        XCTAssertEqual(rates.convert(30000, from: "IDR", to: "USD"), 2)
        XCTAssertEqual(rates.data.source, "Manual")
    }

    func testCurrencyMigrationDefaultsInvalidCodeToIDR() {
        XCTAssertEqual(CurrencyFormatter.normalizedCode(nil), "IDR")
        XCTAssertEqual(CurrencyFormatter.normalizedCode("EUR"), "IDR")
        XCTAssertEqual(CurrencyFormatter.normalizedCode("invalid"), "IDR")
    }

    func testCashFlowConvertsAccountCurrencies() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let usd = account(context, currency: "USD")
        let idr = account(context, currency: "IDR")
        let income = transaction(context, account: usd, amount: 2, kind: .income)
        let expense = transaction(context, account: idr, amount: -15000, kind: .expense)
        let defaults = UserDefaults(suiteName: "CashFlowRates")!
        defaults.removePersistentDomain(forName: "CashFlowRates")
        let rates = ExchangeRateService(defaults: defaults)
        rates.setUSDIDRRate(15000)

        let flow = FinancialCalculator.cashFlow([income, expense], currencyCode: "USD", rates: rates)
        XCTAssertEqual(flow.income, 2)
        XCTAssertEqual(flow.expense, 1)
    }

    func testNetWorthConvertsMultipleAccountCurrencies() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let usd = account(context, currency: "USD", openingBalance: 2)
        let idr = account(context, currency: "IDR", openingBalance: 15000)
        let defaults = UserDefaults(suiteName: "NetWorthRates")!
        defaults.removePersistentDomain(forName: "NetWorthRates")
        let rates = ExchangeRateService(defaults: defaults)
        rates.setUSDIDRRate(15000)

        XCTAssertEqual(FinancialCalculator.netWorth(accounts: [usd, idr], transactions: [], currencyCode: "USD", rates: rates), 3)
    }

    func testBackupDTOPreservesSettingsAndRateDataAndReadsOldBackup() throws {
        let settings = ReportingSettings(baseCurrency: "USD", secondaryCurrency: "IDR")
        let rate = ExchangeRateData(usdIDR: 15000, source: "Manual", lastUpdated: Date(timeIntervalSince1970: 0))
        let accountID = UUID(), categoryID = UUID()
        let backup = Backup(accounts: [BackupAccount(id: accountID, name: "Demo", kind: "Checking", currencyCode: "USD", openingBalance: 1, createdAt: Date(), isDemoData: true)], categories: [BackupCategory(id: categoryID, name: "Demo", kind: "expense", isDemoData: true)], transactions: [BackupTransaction(id: UUID(), date: Date(), amount: -1, note: nil, kind: "expense", transferID: nil, investmentSymbol: nil, investmentQuantity: nil, accountID: accountID, categoryID: categoryID, isDemoData: true)], settings: settings, rateData: rate)
        let decoded = try JSONDecoder().decode(Backup.self, from: JSONEncoder().encode(backup))
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.settings, settings)
        XCTAssertEqual(decoded.rateData, rate)
        XCTAssertTrue(decoded.accounts[0].isDemoData)
        XCTAssertTrue(decoded.categories[0].isDemoData)
        XCTAssertTrue(decoded.transactions[0].isDemoData)
        XCTAssertFalse(try JSONDecoder().decode(BackupAccount.self, from: Data("{\"id\":\"\(UUID())\",\"name\":\"Account\",\"kind\":\"Checking\",\"openingBalance\":0,\"createdAt\":0}".utf8)).isDemoData)
        XCTAssertFalse(try JSONDecoder().decode(BackupCategory.self, from: Data("{\"id\":\"\(UUID())\",\"name\":\"Category\",\"kind\":\"expense\"}".utf8)).isDemoData)
        XCTAssertFalse(try JSONDecoder().decode(BackupTransaction.self, from: Data("{\"id\":\"\(UUID())\",\"date\":0,\"amount\":0,\"kind\":\"expense\",\"accountID\":\"\(accountID)\"}".utf8)).isDemoData)

        let old = try JSONEncoder().encode(Backup(version: 1, accounts: [], categories: [], transactions: []))
        let oldDecoded = try JSONDecoder().decode(Backup.self, from: old)
        XCTAssertNil(oldDecoded.settings)
        XCTAssertNil(oldDecoded.rateData)
    }

    func testDemoDataLoadIsIdempotentAndKeepsRelationships() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        try DemoDataService.load(in: context)
        try DemoDataService.load(in: context)

        let accounts = try context.fetch(NSFetchRequest<Account>(entityName: "Account"))
        let categories = try context.fetch(NSFetchRequest<MoneyManager.Category>(entityName: "Category"))
        let transactions = try context.fetch(NSFetchRequest<FinancialTransaction>(entityName: "Transaction"))
        XCTAssertEqual(accounts.filter(\.isDemoData).count, 1)
        XCTAssertEqual(categories.filter(\.isDemoData).count, 2)
        XCTAssertEqual(transactions.filter(\.isDemoData).count, 2)
        XCTAssertTrue(transactions.allSatisfy { $0.account.isDemoData && $0.category?.isDemoData == true })
    }

    func testRemovingDemoDataPreservesRealRecordsAndCalculation() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let realAccount = account(context, currency: "USD", openingBalance: 100)
        let realCategory = category(context, name: "Real", kind: .income)
        let realTransaction = transaction(context, account: realAccount, amount: 25, kind: .income)
        realTransaction.category = realCategory
        try context.save()
        try DemoDataService.load(in: context)

        try DemoDataService.remove(in: context)
        let accounts = try context.fetch(NSFetchRequest<Account>(entityName: "Account"))
        let categories = try context.fetch(NSFetchRequest<MoneyManager.Category>(entityName: "Category"))
        let transactions = try context.fetch(NSFetchRequest<FinancialTransaction>(entityName: "Transaction"))
        XCTAssertEqual(accounts.map(\.id), [realAccount.id])
        XCTAssertEqual(categories.map(\.id), [realCategory.id])
        XCTAssertEqual(transactions.map(\.id), [realTransaction.id])
        XCTAssertEqual(FinancialCalculator.balance(account: realAccount, transactions: transactions), 125)
    }

    func testRemovingDemoDataPreservesDemoParentsUsedByRealTransactions() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        try DemoDataService.load(in: context)
        let demoTransaction = try context.fetch(NSFetchRequest<FinancialTransaction>(entityName: "Transaction")).first!
        let demoAccount = demoTransaction.account
        let demoCategory = demoTransaction.category!
        let realTransaction = transaction(context, account: demoAccount, amount: 10, kind: .income)
        realTransaction.category = demoCategory
        try context.save()

        try DemoDataService.remove(in: context)
        XCTAssertFalse(demoAccount.isDeleted)
        XCTAssertFalse(demoCategory.isDeleted)
        XCTAssertFalse(realTransaction.isDeleted)
    }

    func testResetAllDataDeletesEveryFinancialRecord() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let realAccount = account(context, currency: "USD")
        let realCategory = category(context, name: "Real", kind: .expense)
        let realTransaction = transaction(context, account: realAccount, amount: -1, kind: .expense)
        realTransaction.category = realCategory
        try context.save()
        try DemoDataService.load(in: context)

        try DemoDataService.reset(in: context)
        XCTAssertEqual(try context.count(for: NSFetchRequest<Account>(entityName: "Account")), 0)
        XCTAssertEqual(try context.count(for: NSFetchRequest<MoneyManager.Category>(entityName: "Category")), 0)
        XCTAssertEqual(try context.count(for: NSFetchRequest<FinancialTransaction>(entityName: "Transaction")), 0)
    }

    private func account(_ context: NSManagedObjectContext, currency: String, openingBalance: Decimal = 0) -> Account {
        let account = Account(context: context)
        account.id = UUID(); account.name = "Account"; account.kind = "Checking"; account.currencyCode = currency; account.openingBalance = NSDecimalNumber(decimal: openingBalance); account.createdAt = Date()
        return account
    }

    private func category(_ context: NSManagedObjectContext, name: String, kind: TransactionKind) -> MoneyManager.Category {
        let category = MoneyManager.Category(context: context)
        category.id = UUID(); category.name = name; category.kind = kind.rawValue
        return category
    }

    private func transaction(_ context: NSManagedObjectContext, account: Account, amount: Decimal, kind: TransactionKind) -> FinancialTransaction {
        let transaction = FinancialTransaction(context: context)
        transaction.id = UUID(); transaction.account = account; transaction.date = Date(); transaction.amount = NSDecimalNumber(decimal: amount); transaction.kind = kind.rawValue
        return transaction
    }
}
