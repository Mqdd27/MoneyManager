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

    func testCurrencyCatalogAndFormatterUseCurrencyFractionDigits() {
        XCTAssertEqual(CurrencyFormatter.supportedCodes.prefix(4), ["IDR", "USD", "SGD", "CNY"])
        XCTAssertEqual(CurrencyFormatter.definition(for: "IDR").fractionDigits, 0)
        XCTAssertEqual(CurrencyFormatter.definition(for: "USD").fractionDigits, 2)
        XCTAssertEqual(CurrencyFormatter.definition(for: "SGD").fractionDigits, 2)
        XCTAssertEqual(CurrencyFormatter.definition(for: "CNY").fractionDigits, 2)
        XCTAssertEqual(CurrencyFormatter.normalizedCode(nil), "IDR")
        XCTAssertEqual(CurrencyFormatter.normalizedCode("EUR"), "EUR")
        XCTAssertEqual(CurrencyFormatter.normalizedCode("invalid"), "IDR")
    }

    func testDecimalInputParserSupportsDotAndCommaWithoutFloatingPoint() {
        XCTAssertEqual(DecimalInputParser.parse("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(DecimalInputParser.parse("1.234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(DecimalInputParser.parse("0,10"), Decimal(string: "0.10"))
        XCTAssertNil(DecimalInputParser.parse(""))
    }

    func testGenericExchangeRatePairsConvertBothDirectionsWithoutSeedRates() {
        let defaults = UserDefaults(suiteName: "GenericRatePairs")!
        defaults.removePersistentDomain(forName: "GenericRatePairs")
        let rates = ExchangeRateService(defaults: defaults)
        XCTAssertTrue(rates.pairs.isEmpty)
        rates.setRate(from: "USD", to: "SGD", rate: Decimal(string: "1.35"), source: "Manual")
        XCTAssertEqual(rates.convert(2, from: "USD", to: "SGD"), Decimal(string: "2.70"))
        XCTAssertEqual(rates.convert(Decimal(string: "2.70")!, from: "SGD", to: "USD"), 2)
    }

    func testExchangeRatePairsUseIDRPivot() {
        let defaults = UserDefaults(suiteName: "PivotRates")!
        defaults.removePersistentDomain(forName: "PivotRates")
        let rates = ExchangeRateService(defaults: defaults)
        rates.setRate(from: "SGD", to: "IDR", rate: 12000)
        rates.setRate(from: "CNY", to: "IDR", rate: 3000)
        XCTAssertEqual(rates.convert(2, from: "SGD", to: "CNY"), 8)
    }

    func testMultiCurrencyNetWorthUsesIDRPivotRates() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let accounts = [account(context, currency: "IDR", openingBalance: 1000), account(context, currency: "USD", openingBalance: 1), account(context, currency: "SGD", openingBalance: 1), account(context, currency: "CNY", openingBalance: 1)]
        let defaults = UserDefaults(suiteName: "MultiCurrencyNetWorth")!
        defaults.removePersistentDomain(forName: "MultiCurrencyNetWorth")
        let rates = ExchangeRateService(defaults: defaults)
        rates.setRate(from: "USD", to: "IDR", rate: 15000); rates.setRate(from: "SGD", to: "IDR", rate: 12000); rates.setRate(from: "CNY", to: "IDR", rate: 2200)
        XCTAssertEqual(FinancialCalculator.netWorth(accounts: accounts, transactions: [], currencyCode: "IDR", rates: rates), 30200)
    }

    func testDecimalNSDecimalNumberRoundTripForSGDAndCNY() {
        let value = Decimal(string: "8.64")!
        XCTAssertEqual(NSDecimalNumber(decimal: value).decimalValue, value)
        XCTAssertEqual(DecimalInputParser.parse("8,64"), value)
    }

    func testAccountEditKeepsIDAndTransactionsAndBlocksCurrencyChange() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let account = account(context, currency: "SGD", openingBalance: 1), id = account.id
        let record = transaction(context, account: account, amount: 8.64, kind: .income)
        account.name = "Edited"; account.openingBalance = NSDecimalNumber(decimal: Decimal(string: "8.64")!); try context.save()
        XCTAssertEqual(account.id, id); XCTAssertEqual(record.account, account)
        XCTAssertFalse(AccountEditing.canChangeCurrency(account: account, transactions: [record]))
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
        XCTAssertEqual(decoded.version, 3)
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

    func testInvestmentPositionUsesMovingAverageCostAndQuote() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let account = account(context, currency: "USD")
        let buy = transaction(context, account: account, amount: -100, kind: .investmentBuy); buy.investmentSymbol = "ABC"; buy.investmentQuantity = 10
        let sell = transaction(context, account: account, amount: 60, kind: .investmentSell); sell.investmentSymbol = "ABC"; sell.investmentQuantity = 5
        let quote = MarketQuote(context: context); quote.id = UUID(); quote.symbol = "ABC"; quote.currencyCode = "USD"; quote.price = 15; quote.updatedAt = Date(); quote.source = "Manual"
        let position = FinancialCalculator.investmentPositions([buy, sell], quotes: [quote]).first!
        XCTAssertEqual(position.quantity, 5); XCTAssertEqual(position.remainingCost, 50); XCTAssertEqual(position.averageCost, 10); XCTAssertEqual(position.realizedProfitLoss, 10); XCTAssertEqual(position.marketValue, 75); XCTAssertEqual(position.unrealizedProfitLoss, 25)
    }

    func testNetWorthSnapshotDoesNotChangeWithLaterQuotes() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let result = NetWorthResult(cash: 10, investments: 20, unconvertibleCount: 0)
        NetWorthSnapshotService.save(result, currencyCode: "USD", in: context)
        let snapshots = try context.fetch(NSFetchRequest<NetWorthSnapshot>(entityName: "NetWorthSnapshot"))
        XCTAssertEqual(snapshots.first?.totalValue.decimalValue, 30)
        NetWorthSnapshotService.save(NetWorthResult(cash: 11, investments: 21, unconvertibleCount: 0), currencyCode: "USD", in: context)
        XCTAssertEqual(try context.count(for: NSFetchRequest<NetWorthSnapshot>(entityName: "NetWorthSnapshot")), 1)
        XCTAssertEqual(snapshots.first?.totalValue.decimalValue, 32)
    }

    func testNetWorthExcludesInvestmentCashMovement() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let account = account(context, currency: "USD", openingBalance: 100)
        let buy = transaction(context, account: account, amount: -100, kind: .investmentBuy); buy.investmentSymbol = "ABC"; buy.investmentQuantity = 10
        let quote = MarketQuote(context: context); quote.id = UUID(); quote.symbol = "ABC"; quote.currencyCode = "USD"; quote.price = 12; quote.updatedAt = Date(); quote.source = "Manual"; quote.assetType = "Equity"; quote.isManual = true
        let result = FinancialCalculator.netWorthResult(accounts: [account], transactions: [buy], quotes: [quote], currencyCode: "USD")
        XCTAssertEqual(FinancialCalculator.balance(account: account, transactions: [buy]), 0)
        XCTAssertEqual(result.cash, 100); XCTAssertEqual(result.investments, 120); XCTAssertEqual(result.total, 220)
    }

    func testMultiCurrencyReportingAndPersistence() {
        let defaults = UserDefaults(suiteName: "ReportingPersistence")!
        defaults.removePersistentDomain(forName: "ReportingPersistence")
        let settings = ReportingSettings(baseCurrency: "SGD", secondaryCurrency: "IDR")
        settings.save(defaults: defaults)
        let loaded = ReportingSettings.current(defaults: defaults)
        XCTAssertEqual(loaded.baseCurrency, "SGD")
        XCTAssertEqual(loaded.secondaryCurrency, "IDR")

        let context = PersistenceController(inMemory: true).container.viewContext
        let idrAcc = account(context, currency: "IDR", openingBalance: 5000000)
        let usdAcc = account(context, currency: "USD", openingBalance: 100)
        let sgdAcc = account(context, currency: "SGD", openingBalance: 50)

        let rates = ExchangeRateService(defaults: defaults)
        rates.setRate(from: "USD", to: "IDR", rate: 16000)
        rates.setRate(from: "SGD", to: "IDR", rate: 12000)

        let idrResult = FinancialCalculator.netWorthResult(accounts: [idrAcc, usdAcc, sgdAcc], transactions: [], quotes: [], currencyCode: "IDR", rates: rates)
        XCTAssertEqual(idrResult.total, 7200000)

        let usdResult = FinancialCalculator.netWorthResult(accounts: [idrAcc, usdAcc, sgdAcc], transactions: [], quotes: [], currencyCode: "USD", rates: rates)
        XCTAssertEqual(usdResult.total, 450)

        let sgdResult = FinancialCalculator.netWorthResult(accounts: [idrAcc, usdAcc, sgdAcc], transactions: [], quotes: [], currencyCode: "SGD", rates: rates)
        XCTAssertEqual(sgdResult.total, 600)

        XCTAssertEqual(idrAcc.openingBalance, 5000000)
        XCTAssertEqual(usdAcc.openingBalance, 100)
        XCTAssertEqual(sgdAcc.openingBalance, 50)
    }

    func testMissingSGDRateExcludesUnconvertibleAccount() {
        let defaults = UserDefaults(suiteName: "MissingRateTest")!
        defaults.removePersistentDomain(forName: "MissingRateTest")
        let context = PersistenceController(inMemory: true).container.viewContext
        let idrAcc = account(context, currency: "IDR", openingBalance: 5000000)
        let usdAcc = account(context, currency: "USD", openingBalance: 100)
        let sgdAcc = account(context, currency: "SGD", openingBalance: 50)

        let rates = ExchangeRateService(defaults: defaults)
        rates.setRate(from: "USD", to: "IDR", rate: 16000)

        let result = FinancialCalculator.netWorthResult(accounts: [idrAcc, usdAcc, sgdAcc], transactions: [], quotes: [], currencyCode: "IDR", rates: rates)
        XCTAssertGreaterThan(result.unconvertibleCount, 0)
        XCTAssertEqual(result.total, 6600000)
    }

    func testFrankfurterResponseDecodesToDecimal() throws {
        let integer = try JSONDecoder().decode(FrankfurterRate.self, from: Data("{\"date\":\"2026-09-14\",\"base\":\"USD\",\"quote\":\"IDR\",\"rate\":17627}".utf8))
        XCTAssertEqual(integer.rate, Decimal(17627))
        XCTAssertEqual(integer.base, "USD"); XCTAssertEqual(integer.quote, "IDR")
        let fractional = try JSONDecoder().decode(FrankfurterRate.self, from: Data("{\"date\":\"2026-09-14\",\"base\":\"CNY\",\"quote\":\"IDR\",\"rate\":2628.35}".utf8))
        XCTAssertEqual(fractional.rate, Decimal(string: "2628.35"))
    }

    func testAutomaticRefreshStoresFrankfurterPairs() {
        let mock = MockRateProvider(responses: ["USD/IDR": frankfurterRate(base: "USD", quote: "IDR", rate: 17627)])
        let defaults = UserDefaults(suiteName: "AutoRefresh")!
        defaults.removePersistentDomain(forName: "AutoRefresh")
        let rates = ExchangeRateService(defaults: defaults, provider: mock)
        let expectation = XCTestExpectation(description: "refresh")
        rates.refreshRatesIfNeeded(nativeCurrencies: ["USD"]) { updated in
            XCTAssertTrue(updated)
            XCTAssertEqual(rates.convert(2, from: "USD", to: "IDR"), 35254)
            XCTAssertEqual(rates.pairs.first?.source, "Frankfurter")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func testStaleRatesRefreshWhileFreshOnesAreSkipped() {
        let mock = MockRateProvider(responses: ["SGD/IDR": frankfurterRate(base: "SGD", quote: "IDR", rate: 13902)])
        let defaults = UserDefaults(suiteName: "StaleRefresh")!
        defaults.removePersistentDomain(forName: "StaleRefresh")
        let rates = ExchangeRateService(defaults: defaults, provider: mock)
        rates.setRate(from: "USD", to: "IDR", rate: 17627, source: "Frankfurter", updatedAt: Date())
        rates.setRate(from: "SGD", to: "IDR", rate: 12000, source: "Frankfurter", updatedAt: Date(timeIntervalSinceNow: -100000))
        let expectation = XCTestExpectation(description: "refresh")
        rates.refreshRatesIfNeeded(nativeCurrencies: ["USD", "SGD"]) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(mock.requested, ["SGD/IDR"])
        XCTAssertEqual(rates.convert(1, from: "SGD", to: "IDR"), 13902)
    }

    func testManualOverrideIsNeverAutoRefreshed() {
        let mock = MockRateProvider(responses: ["USD/IDR": frankfurterRate(base: "USD", quote: "IDR", rate: 17627)])
        let defaults = UserDefaults(suiteName: "ManualOverride")!
        defaults.removePersistentDomain(forName: "ManualOverride")
        let rates = ExchangeRateService(defaults: defaults, provider: mock)
        rates.setManualOverride(from: "USD", to: "IDR", rate: 15000)
        let expectation = XCTestExpectation(description: "refresh")
        rates.refreshRatesIfNeeded(nativeCurrencies: ["USD"], force: true) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
        XCTAssertTrue(mock.requested.isEmpty)
        XCTAssertEqual(rates.convert(1, from: "USD", to: "IDR"), 15000)
        rates.clearManualOverride(from: "USD", to: "IDR")
        XCTAssertNil(rates.convert(1, from: "USD", to: "IDR"))
    }

    func testOfflineFailureFallsBackToCachedRate() {
        let mock = MockRateProvider(responses: [:])
        let defaults = UserDefaults(suiteName: "OfflineFallback")!
        defaults.removePersistentDomain(forName: "OfflineFallback")
        let rates = ExchangeRateService(defaults: defaults, provider: mock)
        rates.setRate(from: "USD", to: "IDR", rate: 17627, source: "Frankfurter", updatedAt: Date(timeIntervalSinceNow: -100000))
        let expectation = XCTestExpectation(description: "refresh")
        rates.refreshRatesIfNeeded(nativeCurrencies: ["USD"], force: true) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(rates.convert(1, from: "USD", to: "IDR"), 17627)
    }

    func testRefreshFetchesReportingCurrencyPairForNonNativeReporting() {
        let mock = MockRateProvider(responses: [
            "EUR/IDR": frankfurterRate(base: "EUR", quote: "IDR", rate: 17000),
            "USD/IDR": frankfurterRate(base: "USD", quote: "IDR", rate: 16000)
        ])
        let defaults = UserDefaults(suiteName: "ReportingPairFetch")!
        defaults.removePersistentDomain(forName: "ReportingPairFetch")
        let rates = ExchangeRateService(defaults: defaults, provider: mock)
        let expectation = XCTestExpectation(description: "refresh")
        rates.refreshRatesIfNeeded(nativeCurrencies: ["IDR", "EUR"], reportingCurrency: "USD") { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
        XCTAssertTrue(mock.requested.contains("EUR/IDR"))
        XCTAssertTrue(mock.requested.contains("USD/IDR"))
        XCTAssertEqual(rates.convert(2, from: "EUR", to: "USD"), Decimal(string: "2.125"))
    }

    func testCrossConversionSGDToUSDThroughIDR() {
        let defaults = UserDefaults(suiteName: "CrossConvert")!
        defaults.removePersistentDomain(forName: "CrossConvert")
        let rates = ExchangeRateService(defaults: defaults)
        rates.setRate(from: "USD", to: "IDR", rate: 16000, source: "Frankfurter")
        rates.setRate(from: "SGD", to: "IDR", rate: 12000, source: "Frankfurter")
        XCTAssertEqual(rates.convert(2, from: "SGD", to: "USD"), Decimal(string: "1.5"))
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

final class MockRateProvider: ExchangeRateProvider {
    var responses: [String: FrankfurterRate]
    private(set) var requested: [String] = []
    init(responses: [String: FrankfurterRate]) { self.responses = responses }
    func fetchRate(from: String, to: String, completion: @escaping (Result<FrankfurterRate, Error>) -> Void) {
        let key = "\(from.uppercased())/\(to.uppercased())"
        requested.append(key)
        if let rate = responses[key] { completion(.success(rate)) }
        else { completion(.failure(URLError(.badServerResponse))) }
    }
}

func frankfurterRate(base: String, quote: String, rate: Decimal) -> FrankfurterRate {
    FrankfurterRate(date: "2026-09-14", base: base, quote: quote, rate: rate)
}
