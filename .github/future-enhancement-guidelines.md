# Future Enhancement & New Table Guidelines

This document defines the standard process for implementing any new feature or adding any new table in VEYO SYNC.

Use this as the default playbook to avoid sync regressions, schema mismatches, and accounting/data integrity issues.

---

## 1) Core Rule: Local First, Sync Second

- UI must read/write through local Isar first.
- Remote API sync is asynchronous and additive.
- Never make UI depend directly on network availability.

---

## 2) Before Starting Any Enhancement

1. Define business scope clearly:
   - Which feature?
   - Which tables/entities are affected?
   - Which reports/balances will change?
2. Confirm multi-company impact:
   - Every new entity must include `companyId`.
3. Confirm sync impact:
   - Will create/update/delete operations be pushed and pulled?
4. Confirm accounting impact (if financial):
   - Are journal entries required?
   - Which account codes are impacted?

---

## 3) New Table Implementation (End-to-End)

## 3.1 Flutter Isar Model Layer

When adding a new local entity:

- Create model under `lib/data/models/` with `@collection`.
- Include:
  - `Id id = Isar.autoIncrement;`
  - indexed `companyId`
  - timestamps/fields needed for sync and UI
- Keep naming consistent with existing models.

Example shape:

```dart
@collection
class NewEntity {
  Id id = Isar.autoIncrement;

  @Index()
  late int companyId;

  late String name;
  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();
}
```

Then:

- Register schema in `lib/core/database/isar_service.dart`.
- Run codegen:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

---

## 3.2 DAO Layer (Required)

All DB operations must go in `lib/core/database/dao/`.

For each new table, add `{Entity}Dao` with:

- Read methods filtered by `companyId`
- Create/update/delete methods in write transactions
- Validation/business rules inside DAO (not UI)

Sync requirement:

- Every create/update/delete must create a `SyncChange` entry.
- Do not write Isar directly from providers/widgets/services.

---

## 3.3 Provider Layer (Riverpod)

- Add DAO provider and list/detail providers as needed.
- Add refresh trigger providers when list invalidation is needed.
- Read `currentCompanyProvider` and always scope by company.

---

## 3.4 UI Layer

- UI calls provider/DAO methods only.
- Catch DAO exceptions in screen and show `SnackBar`.
- Do not place transaction logic in widget build methods.

---

## 3.5 Laravel Backend Layer

For synced tables, backend must mirror capabilities.

Create/update:

1. Migration in `laravel_sync/database/migrations/`
2. Eloquent Model in `laravel_sync/app/Models/`
3. API controller methods in `laravel_sync/app/Http/Controllers/Api/`
4. Route entries in `laravel_sync/routes/api.php` (if needed)

Rules:

- Ensure company scoping at query level.
- Ensure validation for required fields and uniqueness constraints.
- For any accepted change, server must log it in `sync_changes`.

---

## 3.6 Sync Engine Integration (Critical)

Enhancement is incomplete until both push and pull paths support the table.

### Flutter side (`lib/core/services/sync_service.dart`)

- Include new table in push payload mapping.
- Add pull/apply handler for table in change dispatcher.
- Ensure create/update/delete apply logic is idempotent.

### Laravel side (`laravel_sync/app/Services/SyncService.php`)

- Apply incoming operations for new table.
- Record each applied operation into sync change log.
- Return current version/token after processing.

---

## 4) Financial/Stock Enhancements Extra Rules

If feature affects accounts, inventory, or invoices:

- Use existing DAO orchestration patterns (`AccountDao`, `SalesDao`, `PurchaseDao`, etc.).
- Preserve double-entry accounting rules.
- Ensure stock ledger movement types remain consistent.
- Recompute dependent balances (party, invoice, account) atomically.

---

## 5) Testing Checklist (Must Pass)

Minimum required before merge:

1. Unit/smoke test for new table sync push/pull behavior.
2. Verify only pushed local IDs are marked synced.
3. Verify pull applies create/update/delete correctly.
4. Verify company scoping works.
5. Run:

```bash
flutter analyze
flutter test -j 1
```

For backend table changes:

- Run migrations in test/staging environment.
- Verify API responses for success/conflict/error paths.

---

## 6) Definition of Done for Any New Table

A new table is done only when all are true:

- [ ] Isar model created and generated
- [ ] Schema registered in Isar service
- [ ] DAO methods implemented
- [ ] SyncChange writing implemented for CRUD
- [ ] Providers added/updated
- [ ] UI integrated and error-handled
- [ ] Laravel migration/model/controller updated
- [ ] Server SyncService apply + record change implemented
- [ ] Flutter pull/apply handler implemented
- [ ] Tests added/updated and passing
- [ ] No sync-related analyzer/test regressions

---

## 7) Common Mistakes to Avoid

- Missing `companyId` on new entities.
- Direct Isar writes from widgets/providers.
- Adding table to push but not to pull (or vice versa).
- Server applies change but does not log `sync_changes` entry.
- Marking all local changes synced instead of only pushed IDs.
- Skipping tests for conflict/idempotency behavior.

---

## 8) Suggested PR Structure

When submitting enhancement PRs:

1. `models:` Isar + Laravel schema updates
2. `dao/services:` business logic + sync queue/logging
3. `sync:` push/pull/apply integration
4. `ui/providers:` presentation wiring
5. `tests:` smoke/unit/integration coverage

This keeps review focused and reduces regression risk.
