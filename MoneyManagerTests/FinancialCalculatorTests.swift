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
        let backup = Backup(accounts: [], categories: [], transactions: [], settings: settings, rateData: rate)
        let decoded = try JSONDecoder().decode(Backup.self, from: JSONEncoder().encode(backup))
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.settings, settings)
        XCTAssertEqual(decoded.rateData, rate)

        let old = try JSONEncoder().encode(Backup(version: 1, accounts: [], categories: [], transactions: []))
        let oldDecoded = try JSONDecoder().decode(Backup.self, from: old)
        XCTAssertNil(oldDecoded.settings)
        XCTAssertNil(oldDecoded.rateData)
    }

    private func account(_ context: NSManagedObjectContext, currency: String, openingBalance: Decimal = 0) -> Account {
        let account = Account(context: context)
        account.id = UUID(); account.name = "Account"; account.kind = "Checking"; account.currencyCode = currency; account.openingBalance = NSDecimalNumber(decimal: openingBalance); account.createdAt = Date()
        return account
    }

    private func transaction(_ context: NSManagedObjectContext, account: Account, amount: Decimal, kind: TransactionKind) -> FinancialTransaction {
        let transaction = FinancialTransaction(context: context)
        transaction.id = UUID(); transaction.account = account; transaction.date = Date(); transaction.amount = NSDecimalNumber(decimal: amount); transaction.kind = kind.rawValue
        return transaction
    }
}
