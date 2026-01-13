# Next Steps - Matrix Accounts Sync Implementation

## 🎯 What We've Completed

✅ **Backend (Laravel)**
- 22 database migrations
- 20 Eloquent models
- SyncService with delta sync
- API controllers (Auth, Sync, Party)
- Complete documentation

✅ **Frontend (Flutter)**
- ApiClient service (HTTP client)
- SyncService skeleton
- pubspec.yaml updated with http & uuid

---

## 📋 Choose Your Path

### Path A: Set Up Laravel Backend First (Recommended)

**Time: 30 minutes**

#### Step 1: Install Laravel

```bash
cd laravel_sync

# Option 1: Use setup script (Windows)
setup.bat

# Option 2: Manual installation
composer create-project laravel/laravel . "11.*"
```

#### Step 2: Install Sanctum

```bash
composer require laravel/sanctum
php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider"
```

#### Step 3: Configure Database

Edit `.env`:
```env
DB_DATABASE=matrix_accounts_sync
DB_USERNAME=root
DB_PASSWORD=your_password
```

Create database:
```sql
CREATE DATABASE matrix_accounts_sync;
```

#### Step 4: Copy Our Files

The migration, model, controller, and service files are already created in:
- `database/migrations/` (22 files)
- `app/Models/` (20 files)
- `app/Http/Controllers/Api/` (3 files)
- `app/Services/` (1 file)
- `routes/api.php`

**Make sure these files are in the Laravel project folder.**

#### Step 5: Run Migrations

```bash
php artisan migrate
```

#### Step 6: Test the API

```bash
# Start server
php artisan serve

# In another terminal, test registration
curl -X POST http://localhost:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"admin@test.com\",\"full_name\":\"Admin\",\"password\":\"password123\"}"
```

---

### Path B: Complete Flutter Integration

**Time: 2-3 hours**

#### Step 1: Install Dependencies

```bash
flutter pub get
```

#### Step 2: Configure API Endpoint

Create `lib/core/config/api_config.dart`:

```dart
class ApiConfig {
  // Development
  static const String baseUrl = 'http://localhost:8000';
  
  // Production
  // static const String baseUrl = 'https://api.yourserver.com';
  
  static const String apiVersion = 'v1';
}
```

#### Step 3: Add Providers

Update `lib/core/config/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import 'api_config.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ApiClient(
    baseUrl: ApiConfig.baseUrl,
    prefs: prefs,
  );
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final isarService = ref.watch(isarServiceProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  
  return SyncService(
    apiClient: apiClient,
    isarService: isarService,
    prefs: prefs,
  );
});
```

#### Step 4: Implement Authentication

Create `lib/features/auth/services/cloud_auth_service.dart`:

```dart
import '../../../core/services/api_client.dart';

class CloudAuthService {
  final ApiClient apiClient;
  
  CloudAuthService(this.apiClient);
  
  Future<AuthResult> login(String email, String password) async {
    try {
      final response = await apiClient.post('/api/auth/login', {
        'email': email,
        'password': password,
      });
      
      if (response['success'] == true) {
        final token = response['token'];
        // Save token
        await apiClient.prefs.setString('auth_token', token);
        
        return AuthResult(success: true, user: response['user']);
      }
      
      return AuthResult(success: false, error: 'Login failed');
    } catch (e) {
      return AuthResult(success: false, error: e.toString());
    }
  }
  
  Future<void> logout() async {
    try {
      await apiClient.post('/api/auth/logout', {});
      await apiClient.prefs.remove('auth_token');
    } catch (e) {
      print('Logout error: $e');
    }
  }
}

class AuthResult {
  final bool success;
  final dynamic user;
  final String? error;
  
  AuthResult({required this.success, this.user, this.error});
}
```

#### Step 5: Implement Change Tracking

Create `lib/core/database/change_tracker.dart`:

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ChangeTracker {
  final SharedPreferences prefs;
  static const _key = 'pending_changes';
  
  ChangeTracker(this.prefs);
  
  Future<void> trackChange({
    required String table,
    required String operation,
    required Map<String, dynamic> data,
    String? localId,
  }) async {
    final changes = await getPendingChanges();
    
    changes.add({
      'table': table,
      'operation': operation,
      'data': data,
      if (localId != null) 'local_id': localId,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    await _saveChanges(changes);
  }
  
  Future<List<Map<String, dynamic>>> getPendingChanges() async {
    final json = prefs.getString(_key);
    if (json == null) return [];
    
    final List<dynamic> decoded = jsonDecode(json);
    return decoded.cast<Map<String, dynamic>>();
  }
  
  Future<void> clearPendingChanges() async {
    await prefs.remove(_key);
  }
  
  Future<void> _saveChanges(List<Map<String, dynamic>> changes) async {
    await prefs.setString(_key, jsonEncode(changes));
  }
}
```

#### Step 6: Add Background Sync

Create `lib/core/services/background_sync_service.dart`:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'sync_service.dart';
import '../database/change_tracker.dart';

class BackgroundSyncService {
  final SyncService syncService;
  final ChangeTracker changeTracker;
  
  Timer? _syncTimer;
  bool _isSyncing = false;
  
  BackgroundSyncService({
    required this.syncService,
    required this.changeTracker,
  });
  
  /// Start periodic sync (every 5 minutes)
  void startPeriodicSync({Duration interval = const Duration(minutes: 5)}) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (_) => syncNow());
  }
  
  /// Stop periodic sync
  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }
  
  /// Trigger sync immediately
  Future<void> syncNow({int? companyId}) async {
    if (_isSyncing) {
      debugPrint('Sync already in progress');
      return;
    }
    
    if (companyId == null) {
      debugPrint('No company ID provided for sync');
      return;
    }
    
    _isSyncing = true;
    
    try {
      // Push local changes first
      final pendingChanges = await changeTracker.getPendingChanges();
      
      if (pendingChanges.isNotEmpty) {
        final pushResult = await syncService.pushChanges(
          companyId: companyId,
          changes: pendingChanges,
        );
        
        if (pushResult.success) {
          await changeTracker.clearPendingChanges();
        }
      }
      
      // Then pull server changes
      final pullResult = await syncService.pullChanges(
        companyId: companyId,
      );
      
      if (pullResult.success) {
        debugPrint('Sync completed: ${pullResult.changesApplied} changes applied');
      }
    } catch (e) {
      debugPrint('Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }
  
  void dispose() {
    stopPeriodicSync();
  }
}
```

#### Step 7: Update DAOs to Track Changes

Example for PartyDao:

```dart
Future<void> saveParty(Party party, {int? companyId}) async {
  await isar.writeTxn(() async {
    await isar.partys.put(party);
  });
  
  // Track change for sync
  if (companyId != null) {
    await changeTracker.trackChange(
      table: 'parties',
      operation: party.id == Isar.autoIncrement ? 'INSERT' : 'UPDATE',
      data: {
        'id': party.id,
        'company_id': companyId,
        'name': party.name,
        'party_type': party.partyType.name,
        // ... other fields
      },
      localId: party.id == Isar.autoIncrement ? 'temp_${DateTime.now().millisecondsSinceEpoch}' : null,
    );
  }
}
```

---

## 🧪 Testing the Integration

### Test 1: User Registration & Login

```dart
// In your login screen
final cloudAuth = CloudAuthService(apiClient);

final result = await cloudAuth.login(
  'test@example.com',
  'password123',
);

if (result.success) {
  // Navigate to home
}
```

### Test 2: Sync Status

```dart
final syncService = ref.read(syncServiceProvider);
final status = await syncService.getSyncStatus(currentCompanyId);

if (status != null) {
  print('Pending changes: ${status.pendingChanges}');
  print('Last sync: ${status.lastSyncAt}');
}
```

### Test 3: Full Sync

```dart
final syncService = ref.read(syncServiceProvider);
final result = await syncService.fullSync(currentCompanyId);

if (result.success) {
  showSnackBar('Sync completed: ${result.changesApplied} changes');
}
```

---

## 📱 Add Sync UI

### Sync Button Widget

Create `lib/presentation/widgets/sync_button.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SyncButton extends ConsumerWidget {
  final int companyId;
  
  const SyncButton({super.key, required this.companyId});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.sync),
      onPressed: () async {
        final syncService = ref.read(syncServiceProvider);
        
        // Show loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Syncing...')),
        );
        
        final result = await syncService.fullSync(companyId);
        
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synced ${result.changesApplied} changes'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync failed: ${result.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }
}
```

---

## 🚀 Quick Start Commands

### Backend Setup
```bash
cd laravel_sync
composer install
cp .env.example .env
php artisan key:generate
# Configure database in .env
php artisan migrate
php artisan serve
```

### Flutter Setup
```bash
flutter pub get
flutter run
```

### Test API
```bash
# Register
curl -X POST http://localhost:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","full_name":"Test","password":"password123"}'

# Login
curl -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"password123"}'
```

---

## 📚 Documentation Reference

- **[QUICK_START.md](laravel_sync/QUICK_START.md)** - Laravel setup
- **[ARCHITECTURE.md](laravel_sync/ARCHITECTURE.md)** - System design
- **[IMPLEMENTATION_SUMMARY.md](laravel_sync/IMPLEMENTATION_SUMMARY.md)** - What was built

---

## ✅ Recommended Order

1. ✅ **Set up Laravel backend** (30 min)
2. ✅ **Test API with Postman/curl** (15 min)
3. ✅ **Add Flutter dependencies** (5 min)
4. ✅ **Configure API client** (15 min)
5. ✅ **Implement authentication** (1 hour)
6. ✅ **Add change tracking** (1 hour)
7. ✅ **Test sync flow** (30 min)
8. ✅ **Add background sync** (30 min)
9. ✅ **Polish UI** (1 hour)

**Total Time: 5-6 hours**

---

## 🎯 Your Choice

**Which path do you want to take?**

1. **Option A**: Set up Laravel backend now
2. **Option B**: Complete Flutter integration
3. **Option C**: Test existing Flutter app first
4. **Something else?**

Let me know and I'll guide you through! 🚀
