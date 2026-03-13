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
  static const String _companySyncVersionPrefix = 'last_sync_version_company_';
  static const Set<String> _globalSyncTables = {'units_of_measure'};

  void _logSyncDebug(String message) {
    if (kDebugMode) {
      debugPrint('[SyncService] $message');
    }
  }

  String get deviceId {
    var id = prefs.getString('device_id');
    if (id == null) {
      id = const Uuid().v4();
      prefs.setString('device_id', id);
    }
    return id;
  }

  int _getLastSyncVersionForCompany(int companyId) {
    return prefs.getInt('$_companySyncVersionPrefix$companyId') ?? 0;
  }

  Future<void> _setLastSyncVersionForCompany(int companyId, int version) async {
    await prefs.setInt('$_companySyncVersionPrefix$companyId', version);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ──────────────────────────────────────────────────────────────────────────

  /// Pull changes from server and apply them to local Isar.
  Future<SyncResult> pullChanges({
    required int companyId,
    int? serverCompanyId,
    List<String>? tables,
    int? lastVersionOverride,
  }) async {
    try {
      final lastVersion =
          lastVersionOverride ?? _getLastSyncVersionForCompany(companyId);

      _logSyncDebug(
        'pullChanges:start companyId=$companyId serverCompanyId=${serverCompanyId ?? companyId} lastVersion=$lastVersion deviceId=$deviceId',
      );

      final response = await apiClient.post('/api/sync/pull', {
        'company_id': serverCompanyId ?? companyId,
        'device_id': deviceId,
        'last_version': lastVersion,
        if (tables != null) 'tables': tables,
      });

      if (response['success'] == true) {
        final changes = response['changes'] as List;
        final currentVersion = response['current_version'] as int;

        try {
          await _applyChanges(changes, localCompanyId: companyId);
        } catch (e) {
          // Recovery path for stale clients that may have advanced cursor while
          // missing records due older apply/parsing bugs.
          final canFallbackToFullResync =
              lastVersion > 0 && lastVersionOverride == null;
          if (canFallbackToFullResync) {
            debugPrint(
              '[Sync] apply failed at version $lastVersion for company=$companyId; retrying with full resync from version 0. Error: $e',
            );
            await _setLastSyncVersionForCompany(companyId, 0);
            return pullChanges(
              companyId: companyId,
              serverCompanyId: serverCompanyId,
              tables: tables,
              lastVersionOverride: 0,
            );
          }
          rethrow;
        }

        await _setLastSyncVersionForCompany(companyId, currentVersion);

        _logSyncDebug(
          'pullChanges:success companyId=$companyId applied=${changes.length} currentVersion=$currentVersion',
        );

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
      _logSyncDebug('pullChanges:error companyId=$companyId error=$e');
      return SyncResult(success: false, error: e.toString());
    }
  }

  /// Post-login bootstrap:
  /// 1) Download companies linked to authenticated user
  /// 2) Upsert companies into local Isar
  /// 3) Pull remote data for each active company
  Future<LoginBootstrapResult> bootstrapUserDataOnLogin() async {
    if (apiClient.token == null) {
      return LoginBootstrapResult(
        success: false,
        error: 'Missing auth token for bootstrap sync.',
      );
    }

    try {
      final response = await apiClient.get('/api/companies');
      if (response['success'] != true || response['companies'] is! List) {
        return LoginBootstrapResult(
          success: false,
          error: response['message']?.toString() ??
              'Failed to load companies from server.',
        );
      }

      final companies = (response['companies'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final userId = prefs.getInt('user_id') ?? 0;
      int syncedCompanies = 0;
      int totalChanges = 0;
      final syncErrors = <String>[];
      final serverLinkedLocalCompanyIds = <int>{};

      for (final companyData in companies) {
        final serverCompanyId = companyData['id'] as int?;
        final companyName = companyData['name']?.toString();

        if (serverCompanyId == null ||
            companyName == null ||
            companyName.isEmpty) {
          continue;
        }

        int localCompanyId = serverCompanyId;
        await _isar.writeTxn(() async {
          final existingById = await _isar.companys.get(serverCompanyId);
          final existingByName = await _isar.companys
              .filter()
              .nameEqualTo(companyName, caseSensitive: false)
              .findFirst();

          final company = existingById ??
              existingByName ??
              (Company()
                ..id = serverCompanyId
                ..createdAt = DateTime.now());

          company.subscriberId = userId;
          company.name = companyName;
          company.primaryCurrency =
              companyData['primary_currency']?.toString() ?? 'PKR';
          company.financialYearStartMonth =
              companyData['financial_year_start_month'] as int? ?? 1;
          company.isActive = _asBool(companyData['is_active']);

          await _isar.companys.put(company);
          localCompanyId = company.id;
        });

        serverLinkedLocalCompanyIds.add(localCompanyId);
        await prefs.setInt(
            'server_company_id_$localCompanyId', serverCompanyId);

        if (_asBool(companyData['is_active'])) {
          final syncResult = await pullChanges(
            companyId: localCompanyId,
            serverCompanyId: serverCompanyId,
          );

          if (syncResult.success) {
            syncedCompanies++;
            totalChanges += syncResult.changesApplied ?? 0;
          } else {
            syncErrors.add(
                'Company $companyName sync failed: ${syncResult.error ?? 'Unknown error'}');
          }
        }
      }

      await _isar.writeTxn(() async {
        final localCompanies =
            await _isar.companys.filter().subscriberIdEqualTo(userId).findAll();
        for (final company in localCompanies) {
          if (!serverLinkedLocalCompanyIds.contains(company.id) &&
              company.isActive) {
            company.isActive = false;
            await _isar.companys.put(company);
          }
        }
      });

      return LoginBootstrapResult(
        success: true,
        companiesDownloaded: companies.length,
        companiesSynced: syncedCompanies,
        changesApplied: totalChanges,
        syncErrors: syncErrors,
      );
    } catch (e) {
      return LoginBootstrapResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Push unsynced local SyncChange records to the server.
  Future<SyncResult> pushChanges({
    required int companyId,
    int? serverCompanyId,
    required List<Map<String, dynamic>> changes,
  }) async {
    try {
      _logSyncDebug(
        'pushChanges:start companyId=$companyId serverCompanyId=${serverCompanyId ?? companyId} localChanges=${changes.length} deviceId=$deviceId',
      );

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

        _logSyncDebug(
          'pushChanges:success companyId=$companyId currentVersion=${currentVersion?.toString() ?? '-'} conflicts=$conflictsCount markedSynced=${syncChangeIds.length}',
        );

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
      _logSyncDebug('pushChanges:error companyId=$companyId error=$e');
      return SyncResult(success: false, error: e.toString());
    }
  }

  /// Full bidirectional sync: pull first, then push local changes.
  Future<SyncResult> fullSync(int companyId) async {
    _logSyncDebug('fullSync:start companyId=$companyId');

    // Ensure auth token — sync needs a server account.
    final hasToken = await ensureServerToken();
    if (!hasToken) {
      _logSyncDebug('fullSync:abort no token companyId=$companyId');
      return SyncResult(
        success: false,
        error:
            'Server session unavailable for sync. Connect internet and sign in once with your server account.',
      );
    }

    // Register or find the company on the server, get server-side company ID
    final serverCompanyId = await _ensureServerCompanyId(companyId);
    if (serverCompanyId == null) {
      _logSyncDebug('fullSync:abort no serverCompanyId companyId=$companyId');
      return SyncResult(
        success: false,
        error: 'Failed to register company on server. Check your connection.',
      );
    }

    _logSyncDebug(
      'fullSync:resolved mapping localCompanyId=$companyId serverCompanyId=$serverCompanyId',
    );

    final pullResult = await pullChanges(
        companyId: companyId, serverCompanyId: serverCompanyId);
    if (!pullResult.success) {
      _logSyncDebug(
        'fullSync:pull-before-push failed companyId=$companyId error=${pullResult.error}',
      );
      return SyncResult(
        success: false,
        error: 'pull-before-push: ${pullResult.error ?? 'Unknown error'}',
      );
    }

    final localChanges = await _getLocalChanges(companyId);
    _logSyncDebug(
      'fullSync:localChanges companyId=$companyId count=${localChanges.length}',
    );

    if (localChanges.isEmpty) {
      _logSyncDebug('fullSync:done companyId=$companyId (pull only)');
      return pullResult;
    }

    final pushResult = await pushChanges(
        companyId: companyId,
        serverCompanyId: serverCompanyId,
        changes: localChanges);

    if (!pushResult.success) {
      _logSyncDebug(
        'fullSync:push failed companyId=$companyId error=${pushResult.error}',
      );
      return SyncResult(
        success: false,
        error: 'push: ${pushResult.error ?? 'Unknown error'}',
      );
    }

    // Pull again so this device immediately receives any changes that happened
    // during the same sync window (including updates from other devices).
    final pullAfterPush = await pullChanges(
      companyId: companyId,
      serverCompanyId: serverCompanyId,
    );

    if (!pullAfterPush.success) {
      _logSyncDebug(
        'fullSync:pull-after-push failed companyId=$companyId error=${pullAfterPush.error}',
      );
      return SyncResult(
        success: false,
        error: 'pull-after-push: ${pullAfterPush.error ?? 'Unknown error'}',
      );
    }

    _logSyncDebug(
      'fullSync:done companyId=$companyId applied=${(pullResult.changesApplied ?? 0) + (pullAfterPush.changesApplied ?? 0)} finalVersion=${pullAfterPush.currentVersion ?? pushResult.currentVersion}',
    );

    return SyncResult(
      success: true,
      changesApplied: (pullResult.changesApplied ?? 0) +
          (pullAfterPush.changesApplied ?? 0),
      currentVersion: pullAfterPush.currentVersion ?? pushResult.currentVersion,
      conflicts: pushResult.conflicts,
    );
  }

  /// Ensure we have a valid server auth token.
  /// If missing, attempts automatic login using stored server credentials.
  Future<bool> ensureServerToken() async {
    if (apiClient.token != null && apiClient.token!.isNotEmpty) {
      return true;
    }

    final email =
        prefs.getString('server_email') ?? prefs.getString('user_email');
    final password = prefs.getString('server_password');
    if (email == null ||
        email.isEmpty ||
        password == null ||
        password.isEmpty) {
      return false;
    }

    try {
      final response = await apiClient.post('/api/auth/login', {
        'email': email,
        'password': password,
        'device_id': deviceId,
      }).timeout(const Duration(seconds: 8));

      if (response['success'] == true && response['token'] != null) {
        await prefs.setString('auth_token', response['token'].toString());
        await prefs.setString('server_email', email);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Attempt token refresh + data sync for all active local companies.
  /// Safe to call on app startup; returns false silently when offline.
  Future<bool> autoLoginAndSyncAllLocalCompanies() async {
    final hasToken = await ensureServerToken();
    if (!hasToken) return false;

    try {
      final companies =
          await _isar.companys.filter().isActiveEqualTo(true).findAll();
      for (final company in companies) {
        await fullSync(company.id);
      }
      return true;
    } catch (_) {
      return false;
    }
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

    return allUnsynced.map((c) {
      final decodedData = jsonDecode(c.data);
      final data = decodedData is Map
          ? Map<String, dynamic>.from(decodedData)
          : <String, dynamic>{};

      if (_globalSyncTables.contains(c.table)) {
        data.remove('company_id');
      }

      return {
        'local_id': 'local_${c.id}', // stable reference for id_mappings
        'op_uuid': _operationUuidForChange(c),
        'table': c.table,
        'record_id': c.recordId,
        'operation': _opToString(c.operation),
        'data': data,
        'timestamp': c.createdAt.toIso8601String(),
      };
    }).toList();
  }

  String _operationUuidForChange(SyncChange change) {
    return '${deviceId}_${change.id}';
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
    final parsedChanges = <_ParsedSyncChange>[];

    for (final raw in changes) {
      Map<String, dynamic> change;
      try {
        change = raw as Map<String, dynamic>;
      } catch (_) {
        continue; // skip if top-level change is not a map
      }

      final table = change['table'] as String;
      final operation = change['operation'] as String;
      final recordId = _asInt(change['record_id']);

      // Deep copy data and remap server company_id → local company_id
      Map<String, dynamic> data;
      try {
        final rawData = change['data'];
        if (rawData is String) {
          final decoded = jsonDecode(rawData);
          if (decoded is! Map<String, dynamic>) {
            throw FormatException(
              '[Sync] Invalid change payload for $table#$recordId: decoded string is not a map',
            );
          }
          data = Map<String, dynamic>.from(decoded);
        } else if (rawData is Map) {
          data = Map<String, dynamic>.from(rawData);
        } else {
          throw FormatException(
            '[Sync] Invalid change payload for $table#$recordId: unexpected data type ${rawData.runtimeType}',
          );
        }
      } catch (e) {
        throw FormatException(
          '[Sync] Failed to parse change data for $table#$recordId: $e',
        );
      }

      if (localCompanyId != null && data.containsKey('company_id')) {
        data['company_id'] = localCompanyId;
      }

      parsedChanges.add(_ParsedSyncChange(
        table: table,
        operation: operation,
        recordId: recordId,
        data: data,
      ));
    }

    await _isar.writeTxn(() async {
      for (final change in parsedChanges) {
        try {
          switch (change.table) {
            case 'parties':
              await _applyPartyChange(
                  change.operation, change.data, change.recordId);
            case 'products':
              await _applyProductChange(
                  change.operation, change.data, change.recordId);
            case 'invoices':
              await _applyInvoiceChange(
                  change.operation, change.data, change.recordId);
            case 'transactions':
              await _applyTransactionChange(
                  change.operation, change.data, change.recordId);
            case 'transaction_lines':
              await _applyTransactionLineChange(
                  change.operation, change.data, change.recordId);
            case 'account_transactions':
              await _applyAccountTransactionChange(
                  change.operation, change.data, change.recordId);
            case 'payment_accounts':
              await _applyPaymentAccountChange(
                  change.operation, change.data, change.recordId);
            case 'payment_ins':
              await _applyPaymentInChange(
                  change.operation, change.data, change.recordId);
            case 'payment_in_lines':
              await _applyPaymentInLineChange(
                  change.operation, change.data, change.recordId);
            case 'payment_outs':
              await _applyPaymentOutChange(
                  change.operation, change.data, change.recordId);
            case 'payment_out_lines':
              await _applyPaymentOutLineChange(
                  change.operation, change.data, change.recordId);
            case 'accounts':
              await _applyAccountChange(
                  change.operation, change.data, change.recordId);
            case 'stock_ledgers':
              await _applyStockLedgerChange(
                  change.operation, change.data, change.recordId);
            case 'units_of_measure':
              await _applyUomChange(
                  change.operation, change.data, change.recordId);
            case 'item_categories':
              await _applyItemCategoryChange(
                  change.operation, change.data, change.recordId);
            default:
              break; // ignore unknown tables
          }
        } catch (e) {
          throw Exception(
            '[Sync] Failed to apply change for table=${change.table} op=${change.operation} id=${change.recordId}: $e',
          );
        }
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _asBool(dynamic v) => v == true || v == 1;

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final parsed = double.tryParse(v.trim());
      return parsed ?? 0.0;
    }
    return 0.0;
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final parsed = int.tryParse(v.trim());
      return parsed ?? fallback;
    }
    return fallback;
  }

  DateTime _asDate(dynamic v) =>
      v == null ? DateTime.now() : DateTime.parse(v as String);

  DateTime? _asDateNullable(dynamic v) =>
      v == null ? null : DateTime.parse(v as String);

  // ── Party ─────────────────────────────────────────────────────────────────

  Future<void> _applyPartyChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.partys.delete(id);
      return;
    }
    final partyTypeStr = d['party_type'] as String?;
    final party = Party()
      ..id = _asInt(d['id'], fallback: id)
      ..companyId = _asInt(d['company_id'])
      ..name = d['name'] as String
      ..partyType = partyTypeStr != null
          ? PartyType.values.byName(partyTypeStr)
          : PartyType.customer
      ..phone = d['phone'] as String?
      ..email = d['email'] as String?
      ..address = d['address'] as String?
      ..openingBalance = _asDouble(d['opening_balance'])
      ..creditLimit = _asDouble(d['credit_limit'])
      ..paymentTermsDays = _asInt(d['payment_terms_days'])
      ..isActive = _asBool(d['is_active'])
      ..createdAt = _asDate(d['created_at']);
    await _isar.partys.put(party);
  }

  // ── Product ───────────────────────────────────────────────────────────────

  Future<void> _applyProductChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.products.filter().idEqualTo(id).deleteFirst();
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
    await _isar.products.put(product);
  }

  // ── Invoice ───────────────────────────────────────────────────────────────

  Future<void> _applyInvoiceChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.invoices.delete(id);
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
    await _isar.invoices.put(invoice);
  }

  // ── Transaction ───────────────────────────────────────────────────────────

  Future<void> _applyTransactionChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.transactions.delete(id);
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
    await _isar.transactions.put(txn);
  }

  // ── TransactionLine ───────────────────────────────────────────────────────

  Future<void> _applyTransactionLineChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.transactionLines.delete(id);
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
    await _isar.transactionLines.put(line);
  }

  // ── AccountTransaction ────────────────────────────────────────────────────

  Future<void> _applyAccountTransactionChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.accountTransactions.delete(id);
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
    await _isar.accountTransactions.put(entry);
  }

  // ── PaymentAccount ────────────────────────────────────────────────────────

  Future<void> _applyPaymentAccountChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.paymentAccounts.delete(id);
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
    await _isar.paymentAccounts.put(account);
  }

  // ── PaymentIn ─────────────────────────────────────────────────────────────

  Future<void> _applyPaymentInChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.paymentIns.delete(id);
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
    await _isar.paymentIns.put(p);
  }

  // ── PaymentInLine ─────────────────────────────────────────────────────────

  Future<void> _applyPaymentInLineChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.paymentInLines.delete(id);
      return;
    }
    final line = PaymentInLine()
      ..id = d['id'] as int
      ..paymentInId = d['payment_in_id'] as int
      ..paymentAccountId = d['payment_account_id'] as int
      ..amount = _asDouble(d['amount'])
      ..referenceNo = d['reference_no'] as String?
      ..createdAt = _asDate(d['created_at']);
    await _isar.paymentInLines.put(line);
  }

  // ── PaymentOut ────────────────────────────────────────────────────────────

  Future<void> _applyPaymentOutChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.paymentOuts.delete(id);
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
    await _isar.paymentOuts.put(p);
  }

  // ── PaymentOutLine ────────────────────────────────────────────────────────

  Future<void> _applyPaymentOutLineChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.paymentOutLines.delete(id);
      return;
    }
    final line = PaymentOutLine()
      ..id = d['id'] as int
      ..paymentOutId = d['payment_out_id'] as int
      ..paymentAccountId = d['payment_account_id'] as int
      ..amount = _asDouble(d['amount'])
      ..referenceNo = d['reference_no'] as String?
      ..createdAt = _asDate(d['created_at']);
    await _isar.paymentOutLines.put(line);
  }

  // ── StockLedger ───────────────────────────────────────────────────────────

  Future<void> _applyStockLedgerChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.stockLedgers.delete(id);
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
    await _isar.stockLedgers.put(entry);
  }

  // ── UnitOfMeasure ─────────────────────────────────────────────────────────

  Future<void> _applyUomChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.unitOfMeasures.delete(id);
      return;
    }
    final uom = UnitOfMeasure()
      ..id = d['id'] as int
      ..name = d['name'] as String
      ..abbrev = d['abbrev'] as String;
    await _isar.unitOfMeasures.put(uom);
  }

  // ── Account ───────────────────────────────────────────────────────────────

  Future<void> _applyAccountChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.accounts.delete(id);
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
    await _isar.accounts.put(account);
  }

  // ── ItemCategory ──────────────────────────────────────────────────────────

  Future<void> _applyItemCategoryChange(
      String op, Map<String, dynamic> d, int id) async {
    if (op == 'DELETE') {
      await _isar.itemCategorys.delete(id);
      return;
    }
    final cat = ItemCategory()
      ..id = d['id'] as int
      ..companyId = d['company_id'] as int
      ..name = d['name'] as String
      ..parentCategoryId = d['parent_category_id'] as int?;
    await _isar.itemCategorys.put(cat);
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

class LoginBootstrapResult {
  final bool success;
  final int companiesDownloaded;
  final int companiesSynced;
  final int changesApplied;
  final List<String> syncErrors;
  final String? error;

  LoginBootstrapResult({
    required this.success,
    this.companiesDownloaded = 0,
    this.companiesSynced = 0,
    this.changesApplied = 0,
    this.syncErrors = const [],
    this.error,
  });

  bool get hasWarnings => syncErrors.isNotEmpty;
}

class _ParsedSyncChange {
  final String table;
  final String operation;
  final int recordId;
  final Map<String, dynamic> data;

  _ParsedSyncChange({
    required this.table,
    required this.operation,
    required this.recordId,
    required this.data,
  });
}
