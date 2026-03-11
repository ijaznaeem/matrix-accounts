````instructions
# VEYO SYNC – Flutter Project Coding Standards & Architecture Guide

> **App Branding:** VEYO SYNC – Real-Time Business  
> **Package Name:** `matrix_accounts`  
> **Description:** Offline-first multi-company accounts & inventory management app  
> **Platforms:** Android, iOS, Web, Windows  
> **Dart SDK:** `>=3.4.0 <4.0.0` | **Flutter Riverpod:** v2.x | **Database:** Isar v3

---

## 1. Core Principles

- **Dart 3.x syntax**: Use records, sealed classes, patterns, and `switch` expressions where appropriate.
- **Immutability**: All `StatelessWidget` and `ConsumerWidget` fields must be `final`.
- **Performance**: Use `const` constructors wherever possible. Never call functions inside `build()`.
- **Offline-First**: All data operations go through Isar (local DB). Remote sync is additive via Laravel API.
- **Multi-Company**: Every entity has a `companyId` field. Always filter by `companyId` from `currentCompanyProvider`.

---

## 2. Actual Project Structure

```
lib/
├── main.dart                        # App entry point – ProviderScope, Isar init, seeding
├── core/
│   ├── config/
│   │   ├── providers.dart           # Global providers (isarServiceProvider, currentCompanyProvider)
│   │   └── routes.dart              # GoRouter route definitions
│   ├── database/
│   │   ├── isar_service.dart        # IsarService singleton – opens all Isar schemas
│   │   ├── seed_data.dart           # Seeds chart of accounts and default data
│   │   └── dao/                     # ALL DAO classes – the only place for DB calls
│   │       ├── account_dao.dart     # Double-entry accounting engine
│   │       ├── expense_dao.dart
│   │       ├── party_dao.dart       # Customers & Suppliers + balance tracking
│   │       ├── payment_dao.dart     # Payments In/Out
│   │       ├── product_dao.dart
│   │       ├── product_master_dao.dart
│   │       ├── purchase_dao.dart
│   │       └── sales_dao.dart       # Sales invoices, returns, COGS, balance tracking
│   ├── services/
│   │   ├── auth_service.dart        # Login/logout with SharedPreferences
│   │   ├── biometric_service.dart   # LocalAuthentication wrapper
│   │   ├── sync_service.dart        # Laravel REST sync service
│   │   ├── api_client.dart          # HTTP API client
│   │   └── whatsapp_service.dart    # WhatsApp sharing helper
│   ├── providers/
│   │   ├── settings_provider.dart
│   │   └── sync_providers.dart
│   └── mixins/
│       └── app_lifecycle_mixin.dart
├── data/
│   └── models/                      # Isar @collection models + generated .g.dart files
│       ├── account_models.dart      # Account, AccountTransaction, AccountType, TransactionType
│       ├── company_model.dart       # Company, CompanyUser
│       ├── inventory_models.dart    # Product, ItemCategory, UnitOfMeasure
│       ├── invoice_stock_models.dart# Invoice, StockLedger, InvoiceType, StockMovementType
│       ├── party_model.dart         # Party, PartyType (customer/supplier/both)
│       ├── payment_models.dart      # PaymentAccount, PaymentIn, PaymentOut
│       ├── sync_change_model.dart   # SyncChange – tracks local mutations for sync
│       ├── transaction_model.dart   # Transaction, TransactionLine
│       └── user_model.dart          # User
└── features/
    ├── cash_bank/
    ├── companies/                   # (presentation/, services/)
    ├── expenses/
    ├── inventory/                   # (logic/, presentation/)
    ├── journal_entries/
    ├── parties/                     # (logic/, presentation/)
    ├── payments/                    # (logic/, presentation/)
    ├── purchases/                   # (logic/, presentation/, services/)
    ├── reports/                     # (presentation/, services/)
    ├── sales/
    │   ├── logic/sales_providers.dart
    │   ├── presentation/            # Form & list screens for invoices & returns
    │   └── services/
    │       ├── invoice_generator.dart        # Canvas-based invoice image generator
    │       ├── invoice_sharing_extensions.dart
    │       ├── sales_invoice_service.dart
    │       └── whatsapp_sharing_fix.dart
    ├── settings/
    ├── shared/                      # Reusable widgets across features
    └── sync/                        # sync_screen.dart
```

---

## 3. Database – Isar v3

- **`IsarService`** opens all schemas at startup in `lib/core/database/isar_service.dart`.
- **Register new `@collection` models** in `IsarService.init()` after creating them.
- **Code generation**: Run `flutter pub run build_runner build --delete-conflicting-outputs` after modifying models.
- **Never** call `isar.writeTxn()` or query Isar directly inside widgets, providers, or services — always go through a DAO.

### Model Template
```dart
@collection
class MyEntity {
  Id id = Isar.autoIncrement;

  @Index()
  late int companyId; // REQUIRED on every entity

  // other fields...
}
```

---

## 4. DAO Pattern (Strict)

All database interactions happen **only** in DAO classes under `lib/core/database/dao/`.

- **Naming**: `{Entity}Dao` — e.g. `SalesDao`, `PartyDao`, `AccountDao`
- **Constructor**: Takes `Isar isar` as the only parameter
- **Cross-DAO**: DAOs may hold references to other DAOs initialized in the constructor

```dart
class SalesDao {
  final Isar isar;
  late final AccountDao _accountDao;
  late final PaymentDao _paymentDao;
  late final PartyDao _partyDao;

  SalesDao(this.isar) {
    _accountDao = AccountDao(isar);
    _paymentDao = PaymentDao(isar);
    _partyDao = PartyDao(isar);
  }
}
```

### Input Classes for Write Operations
```dart
class SaleLineInput {
  final int productId;
  final double qty;
  final double rate;
  SaleLineInput({required this.productId, required this.qty, required this.rate});
}

class PaymentLineInput {
  final int paymentAccountId;
  final double amount;
  final String? referenceNo;
  PaymentLineInput({required this.paymentAccountId, required this.amount, this.referenceNo});
}
```

---

## 5. State Management – Riverpod v2

Using `flutter_riverpod: ^2.5.0` — **without** `riverpod_generator` or `freezed` (not in this project).

### Provider Patterns

```dart
// Service/DAO provider
final salesDaoProvider = Provider<SalesDao>((ref) {
  final isar = ref.read(isarServiceProvider).isar;
  return SalesDao(isar);
});

// Async list with refresh trigger
final productListRefreshProvider = StateProvider<int>((ref) => 0);
final productListProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(productListRefreshProvider);
  final company = ref.read(currentCompanyProvider);
  if (company == null) return [];
  return ref.read(productDaoProvider).getAllByCompany(company.id);
});

// Global state
final currentCompanyProvider = StateProvider<Company?>((ref) => null);
final currentUserProvider = StateProvider<User?>((ref) => null);
```

### Startup Overrides (main.dart)
```dart
ProviderScope(
  overrides: [
    isarServiceProvider.overrideWithValue(isarService),
    salesDaoProvider.overrideWithValue(salesDao),
    accountDaoProvider.overrideWithValue(accountDao),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ],
  child: const MatrixAccountsApp(),
)
```

---

## 6. Accounting Engine Rules

This app implements **double-entry accounting**. All accounting entries are created inside `AccountDao` internal methods called from DAOs (never directly from UI).

### System Chart of Accounts
| Code | Name | Type |
|------|------|------|
| 1000 | Cash | Asset |
| 1050 | Cheque | Asset |
| 1100 | Bank | Asset |
| 1200 | Accounts Receivable | Asset |
| 1300 | Inventory | Asset |
| 2000 | Accounts Payable | Liability |
| 3000 | Owner Equity | Equity |
| 4000 | Sales Revenue | Revenue |
| 5000 | Cost of Goods Sold | Expense |

### Double-Entry Journal Rules
- **Sale Invoice**: DR AR (1200) / CR Sales Revenue (4000)
- **COGS on Sale**: DR COGS (5000) / CR Inventory (1300)
- **Payment Received**: DR Cash/Bank (1000/1100) / CR AR (1200)
- **Purchase Invoice**: DR Inventory (1300) / CR AP (2000)
- **Purchase Payment**: DR AP (2000) / CR Cash/Bank

### Customer Balance on Sales Invoices
Every `Invoice` stores three balance fields:
```dart
double previousBalance;  // Customer AR balance BEFORE this invoice (opening balance)
double paidAmount;       // Cash/payment received with this invoice
double remainingBalance; // Closing balance = previousBalance + grandTotal - paidAmount
```
> Always call `PartyDao.getPartyBalance(partyId, companyId)` to get opening balance before creating/updating a sale invoice.

### Stock Ledger – Weighted Average Cost
```
inPurchase    → stock added
outSale       → stock deducted (COGS calculated via weighted average)
inAdjustment  → returns & positive adjustments
outAdjustment → negative adjustments
```

---

## 7. Invoice Generator

Located at `lib/features/sales/services/invoice_generator.dart`

- Canvas-based image generator using `dart:ui` — outputs `Uint8List` PNG
- Summary section renders in order:
  1. **Opening Balance** (`invoice.previousBalance`)
  2. **Total Amount** (calculated from line items)
  3. **Paid Amount**
  4. **Closing Balance** (`invoice.remainingBalance`) — red if > 0, green "CLEARED" if = 0
- WhatsApp share text must include all four balance fields

---

## 8. Navigation – GoRouter v14

- All routes defined in `lib/core/config/routes.dart`
- Use `context.go('/route')` for navigation, `context.push('/route')` for stack-based

---

## 9. Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_riverpod` | ^2.5.0 | State management |
| `isar` + `isar_flutter_libs` | ^3.1.0+1 | Offline NoSQL database |
| `go_router` | ^14.0.0 | Declarative navigation |
| `isar_generator` | ^3.1.0+1 | Isar code generation (dev) |
| `build_runner` | ^2.4.0 | Code generation runner (dev) |
| `fl_chart` | ^0.69.0 | Charts and graphs |
| `pdf` + `printing` | ^3 / ^5 | PDF report generation |
| `share_plus` | ^7.2.1 | Native file/content sharing |
| `intl` | ^0.19.0 | Date & currency formatting |
| `local_auth` | ^2.1.6 | Biometric authentication |
| `excel` | ^4.0.0 | Excel export |
| `url_launcher` | ^6.3.2 | WhatsApp & external links |
| `flutter_launcher_icons` | ^0.13.1 | App icon generation (dev) |

---

## 10. Coding Style

- `snake_case` files · `UpperCamelCase` classes · `lowerCamelCase` variables/methods
- `///` doc comments on all public DAO methods and model fields
- **No helper widget methods**: extract to private `_MyWidget extends StatelessWidget`
- **Currency**: `NumberFormat('#,##,##0.00')` from `intl`
- **Dates (display)**: `DateFormat('dd MMM, yyyy')`
- **Error handling**: throw from DAOs, catch and show `SnackBar` in screens

---

## 11. App Icon & Assets

- App icon source: `assets/icons/app_icon.png` (VEYO SYNC logo)
- Regenerate icons: `flutter pub run flutter_launcher_icons`
- Assets declared in `pubspec.yaml`: `assets/fonts/`, `assets/icons/`, `assets/excel_templates/`

---

## 12. Sync Architecture (Laravel Backend)

- Laravel project in `laravel_sync/` directory
- `SyncChange` model tracks all local mutations for offline-first sync
- `SyncService` → `lib/core/services/sync_service.dart`
- App is fully functional offline; sync is additive and optional
````
