import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:matrix_accounts/core/database/isar_service.dart';
import 'package:matrix_accounts/core/services/api_client.dart';
import 'package:matrix_accounts/core/services/sync_service.dart';
import 'package:matrix_accounts/data/models/account_models.dart';
import 'package:matrix_accounts/data/models/sync_change_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    required SharedPreferences prefs,
    required this.onPost,
  }) : super(baseUrl: 'http://localhost', prefs: prefs);

  final Future<Map<String, dynamic>> Function(
    String endpoint,
    Map<String, dynamic> data,
  ) onPost;

  @override
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data,
  ) {
    return onPost(endpoint, data);
  }
}

class _FakeIsarService extends IsarService {
  _FakeIsarService(this._testIsar);

  final Isar _testIsar;

  @override
  Isar get isar => _testIsar;

  @override
  Future<void> init() async {}

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Isar? isar;
  Directory? tempDir;
  late SharedPreferences prefs;

  setUpAll(() async {
    await Isar.initializeIsarCore(
      libraries: {
        Abi.current():
            'C:/Users/Naeem/AppData/Local/Pub/Cache/hosted/pub.dev/isar_flutter_libs-3.1.0+1/windows/isar.dll',
      },
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'test-token',
      'device_id': 'test-device-1',
      'last_sync_version': 0,
    });
    prefs = await SharedPreferences.getInstance();

    tempDir = Directory.systemTemp.createTempSync('sync_smoke_');
    isar = await Isar.open(
      [
        SyncChangeSchema,
        AccountSchema,
      ],
      directory: tempDir!.path,
      inspector: false,
    );
  });

  tearDown(() async {
    if (isar != null) {
      await isar!.close(deleteFromDisk: true);
      isar = null;
    }
    if (tempDir != null && tempDir!.existsSync()) {
      tempDir!.deleteSync(recursive: true);
      tempDir = null;
    }
  });

  test('pushChanges marks only pushed SyncChange records as synced', () async {
    final db = isar!;
    late int pushedId1;
    late int pushedId2;
    late int untouchedId;

    await db.writeTxn(() async {
      pushedId1 = await db.syncChanges.put(
        SyncChange()
          ..companyId = 1
          ..table = 'products'
          ..operation = ChangeOperation.create
          ..recordId = 101
          ..data = '{"id":101}'
          ..createdAt = DateTime.now()
          ..synced = false
          ..deviceId = 'local',
      );

      pushedId2 = await db.syncChanges.put(
        SyncChange()
          ..companyId = 1
          ..table = 'accounts'
          ..operation = ChangeOperation.update
          ..recordId = 202
          ..data = '{"id":202}'
          ..createdAt = DateTime.now()
          ..synced = false
          ..deviceId = 'local',
      );

      untouchedId = await db.syncChanges.put(
        SyncChange()
          ..companyId = 1
          ..table = 'parties'
          ..operation = ChangeOperation.create
          ..recordId = 303
          ..data = '{"id":303}'
          ..createdAt = DateTime.now()
          ..synced = false
          ..deviceId = 'local',
      );
    });

    final apiClient = _FakeApiClient(
      prefs: prefs,
      onPost: (endpoint, data) async {
        expect(endpoint, '/api/sync/push');
        return {
          'success': true,
          'id_mappings': <String, dynamic>{},
          'conflicts': <dynamic>[],
          'current_version': 55,
        };
      },
    );

    final service = SyncService(
      apiClient: apiClient,
      isarService: _FakeIsarService(db),
      prefs: prefs,
    );

    final result = await service.pushChanges(
      companyId: 1,
      serverCompanyId: 1,
      changes: [
        {
          'local_id': 'local_$pushedId1',
          'table': 'products',
          'operation': 'CREATE',
          'record_id': 101,
          'data': {'id': 101},
        },
        {
          'local_id': 'local_$pushedId2',
          'table': 'accounts',
          'operation': 'UPDATE',
          'record_id': 202,
          'data': {'id': 202},
        },
      ],
    );

    expect(result.success, isTrue);
    expect(result.currentVersion, 55);

    final records =
        await db.syncChanges.getAll([pushedId1, pushedId2, untouchedId]);
    final rec1 = records[0]!;
    final rec2 = records[1]!;
    final rec3 = records[2]!;

    expect(rec1.synced, isTrue);
    expect(rec2.synced, isTrue);
    expect(rec3.synced, isFalse);
  });

  test('pullChanges applies accounts table create from server', () async {
    final db = isar!;
    final apiClient = _FakeApiClient(
      prefs: prefs,
      onPost: (endpoint, data) async {
        expect(endpoint, '/api/sync/pull');
        return {
          'success': true,
          'changes': [
            {
              'table': 'accounts',
              'operation': 'CREATE',
              'record_id': 9001,
              'data': {
                'id': 9001,
                'company_id': 1,
                'name': 'Remote Cash',
                'code': '1000',
                'account_type': 'asset',
                'parent_account_id': null,
                'description': 'Pulled from server',
                'is_system': true,
                'opening_balance': 0.0,
                'current_balance': 1250.5,
                'is_active': true,
                'created_at': '2026-03-12T10:00:00.000Z',
              },
            },
          ],
          'current_version': 77,
        };
      },
    );

    final service = SyncService(
      apiClient: apiClient,
      isarService: _FakeIsarService(db),
      prefs: prefs,
    );

    final result = await service.pullChanges(companyId: 1, serverCompanyId: 1);

    expect(result.success, isTrue);
    expect(result.currentVersion, 77);

    final account = await db.accounts.get(9001);
    expect(account, isNotNull);
    expect(account!.companyId, 1);
    expect(account.name, 'Remote Cash');
    expect(account.code, '1000');
    expect(account.accountType, AccountType.asset);
    expect(account.currentBalance, 1250.5);

    expect(prefs.getInt('last_sync_version'), 77);
  });
}
