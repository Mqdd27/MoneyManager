# Money Manager

A private, offline-first personal finance utility for accounts, transactions, transfers, categories, and investment holdings.

## Compatibility

- Minimum deployment target: iOS 15.0
- Primary layout target: iPhone 7, 4.7-inch display
- Supports newer iPhones and iOS releases without requiring iOS 16 APIs
- Uses `NavigationView`, custom SwiftUI primitives, Core Data, LocalAuthentication, URLSession-ready native networking boundaries, and no third-party dependencies

## Architecture

The app is a single native SwiftUI target. `PersistenceController` creates the Core Data model and persistent store. Financial entities are `Account`, `Category`, and `FinancialTransaction`; account balances and holdings are derived from historical transactions. `FinancialCalculator` keeps money calculations in `Decimal`. Views use fetch requests only for the data they render.

## Project structure

- `MoneyManager/MoneyManagerApp.swift`: application, Core Data entities, calculation logic, views, backup/export service
- `MoneyManagerTests/FinancialCalculatorTests.swift`: business-logic tests
- `MoneyManager.xcodeproj`: iOS 15 Xcode project

## Build and run

1. Open `MoneyManager.xcodeproj` in Xcode 14 or later.
2. Set a unique signing team and bundle identifier.
3. Select an iPhone 7 simulator or connected device.
4. Build and run the `MoneyManager` scheme.

Run tests:

```sh
xcodebuild -project MoneyManager.xcodeproj -scheme MoneyManager -destination 'platform=iOS Simulator,name=iPhone 7' test
```

## First Xcode and device build checklist

- [ ] Install Xcode 14 or later and accept its license.
- [ ] Open `MoneyManager.xcodeproj` and select the `MoneyManager` target.
- [ ] In Signing & Capabilities, select an Apple Account Personal Team or development team.
- [ ] Replace `com.example.MoneyManager` with a unique bundle identifier owned by that team.
- [ ] Keep `IPHONEOS_DEPLOYMENT_TARGET` at `15.0` for both app and test targets.
- [ ] Connect the iPhone 7 with a data cable, unlock it, and trust the Mac if prompted.
- [ ] On iOS 16 or later, enable Developer Mode if the device requires it. iOS 15 does not have Developer Mode.
- [ ] Select the connected iPhone as the `MoneyManager` run destination.
- [ ] Build and run the app. Do not treat this project as device-tested until this succeeds.
- [ ] Run `MoneyManagerTests` from Xcode's Test navigator or the scheme test action.
- [ ] Launch the installed app and enable device authentication in Settings. Verify the lock reads and authenticates with Touch ID on iPhone 7.
- [ ] Add an account and transaction, relaunch the app, and verify Core Data persistence.
- [ ] Create a JSON backup, share/save it, restore it through Settings, and verify restored records.
- [ ] Export CSV and verify its headers, quoted text, amounts, and transaction rows in a spreadsheet or text editor.

## Sideloading

Connect an iPhone, select it as the run destination, set the target Signing & Capabilities team to a personal Apple ID or development team, then run from Xcode. A free Apple ID requires periodically re-signing the app.

## Backup and export

Settings can create a JSON backup containing accounts, categories, and transactions. Restore replaces local financial data after selecting a JSON backup. CSV export contains transaction date, type, account, amount, and note. Backup and export files are generated in the temporary directory and presented through the system share sheet.

## Known limitations

- Currency is stored per account, but dashboard totals use USD presentation and do not convert currencies.
- Investment holdings track quantity from buy and sell transactions; market price retrieval is not implemented.
- The app has no cloud sync or banking integration.
- Xcode is not installed in this environment, so an iOS build must be run locally in Xcode.
