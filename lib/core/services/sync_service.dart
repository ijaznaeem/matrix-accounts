import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/account_models.dart' as am;
import '../../data/models/company_model.dart';
import '../../data/models/inventory_models.dart';
import '../../data/models/invoice_stock_models.dart';
import '../../data/models/party_model.dart';
import '../../data/models/payment_models.dart';
import '../../data/models/sync_change_model.dart';
import '../../data/models/transaction_model.dart' as tm;
import '../database/isar_service.dart';
import 'api_client.dart';

class SyncService {
  final ApiClient apiClient;
  final IsarService isarService;
  final SharedPreferences prefs;

  SyncService({
    required this.apiClient,
    required this.isarService,
    required this.prefs,
  });

  Isar get _isar => isarService.isar;

  String get deviceId {
    var id = prefs.getString('device_id');
    if (id == null) {
      id = const Uuid().v4();
      prefs.setString('device_id', id);
    }
    return id;
  }

  int get lastSyncVersion => prefs.getInt('last_sync_version') ?? 0;

  Future<void> setLastSyncVersion(int version) async {
    await prefs.setInt('last_sync_version', version);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ──────────────────────────────────────────────────────────────────────────

  /// Pull changes from server and apply them to local Isar.
  Future<SyncResult> pullChanges({
    required int companyId,
    int? serverCompanyId,
    List<String>? tables,
  }) async {
    try {
      final response = await apiClient.post('/api/sync/pull', {
        'company_id': serverCompanyId ?? companyId,
        'device_id': deviceId,
        'last_version': lastSyncVersion,
        if (tables != null) 'tables': tables,
      });

      if (response['success'] == true) {
        final changes = response['changes'] as List;
        final currentVersion = response['current_version'] as int;

        await _applyChanges(changes, localCompanyId: companyId);
        await setLastSyncVersion(currentVersion);

        return SyncResult(
          success: true,
          changesApplied: changes.length,
          currentVersion: currentVersion,
        );
      }

      return SyncResult(
        success: false,
        error: response['message'] ?? 'Server returned unsuccessful response',
      );
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }

  /// Push unsynced local SyncChange records to the server.
  Future<SyncResult> pushChanges({
    required int companyId,
    int? serverCompanyId,
    required List<Map<String, dynamic>> changes,
  }) async {
    try {
      final response = await apiClient.post('/api/sync/push', {
        'company_id': serverCompanyId ?? companyId,
        'device_id': deviceId,
        'changes': changes,
      });

      if (response['success'] == true) {
        final idMappingsRaw = response['id_mappings'];
        final idMappings = (idMappingsRaw is Map)
            ? Map<String, dynamic>.from(idMappingsRaw)
            : <String, dynamic>{};
        final conflictsRaw = response['conflicts'];
        final currentVersionRaw = response['current_version'];
        final currentVersion = currentVersionRaw is int
            ? currentVersionRaw
            : int.tryParse(currentVersionRaw?.toString() ?? '');
        final conflictsCount = conflictsRaw is List
            ? conflictsRaw.length
            : (conflictsRaw is int ? conflictsRaw : 0);

        // Resolve Isar record IDs from the local_id keys each change carries.
        // Only mark exactly those records as synced — not all pending changes.
        final syncChangeIds = changes
            .map((c) => c['local_id'] as String?)
            .whereType<String>()
            .map((lid) => int.tryParse(lid.replaceFirst('local_', '')))
            .whereType<int>()
            .toList();

        await _updateLocalIds(idMappings, syncChangeIds);

        return SyncResult(
          success: true,
          currentVersion: currentVersion,
          conflicts: conflictsCount,
        );
      }

      return SyncResult(
        success: false,
        error: response['message'] ?? 'Server returned unsuccessful response',
      );
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }

  /// Full bidirectional sync: pull first, then push local changes.
  Future<SyncResult> fullSync(int companyId) async {
    // Require auth token — sync needs a server account
    if (apiClient.token == null) {
      return SyncResult(
        success: false,
        error:
            'Not authenticated for sync. Please log out and sign in with your server account credentials.',
      );
    }

    // Register or find the company on the server, get server-side company ID
    final serverCompanyId = await _ensureServerCompanyId(companyId);
    if (serverCompanyId == null) {
      return SyncResult(
        success: false,
        error: 'Failed to register company on server. Check your connection.',
      );
    }

    final pullResult = await pullChanges(
        companyId: companyId, serverCompanyId: serverCompanyId);
    if (!pullResult.success) return pullResult;

    final localChanges = await _getLocalChanges(companyId);
    if (localChanges.isEmpty) return pullResult;

    return pushChanges(
        companyId: companyId,
        serverCompanyId: serverCompanyId,
        changes: localChanges);
  }

  /// Finds or creates the company on the server and caches the server ID.
  Future<int?> _ensureServerCompanyId(int localCompanyId) async {
    final cacheKey = 'server_company_id_$localCompanyId';
    final cached = prefs.getInt(cacheKey);
    if (cached != null) return cached;

    final company = await _isar.companys.get(localCompanyId);
    if (company == null) return null;

    try {
      // Check if already on server
      final listResponse = await apiClient.get('/api/companies');
      if (listResponse['success'] == true) {
        final companies =
            (listResponse['companies'] as List).cast<Map<String, dynamic>>();
        final match =
            companies.where((c) => c['name'] == company.name).firstOrNull;
        if (match != null) {
          final serverId = match['id'] as int;
          await prefs.setInt(cacheKey, serverId);
          return serverId;
        }
      }
      // Create on server
      final createResponse = await apiClient.post('/api/companies', {
        'name': company.name,
        'primary_currency': company.primaryCurrency,
        'financial_year_start_month': company.financialYearStartMonth,
      });
      if (createResponse['success'] == true) {
        final serverId = createResponse['company']['id'] as int;
        await prefs.setInt(cacheKey, serverId);
        return serverId;
      }
    } catch (_) {}
    return null;
  }

  /// Get sync status from the server for this device.
  Future<SyncStatus?> getSyncStatus(int companyId) async {
    try {
      final cacheKey = 'server_company_id_$companyId';
      final serverCompanyId = prefs.getInt(cacheKey) ?? companyId;
      final response = await apiClient.get(
        '/api/sync/status',
        queryParams: {
          'company_id': serverCompanyId.toString(),
          'device_id': deviceId,
        },
      );

      if (response['success'] == true) {
        final s = response['status'];
        return SyncStatus(
          deviceId: s['device_id'],
          lastSyncVersion: s['last_sync_version'] as int,
          currentVersion: s['current_version'] as int,
          pendingChanges: s['pending_changes'] as int,
          isSynced: s['is_synced'] as bool,
          lastSyncAt: s['last_sync_at'] != null
              ? DateTime.parse(s['last_sync_at'])
              : null,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LOCAL CHANGE HARVESTING
  // ──────────────────────────────────────────────────────────────────────────

  /// Read all unsynced SyncChange records from Isar and format them
  /// for the /api/sync/push payload.
  /// Includes both company-scoped records and global-table records (companyId=0).
  Future<List<Map<String, dynamic>>> _getLocalChanges(int companyId) async {
    final companyRecords = await _isar.syncChanges
        .filter()
        .companyIdEqualTo(companyId)
        .syncedEqualTo(false)
        .findAll();

    // Also include global-table records (e.g. units_of_measure with companyId=0)
    final globalRecords = await _isar.syncChanges
        .filter()
        .companyIdEqualTo(0)
        .syncedEqualTo(false)
        .findAll();

    final allUnsynced = [...companyRecords, ...globalRecords];

    return allUnsynced
        .map((c) => {
              'local_id': 'local_${c.id}', // stable reference for id_mappings
              'table': c.table,
              'record_id': c.recordId,
              'operation': _opToString(c.operation),
              'data': jsonDecode(c.data),
              'timestamp': c.createdAt.toIso8601String(),
            })
        .toList();
  }

  String _opToString(ChangeOperation op) => switch (op) {
        ChangeOperation.create => 'INSERT',
        ChangeOperation.update => 'UPDATE',
        ChangeOperation.delete => 'DELETE',
      };

  /// Record a local change so it can be pushed later.
  Future<void> recordLocalChange({
    required int companyId,
    required String table,
    required ChangeOperation operation,
    required int recordId,
    required Map<String, dynamic> data,
  }) async {
    final change = SyncChange()
      ..companyId = companyId
      ..table = table
      ..operation = operation
      ..recordId = recordId
      ..data = jsonEncode(data)
      ..createdAt = DateTime.now()
      ..synced = false
      ..deviceId = deviceId;

    await _isar.writeTxn(() async {
      await _isar.syncChanges.put(change);
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // APPLY CHANGES FROM SERVER → LOCAL ISAR
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _applyChanges(List<dynamic> changes,
      {int? localCompanyId}) async {
    for (final raw in changes) {
      Map<String, dynamic> change;
      try {
        change = raw as Map<String, dynamic>;
      } catch (_) {
        continue; // skip if top-level change is not a map
      }

      final table = change['table'] as String;
      final operation = change['operation'] as String;
      final recordId = change['record_id'] as int;

      // Deep copy data and remap server company_id → local company_id
      Map<String, dynamic> data;
      try {
        final rawData = change['data'];
        if (rawData is String) {
          final decoded = jsonDecode(rawData);
          if (decoded is! Map<String, dynamic>) {
            debugPrint(
                '[Sync] Skipping $table#$recordId – data is not a map (String)');
            continue;
          }
          data = Map<String, dynamic>.from(decoded);
        } else if (rawData is Map) {
          data = Map<String, dynamic>.from(rawData);
        } else {
          debugPrint(
              '[Sync] Skipping $table#$recordId – unexpected data type: ${rawData.runtimeType}');
          continue;
        }
      } catch (e) {
        debugPrint(
            '[Sync] Skipping $table#$recordId – failed to parse data: $e');
        continue;
      }

      if (localCompanyId != null && data.containsKey('company_id')) {
        data['company_id'] = localCompanyId;
      }

      try {
        switch (table) {
          case 'parties':
            await _applyPartyChange(operation, data, recordId);
          case 'products':
            await _applyProductChange(operation, data, recordId);
          case 'invoices':
            await _applyInvoiceChange(operation, data, recordId);
          case 'transactions':
            await _applyTransactionChange(operation, data, recordId);
          case 'transaction_lines':
            await _applyTransactionLineChange(operation, data, recordId);
          case 'account_transactions':
            await _applyAccountTransactionChange(operation, data, recordId);
          case 'payment_accounts':
            await _applyPaymentAccountChange(operation, data, recordId);
          case 'payment_ins':
            await _applyPaymentInChange(operation, data, recordId);
          case 'payment_in_lines':
            await _applyPaymentInLineChange(operation, data, recordId);
          case 'payment_outs':
            await _applyPaymentOutChange(operation, data, recordId);
          case 'payment_out_lines':
            await _applyPaymentOutLineChange(operation, data, recordId);
          case 'accounts':
            await _applyAccountChange(operation, data, recordId);
          case 'stock_ledgers':
            await _applyStockLedgerChange(operation, data, recordId);
          case 'units_of_measure':
            await _applyUomChange(operation, data, recordId);
          case 'item_categories':
            await _applyItemCategoryChange(operation, data, recordId);
          default:
            break; // ignore unknown tables
        }
      } catch (e) {
        // log the error — one bad record should not halt the rest
        debugPrint(
            '[Sync] Failed to apply change for table=$table op=$operation id=$recordId: $e');
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _asBool(dynamic v) => v == true || v == 1;

  double _asDouble(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

  DateTime _asDate(dynamic v) =>
      v == null ? DateTime.now() : DateTime.parse(v as String);

  DateTime? _asDateNullable(dynamic v) =>
      v == null ? null : DateTime.parse(v as String);

  // ── Party ─────────────────────────────────────────────────────────────────

  Future<void> _applyPartyChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.partys.delete(id));
      return;
    }
    final partyTypeStr = d['party_type'] as String?;
    final party = Party()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..name = d['name'] as String
      ..partyType = partyTypeStr != null
          ? PartyType.values.byName(partyTypeStr)
          : PartyType.customer
      ..phone = d['phone'] as String?
      ..email = d['email'] as String?
      ..address = d['address'] as String?
      ..openingBalance = _asDouble(d['opening_balance'])
      ..creditLimit = _asDouble(d['credit_limit'])
      ..paymentTermsDays = (d['payment_terms_days'] as int?) ?? 0
      ..isActive = _asBool(d['is_active'])
      ..createdAt = _asDate(d['created_at']);
    await _isar.writeTxn(() => _isar.partys.put(party));
  }

  // ── Product ───────────────────────────────────────────────────────────────

  Future<void> _applyProductChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar
          .writeTxn(() => _isar.products.filter().idEqualTo(id).deleteFirst());
      return;
    }
    final product = Product()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..sku = d['sku'] as String? ?? ''
      ..name = d['name'] as String
      ..categoryId = d['category_id'] as int?
      ..uomId = d['uom_id'] as int?
      ..isTracked = _asBool(d['is_tracked'])
      ..lastCost = _asDouble(d['last_cost'])
      ..salePrice = _asDouble(d['sale_price'])
      ..openingQty = _asDouble(d['opening_qty'])
      ..isActive = _asBool(d['is_active']);
    await _isar.writeTxn(() => _isar.products.put(product));
  }

  // ── Invoice ───────────────────────────────────────────────────────────────

  Future<void> _applyInvoiceChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.invoices.delete(id));
      return;
    }
    final invoice = Invoice()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..transactionId = d['transaction_id'] as int
      ..invoiceType = InvoiceType.values.byName(d['invoice_type'] as String)
      ..partyId = d['party_id'] as int
      ..invoiceDate = _asDate(d['invoice_date'])
      ..dueDate = _asDateNullable(d['due_date'])
      ..grandTotal = _asDouble(d['grand_total'])
      ..status = d['status'] as String?
      ..previousBalance = _asDouble(d['previous_balance'])
      ..paidAmount = _asDouble(d['paid_amount'])
      ..remainingBalance = _asDouble(d['remaining_balance'])
      ..invoiceNumber = d['invoice_number'] as String?;
    await _isar.writeTxn(() => _isar.invoices.put(invoice));
  }

  // ── Transaction ───────────────────────────────────────────────────────────

  Future<void> _applyTransactionChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.transactions.delete(id));
      return;
    }
    final txn = tm.Transaction()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..type = tm.TransactionType.values.byName(d['type'] as String)
      ..date = _asDate(d['date'])
      ..referenceNo = d['reference_no'] as String
      ..partyId = d['party_id'] as int?
      ..cashBankAccount = d['cash_bank_account'] as String?
      ..totalAmount = _asDouble(d['total_amount'])
      ..isPosted = _asBool(d['is_posted'])
      ..createdByUserId = d['created_by_user_id'] as int?
      ..createdAt = _asDate(d['created_at']);
    await _isar.writeTxn(() => _isar.transactions.put(txn));
  }

  // ── TransactionLine ───────────────────────────────────────────────────────

  Future<void> _applyTransactionLineChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.transactionLines.delete(id));
      return;
    }
    final line = tm.TransactionLine()
      ..id = d['id'] as int
      ..transactionId = d['transaction_id'] as int
      ..productId = d['product_id'] as int?
      ..expenseCategoryId = d['expense_category_id'] as int?
      ..partyId = d['party_id'] as int?
      ..description = d['description'] as String?
      ..quantity = _asDouble(d['quantity'])
      ..unitPrice = _asDouble(d['unit_price'])
      ..lineAmount = _asDouble(d['line_amount']);
    await _isar.writeTxn(() => _isar.transactionLines.put(line));
  }

  // ── AccountTransaction ────────────────────────────────────────────────────

  Future<void> _applyAccountTransactionChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.accountTransactions.delete(id));
      return;
    }
    final entry = am.AccountTransaction()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..accountId = d['account_id'] as int
      ..transactionType =
          am.TransactionType.values.byName(d['transaction_type'] as String)
      ..referenceId = d['reference_id'] as int
      ..transactionDate = _asDate(d['transaction_date'])
      ..debit = _asDouble(d['debit'])
      ..credit = _asDouble(d['credit'])
      ..runningBalance = _asDouble(d['running_balance'])
      ..description = d['description'] as String?
      ..referenceNo = d['reference_no'] as String?
      ..partyId = d['party_id'] as int?
      ..createdAt = _asDate(d['created_at']);
    await _isar.writeTxn(() => _isar.accountTransactions.put(entry));
  }

  // ── PaymentAccount ────────────────────────────────────────────────────────

  Future<void> _applyPaymentAccountChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.paymentAccounts.delete(id));
      return;
    }
    final account = PaymentAccount()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..accountType =
          PaymentAccountType.values.byName(d['account_type'] as String)
      ..accountName = d['account_name'] as String
      ..bankName = d['bank_name'] as String?
      ..accountNumber = d['account_number'] as String?
      ..ifscCode = d['ifsc_code'] as String?
      ..icon = d['icon'] as String?
      ..isActive = _asBool(d['is_active'])
      ..isDefault = _asBool(d['is_default'])
      ..createdAt = _asDate(d['created_at']);
    await _isar.writeTxn(() => _isar.paymentAccounts.put(account));
  }

  // ── PaymentIn ─────────────────────────────────────────────────────────────

  Future<void> _applyPaymentInChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.paymentIns.delete(id));
      return;
    }
    final p = PaymentIn()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..receiptNo = d['receipt_no'] as String
      ..receiptDate = _asDate(d['receipt_date'])
      ..partyId = d['party_id'] as int
      ..totalAmount = _asDouble(d['total_amount'])
      ..description = d['description'] as String?
      ..attachmentPath = d['attachment_path'] as String?
      ..createdAt = _asDate(d['created_at'])
      ..createdByUserId = d['created_by_user_id'] as int?;
    await _isar.writeTxn(() => _isar.paymentIns.put(p));
  }

  // ── PaymentInLine ─────────────────────────────────────────────────────────

  Future<void> _applyPaymentInLineChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.paymentInLines.delete(id));
      return;
    }
    final line = PaymentInLine()
      ..id = d['id'] as int
      ..paymentInId = d['payment_in_id'] as int
      ..paymentAccountId = d['payment_account_id'] as int
      ..amount = _asDouble(d['amount'])
      ..referenceNo = d['reference_no'] as String?
      ..createdAt = _asDate(d['created_at']);
    await _isar.writeTxn(() => _isar.paymentInLines.put(line));
  }

  // ── PaymentOut ────────────────────────────────────────────────────────────

  Future<void> _applyPaymentOutChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.paymentOuts.delete(id));
      return;
    }
    final p = PaymentOut()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..voucherNo = d['voucher_no'] as String
      ..voucherDate = _asDate(d['voucher_date'])
      ..partyId = d['party_id'] as int
      ..totalAmount = _asDouble(d['total_amount'])
      ..description = d['description'] as String?
      ..attachmentPath = d['attachment_path'] as String?
      ..createdAt = _asDate(d['created_at'])
      ..createdByUserId = d['created_by_user_id'] as int?;
    await _isar.writeTxn(() => _isar.paymentOuts.put(p));
  }

  // ── PaymentOutLine ────────────────────────────────────────────────────────

  Future<void> _applyPaymentOutLineChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.paymentOutLines.delete(id));
      return;
    }
    final line = PaymentOutLine()
      ..id = d['id'] as int
      ..paymentOutId = d['payment_out_id'] as int
      ..paymentAccountId = d['payment_account_id'] as int
      ..amount = _asDouble(d['amount'])
      ..referenceNo = d['reference_no'] as String?
      ..createdAt = _asDate(d['created_at']);
    await _isar.writeTxn(() => _isar.paymentOutLines.put(line));
  }

  // ── StockLedger ───────────────────────────────────────────────────────────

  Future<void> _applyStockLedgerChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.stockLedgers.delete(id));
      return;
    }
    final entry = StockLedger()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..productId = d['product_id'] as int
      ..date = _asDate(d['date'])
      ..movementType =
          StockMovementType.values.byName(d['movement_type'] as String)
      ..quantityDelta = _asDouble(d['quantity_delta'])
      ..unitCost = _asDouble(d['unit_cost'])
      ..totalCost = _asDouble(d['total_cost'])
      ..transactionId = d['transaction_id'] as int?
      ..invoiceId = d['invoice_id'] as int?;
    await _isar.writeTxn(() => _isar.stockLedgers.put(entry));
  }

  // ── UnitOfMeasure ─────────────────────────────────────────────────────────

  Future<void> _applyUomChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.unitOfMeasures.delete(id));
      return;
    }
    final uom = UnitOfMeasure()
      ..id = d['id'] as int
      ..name = d['name'] as String
      ..abbrev = d['abbrev'] as String;
    await _isar.writeTxn(() => _isar.unitOfMeasures.put(uom));
  }

  // ── Account ───────────────────────────────────────────────────────────────

  Future<void> _applyAccountChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.accounts.delete(id));
      return;
    }
    final accountTypeStr = d['account_type'] as String?;
    final account = am.Account()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..name = d['name'] as String
      ..code = d['code'] as String? ?? ''
      ..accountType = accountTypeStr != null
          ? am.AccountType.values.byName(accountTypeStr)
          : am.AccountType.asset
      ..parentAccountId = d['parent_account_id'] as int?
      ..description = d['description'] as String?
      ..openingBalance = _asDouble(d['opening_balance'])
      ..currentBalance = _asDouble(d['current_balance'])
      ..isSystem = _asBool(d['is_system'])
      ..isActive = _asBool(d['is_active'])
      ..createdAt = _asDate(d['created_at']);
    await _isar.writeTxn(() => _isar.accounts.put(account));
  }

  // ── ItemCategory ──────────────────────────────────────────────────────────

  Future<void> _applyItemCategoryChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.writeTxn(() => _isar.itemCategorys.delete(id));
      return;
    }
    final cat = ItemCategory()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..name = d['name'] as String
      ..parentCategoryId = d['parent_category_id'] as int?;
    await _isar.writeTxn(() => _isar.itemCategorys.put(cat));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // POST-PUSH: MARK LOCAL CHANGES AS SYNCED
  // ──────────────────────────────────────────────────────────────────────────

  /// After a successful push, mark only the pushed SyncChange records as
  /// synced. Scoping to [syncChangeIds] prevents cross-company contamination
  /// where a push for Company A would accidentally mark Company B's pending
  /// records as synced.
  Future<void> _updateLocalIds(
      Map<String, dynamic> idMappings, List<int> syncChangeIds) async {
    if (syncChangeIds.isEmpty) return;

    await _isar.writeTxn(() async {
      final records = await _isar.syncChanges.getAll(syncChangeIds);
      final toUpdate = records.whereType<SyncChange>().toList();
      for (final c in toUpdate) {
        c.synced = true;
      }
      if (toUpdate.isNotEmpty) {
        await _isar.syncChanges.putAll(toUpdate);
      }
    });
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Value objects
// ──────────────────────────────────────────────────────────────────────────────

class SyncResult {
  final bool success;
  final int? changesApplied;
  final int? currentVersion;
  final int? conflicts;
  final String? error;

  SyncResult({
    required this.success,
    this.changesApplied,
    this.currentVersion,
    this.conflicts,
    this.error,
  });
}

class SyncStatus {
  final String deviceId;
  final int lastSyncVersion;
  final int currentVersion;
  final int pendingChanges;
  final bool isSynced;
  final DateTime? lastSyncAt;

  SyncStatus({
    required this.deviceId,
    required this.lastSyncVersion,
    required this.currentVersion,
    required this.pendingChanges,
    required this.isSynced,
    this.lastSyncAt,
  });

  bool get hasChanges => pendingChanges > 0;
}
