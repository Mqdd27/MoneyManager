import SwiftUI
import CoreData
import LocalAuthentication
import UniformTypeIdentifiers
import UIKit

@main
struct MoneyManagerApp: App {
    let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}

final class PersistenceController {
    static let shared = PersistenceController()
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = NSManagedObjectModel()
        let account = NSEntityDescription()
        account.name = "Account"
        account.managedObjectClassName = NSStringFromClass(Account.self)
        account.properties = [Self.attribute("id", .UUIDAttributeType), Self.attribute("name", .stringAttributeType), Self.attribute("kind", .stringAttributeType), Self.attribute("currencyCode", .stringAttributeType), Self.attribute("openingBalance", .decimalAttributeType), Self.attribute("createdAt", .dateAttributeType)]
        let category = NSEntityDescription()
        category.name = "Category"
        category.managedObjectClassName = NSStringFromClass(Category.self)
        category.properties = [Self.attribute("id", .UUIDAttributeType), Self.attribute("name", .stringAttributeType), Self.attribute("kind", .stringAttributeType)]
        let transaction = NSEntityDescription()
        transaction.name = "Transaction"
        transaction.managedObjectClassName = NSStringFromClass(FinancialTransaction.self)
        transaction.properties = [Self.attribute("id", .UUIDAttributeType), Self.attribute("date", .dateAttributeType), Self.attribute("amount", .decimalAttributeType), Self.attribute("note", .stringAttributeType, optional: true), Self.attribute("kind", .stringAttributeType), Self.attribute("transferID", .UUIDAttributeType, optional: true), Self.attribute("investmentSymbol", .stringAttributeType, optional: true), Self.attribute("investmentQuantity", .decimalAttributeType, optional: true), Self.relationship("account", account), Self.relationship("category", category, optional: true)]
        model.entities = [account, category, transaction]
        container = NSPersistentContainer(name: "MoneyManager", managedObjectModel: model)
        if inMemory { container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null") }
        container.loadPersistentStores { _, error in
            if let error = error { fatalError("Persistent store error: \(error.localizedDescription)") }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
        let value = NSAttributeDescription(); value.name = name; value.attributeType = type; value.isOptional = optional; return value
    }

    private static func relationship(_ name: String, _ destination: NSEntityDescription, optional: Bool = false) -> NSRelationshipDescription {
        let value = NSRelationshipDescription(); value.name = name; value.destinationEntity = destination; value.minCount = optional ? 0 : 1; value.maxCount = 1; value.deleteRule = .nullifyDeleteRule; value.isOptional = optional; return value
    }
}

extension Account: Identifiable {}
extension Category: Identifiable {}
extension FinancialTransaction: Identifiable {}

@objc(Account) final class Account: NSManagedObject {
    @NSManaged var id: UUID; @NSManaged var name: String; @NSManaged var kind: String; @NSManaged var currencyCode: String; @NSManaged var openingBalance: NSDecimalNumber; @NSManaged var createdAt: Date
}

@objc(Category) final class Category: NSManagedObject {
    @NSManaged var id: UUID; @NSManaged var name: String; @NSManaged var kind: String
}

@objc(FinancialTransaction) final class FinancialTransaction: NSManagedObject {
    @NSManaged var id: UUID; @NSManaged var date: Date; @NSManaged var amount: NSDecimalNumber; @NSManaged var note: String?; @NSManaged var kind: String; @NSManaged var transferID: UUID?; @NSManaged var investmentSymbol: String?; @NSManaged var investmentQuantity: NSDecimalNumber?; @NSManaged var account: Account; @NSManaged var category: Category?
}

enum TransactionKind: String, CaseIterable, Identifiable {
    case income, expense, transfer, investmentBuy, investmentSell
    var id: String { rawValue }
    var title: String { switch self { case .income: return "Income"; case .expense: return "Expense"; case .transfer: return "Transfer"; case .investmentBuy: return "Buy investment"; case .investmentSell: return "Sell investment" } }
}

struct FinancialCalculator {
    static func balance(account: Account, transactions: [FinancialTransaction]) -> Decimal {
        transactions.filter { $0.account.objectID == account.objectID }.reduce(account.openingBalance.decimalValue) { $0 + $1.amount.decimalValue }
    }

    static func netWorth(accounts: [Account], transactions: [FinancialTransaction]) -> Decimal {
        accounts.reduce(.zero) { $0 + balance(account: $1, transactions: transactions) }
    }

    static func cashFlow(_ transactions: [FinancialTransaction]) -> (income: Decimal, expense: Decimal) {
        transactions.reduce((.zero, .zero)) { total, transaction in
            switch transaction.kind {
            case TransactionKind.income.rawValue: return (total.0 + transaction.amount.decimalValue, total.1)
            case TransactionKind.expense.rawValue: return (total.0, total.1 + abs(transaction.amount.decimalValue))
            default: return total
            }
        }
    }

    static func holdings(_ transactions: [FinancialTransaction]) -> [String: Decimal] {
        transactions.reduce(into: [:]) { result, transaction in
            guard let symbol = transaction.investmentSymbol, let quantity = transaction.investmentQuantity?.decimalValue else { return }
            result[symbol, default: .zero] += transaction.kind == TransactionKind.investmentSell.rawValue ? -quantity : quantity
        }
    }
}

final class AppLock: ObservableObject {
    @Published var isUnlocked = false
    @Published var error: String?
    var label: String {
        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &evaluationError) else { return "Unlock with Passcode" }
        return context.biometryType == .faceID ? "Unlock with Face ID" : "Unlock with Touch ID"
    }

    func unlock() {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your financial information") { success, error in
            DispatchQueue.main.async { self.isUnlocked = success; self.error = success ? nil : error?.localizedDescription }
        }
    }
}

struct RootView: View {
    @AppStorage("appLockEnabled") private var lockEnabled = false
    @StateObject private var lock = AppLock()

    var body: some View {
        Group {
            if !lockEnabled || lock.isUnlocked { MainTabView() }
            else { LockView(lock: lock) }
        }
        .onChange(of: lockEnabled) { enabled in
            if !enabled { lock.isUnlocked = true }
            else { lock.isUnlocked = false; lock.unlock() }
        }
        .onAppear { if lockEnabled { lock.unlock() } else { lock.isUnlocked = true } }
    }
}

struct LockView: View {
    @ObservedObject var lock: AppLock
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.largeTitle)
            Text("Money Manager").font(.title2).fontWeight(.semibold)
            Text("Your financial information is protected on this device.").multilineTextAlignment(.center).foregroundColor(.secondary)
            Button(lock.label, action: lock.unlock).buttonStyle(.borderedProminent).controlSize(.large)
            if let error = lock.error { Text(error).foregroundColor(.red).multilineTextAlignment(.center) }
        }.padding()
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }
            AccountsView().tabItem { Label("Accounts", systemImage: "building.columns") }
            TransactionsView().tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
            PortfolioView().tabItem { Label("Portfolio", systemImage: "chart.pie") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }.accentColor(.blue)
    }
}

struct DashboardView: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)]) private var accounts: FetchedResults<Account>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FinancialTransaction.date, ascending: false)]) private var transactions: FetchedResults<FinancialTransaction>
    private var cashFlow: (income: Decimal, expense: Decimal) { FinancialCalculator.cashFlow(Array(transactions)) }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Net Worth")) {
                    Text(FinancialCalculator.netWorth(accounts: Array(accounts), transactions: Array(transactions)), format: .currency(code: "USD")).font(.title2).fontWeight(.semibold)
                }
                Section(header: Text("Cash Flow")) {
                    ValueRow(title: "Income", value: cashFlow.income, currencyCode: "USD")
                    ValueRow(title: "Expenses", value: cashFlow.expense, currencyCode: "USD")
                }
                Section(header: Text("Recent Activity")) {
                    ForEach(transactions.prefix(5)) { TransactionRow(transaction: $0) }
                }
            }
            .navigationTitle("Dashboard")
        }
    }
}

struct ValueRow: View {
    let title: String
    let value: Decimal
    let currencyCode: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value, format: .currency(code: currencyCode))
        }
    }
}

struct AccountsView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Account.name, ascending: true)]) private var accounts: FetchedResults<Account>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FinancialTransaction.date, ascending: false)]) private var transactions: FetchedResults<FinancialTransaction>
    @State private var showingAdd = false
    var body: some View {
        NavigationView { List {
            if accounts.isEmpty { EmptyState(title: "No Accounts", image: "building.columns", detail: "Add an account to start tracking your money.") }
            ForEach(accounts) { account in
                ValueRow(title: account.name, value: FinancialCalculator.balance(account: account, transactions: Array(transactions)), currencyCode: account.currencyCode)
            }
                .onDelete { indexes in indexes.map { accounts[$0] }.forEach { account in transactions.filter { $0.account == account }.forEach(context.delete); context.delete(account) }; try? context.save() }
        }.navigationTitle("Accounts").toolbar { Button(action: { showingAdd = true }) { Label("Add Account", systemImage: "plus") } }.sheet(isPresented: $showingAdd) { AccountEditor() } }
    }
}

struct AccountEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var opening = "0"
    @State private var kind = "Checking"
    var body: some View {
        NavigationView { Form {
            TextField("Account name", text: $name)
            Picker("Type", selection: $kind) { ForEach(["Checking", "Savings", "Cash", "Investment"], id: \.self) { Text($0) } }
            TextField("Opening balance", text: $opening).keyboardType(.decimalPad)
        }.navigationTitle("New Account").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } }
    }
    private func save() { let account = Account(context: context); account.id = UUID(); account.name = name.trimmingCharacters(in: .whitespacesAndNewlines); account.kind = kind; account.currencyCode = "USD"; account.openingBalance = NSDecimalNumber(string: opening); account.createdAt = Date(); try? context.save(); dismiss() }
}

struct TransactionsView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FinancialTransaction.date, ascending: false)]) private var transactions: FetchedResults<FinancialTransaction>
    @State private var showingAdd = false
    var body: some View {
        NavigationView { List {
            if transactions.isEmpty { EmptyState(title: "No Transactions", image: "list.bullet.rectangle", detail: "Add income, expenses, transfers, or investments.") }
            ForEach(transactions) { TransactionRow(transaction: $0) }.onDelete { indexes in
                indexes.map { transactions[$0] }.forEach { transaction in
                    if let transferID = transaction.transferID { transactions.filter { $0.transferID == transferID }.forEach(context.delete) }
                    else { context.delete(transaction) }
                }
                try? context.save()
            }
        }.navigationTitle("Transactions").toolbar { Button(action: { showingAdd = true }) { Label("Add Transaction", systemImage: "plus") } }.sheet(isPresented: $showingAdd) { TransactionEditor() } }
    }
}

struct TransactionRow: View {
    let transaction: FinancialTransaction
    var body: some View {
        HStack { VStack(alignment: .leading) { Text(transaction.note ?? TransactionKind(rawValue: transaction.kind)?.title ?? transaction.kind); Text(transaction.account.name + " · " + transaction.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundColor(.secondary) }; Spacer(); Text(transaction.amount.decimalValue, format: .currency(code: transaction.account.currencyCode)).foregroundColor(transaction.amount.decimalValue < 0 ? .red : .primary) }
    }
}

struct TransactionEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Account.name, ascending: true)]) private var accounts: FetchedResults<Account>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Category.name, ascending: true)]) private var categories: FetchedResults<Category>
    @State private var kind: TransactionKind = .expense
    @State private var account: Account?
    @State private var destination: Account?
    @State private var category: Category?
    @State private var amount = ""
    @State private var quantity = ""
    @State private var symbol = ""
    @State private var note = ""
    @State private var date = Date()
    var body: some View {
        NavigationView { Form {
            Picker("Type", selection: $kind) { ForEach(TransactionKind.allCases) { Text($0.title).tag($0) } }
            Picker("Account", selection: $account) { Text("Choose account").tag(Account?.none); ForEach(accounts) { Text($0.name).tag(Optional($0)) } }
            if kind == .transfer { Picker("To", selection: $destination) { Text("Choose destination").tag(Account?.none); ForEach(accounts) { Text($0.name).tag(Optional($0)) } } }
            if kind == .income || kind == .expense { Picker("Category", selection: $category) { Text("None").tag(Category?.none); ForEach(categories.filter { $0.kind == kind.rawValue }) { Text($0.name).tag(Optional($0)) } } }
            TextField("Amount", text: $amount).keyboardType(.decimalPad)
            if kind == .investmentBuy || kind == .investmentSell { TextField("Symbol", text: $symbol).textInputAutocapitalization(.characters); TextField("Quantity", text: $quantity).keyboardType(.decimalPad) }
            TextField("Note", text: $note)
            DatePicker("Date", selection: $date, displayedComponents: .date)
        }.navigationTitle("New Transaction").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!valid) } } }
    }
    private var valid: Bool { account != nil && Decimal(string: amount) != nil && (kind != .transfer || (destination != nil && destination != account)) && (!(kind == .investmentBuy || kind == .investmentSell) || (!symbol.isEmpty && Decimal(string: quantity) != nil)) }
    private func save() {
        guard let account = account, let value = Decimal(string: amount) else { return }
        if kind == .transfer, let destination = destination { let id = UUID(); create(account, amount: -abs(value), transferID: id); create(destination, amount: abs(value), transferID: id) }
        else { let signed = kind == .expense || kind == .investmentBuy ? -abs(value) : abs(value); create(account, amount: signed, transferID: nil) }
        try? context.save(); dismiss()
    }
    private func create(_ account: Account, amount: Decimal, transferID: UUID?) { let transaction = FinancialTransaction(context: context); transaction.id = UUID(); transaction.account = account; transaction.category = category; transaction.amount = NSDecimalNumber(decimal: amount); transaction.date = date; transaction.kind = kind.rawValue; transaction.note = note.isEmpty ? nil : note; transaction.transferID = transferID; transaction.investmentSymbol = symbol.isEmpty ? nil : symbol.uppercased(); transaction.investmentQuantity = quantity.isEmpty ? nil : NSDecimalNumber(string: quantity) }
}

struct PortfolioView: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FinancialTransaction.date, ascending: false)]) private var transactions: FetchedResults<FinancialTransaction>
    private var holdings: [String: Decimal] { FinancialCalculator.holdings(Array(transactions)) }

    var body: some View {
        NavigationView {
            List {
                if holdings.isEmpty {
                    EmptyState(title: "No Holdings", image: "chart.pie", detail: "Record an investment purchase to track holdings.")
                } else {
                    ForEach(holdings.keys.sorted(), id: \.self) { symbol in
                        HStack {
                            Text(symbol)
                            Spacer()
                            Text(NSDecimalNumber(decimal: holdings[symbol]!).stringValue)
                        }
                    }
                }
            }
            .navigationTitle("Portfolio")
        }
    }
}

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage("appLockEnabled") private var lockEnabled = false
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Account.name, ascending: true)]) private var accounts: FetchedResults<Account>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Category.name, ascending: true)]) private var categories: FetchedResults<Category>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FinancialTransaction.date, ascending: false)]) private var transactions: FetchedResults<FinancialTransaction>
    @State private var showingCategories = false
    @State private var shareItems: [Any] = []
    @State private var restoring = false
    var body: some View {
        NavigationView { Form {
            Section("Security") { Toggle("Require device authentication", isOn: $lockEnabled) }
            Section("Categories") { Button("Manage Categories") { showingCategories = true } }
            Section("Data") { Button("Export CSV") { shareItems = [BackupService.csv(accounts: Array(accounts), transactions: Array(transactions))] }; Button("Create JSON Backup") { shareItems = [BackupService.backup(accounts: Array(accounts), categories: Array(categories), transactions: Array(transactions))] }; Button("Restore JSON Backup") { restoring = true }; Button("Load Demo Data") { BackupService.demo(context: context) } }
        }.navigationTitle("Settings").sheet(isPresented: $showingCategories) { CategoriesView() }.sheet(isPresented: Binding(get: { !shareItems.isEmpty }, set: { if !$0 { shareItems = [] } })) { ActivityView(items: shareItems) }.sheet(isPresented: $restoring) { BackupPicker { url in BackupService.restore(from: url, context: context) } } }
    }
}

struct CategoriesView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Category.name, ascending: true)]) private var categories: FetchedResults<Category>
    @State private var name = ""
    @State private var kind = TransactionKind.expense
    var body: some View {
        NavigationView { List { Section { Picker("Type", selection: $kind) { Text("Income").tag(TransactionKind.income); Text("Expense").tag(TransactionKind.expense) }; TextField("Category name", text: $name); Button("Add Category", action: add).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }; ForEach(categories) { Text($0.name + " · " + $0.kind.capitalized) }.onDelete { indexes in indexes.map { categories[$0] }.forEach(context.delete); try? context.save() } }.navigationTitle("Categories").toolbar { Button("Done") { dismiss() } } }
    }
    private func add() { let category = Category(context: context); category.id = UUID(); category.name = name.trimmingCharacters(in: .whitespacesAndNewlines); category.kind = kind.rawValue; try? context.save(); name = "" }
}

struct EmptyState: View {
    let title: String; let image: String; let detail: String
    var body: some View { VStack(spacing: 10) { Image(systemName: image).font(.title).foregroundColor(.secondary); Text(title).font(.headline); Text(detail).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(.vertical, 36).listRowBackground(Color.clear) }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct BackupPicker: UIViewControllerRepresentable {
    let completion: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController { let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json]); picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate { let completion: (URL) -> Void; init(completion: @escaping (URL) -> Void) { self.completion = completion }; func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { if let url = urls.first { completion(url) } } }
}

struct Backup: Codable { var accounts: [BackupAccount]; var categories: [BackupCategory]; var transactions: [BackupTransaction] }
struct BackupAccount: Codable { var id: UUID; var name: String; var kind: String; var currencyCode: String; var openingBalance: Decimal; var createdAt: Date }
struct BackupCategory: Codable { var id: UUID; var name: String; var kind: String }
struct BackupTransaction: Codable { var id: UUID; var date: Date; var amount: Decimal; var note: String?; var kind: String; var transferID: UUID?; var investmentSymbol: String?; var investmentQuantity: Decimal?; var accountID: UUID; var categoryID: UUID? }

enum BackupService {
    static func backup(accounts: [Account], categories: [Category], transactions: [FinancialTransaction]) -> URL { let value = Backup(accounts: accounts.map { BackupAccount(id: $0.id, name: $0.name, kind: $0.kind, currencyCode: $0.currencyCode, openingBalance: $0.openingBalance.decimalValue, createdAt: $0.createdAt) }, categories: categories.map { BackupCategory(id: $0.id, name: $0.name, kind: $0.kind) }, transactions: transactions.map { BackupTransaction(id: $0.id, date: $0.date, amount: $0.amount.decimalValue, note: $0.note, kind: $0.kind, transferID: $0.transferID, investmentSymbol: $0.investmentSymbol, investmentQuantity: $0.investmentQuantity?.decimalValue, accountID: $0.account.id, categoryID: $0.category?.id) }); return write(try! JSONEncoder().encode(value), named: "MoneyManager-backup.json") }
    static func csv(accounts: [Account], transactions: [FinancialTransaction]) -> URL { let rows = ["Date,Type,Account,Amount,Note"] + transactions.map { "\($0.date.formatted(date: .numeric, time: .omitted)),\($0.kind),\(quote($0.account.name)),\($0.amount.stringValue),\(quote($0.note ?? ""))" }; return write(rows.joined(separator: "\n").data(using: .utf8)!, named: "MoneyManager-transactions.csv") }
    static func restore(from url: URL, context: NSManagedObjectContext) { guard url.startAccessingSecurityScopedResource() else { return }; defer { url.stopAccessingSecurityScopedResource() }; guard let value = try? JSONDecoder().decode(Backup.self, from: Data(contentsOf: url)) else { return }; context.performAndWait { let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Transaction"); let delete = NSBatchDeleteRequest(fetchRequest: request); _ = try? context.execute(delete); ["Account", "Category"].forEach { name in let request = NSFetchRequest<NSFetchRequestResult>(entityName: name); _ = try? context.execute(NSBatchDeleteRequest(fetchRequest: request)) }; let accounts = Dictionary(uniqueKeysWithValues: value.accounts.map { item -> (UUID, Account) in let object = Account(context: context); object.id = item.id; object.name = item.name; object.kind = item.kind; object.currencyCode = item.currencyCode; object.openingBalance = NSDecimalNumber(decimal: item.openingBalance); object.createdAt = item.createdAt; return (item.id, object) }); let categories = Dictionary(uniqueKeysWithValues: value.categories.map { item -> (UUID, Category) in let object = Category(context: context); object.id = item.id; object.name = item.name; object.kind = item.kind; return (item.id, object) }); value.transactions.forEach { item in guard let account = accounts[item.accountID] else { return }; let object = FinancialTransaction(context: context); object.id = item.id; object.date = item.date; object.amount = NSDecimalNumber(decimal: item.amount); object.note = item.note; object.kind = item.kind; object.transferID = item.transferID; object.investmentSymbol = item.investmentSymbol; object.investmentQuantity = item.investmentQuantity.map(NSDecimalNumber.init(decimal:)); object.account = account; object.category = item.categoryID.flatMap { categories[$0] } }; try? context.save() } }
    static func demo(context: NSManagedObjectContext) { guard (try? context.count(for: NSFetchRequest<Account>(entityName: "Account"))) == 0 else { return }; let checking = Account(context: context); checking.id = UUID(); checking.name = "Checking"; checking.kind = "Checking"; checking.currencyCode = "USD"; checking.openingBalance = 1200; checking.createdAt = Date(); let groceries = Category(context: context); groceries.id = UUID(); groceries.name = "Groceries"; groceries.kind = "expense"; let salary = Category(context: context); salary.id = UUID(); salary.name = "Salary"; salary.kind = "income"; [(-65 as Decimal, "Groceries", groceries, "expense"), (2400, "Paycheck", salary, "income")].forEach { amount, note, category, kind in let transaction = FinancialTransaction(context: context); transaction.id = UUID(); transaction.account = checking; transaction.amount = NSDecimalNumber(decimal: amount); transaction.note = note; transaction.category = category; transaction.kind = kind; transaction.date = Date() }; try? context.save() }
    private static func write(_ data: Data, named: String) -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent(named); try? data.write(to: url, options: .atomic); return url }
    private static func quote(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
}
