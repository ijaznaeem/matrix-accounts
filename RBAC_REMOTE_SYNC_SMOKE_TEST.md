# RBAC Remote Sync Smoke Test (Users + Company Assignments)

This runbook verifies that user-management changes made in Flutter are saved locally **and** synchronized to Laravel remote DB.

## 1) Preconditions

- Laravel API is running and reachable by the app (`/api/health` returns `ok`).
- You are logged in as an admin user in Flutter.
- At least one company exists and is selected.
- `php` CLI is available for backend checks.

## 2) Test Flow in Flutter

Go to **Settings → User Access Management** and perform these operations in order:

1. Select a company.
2. Use **Add User (User Role)** to create a test user.
3. Assign that user to selected company and tap **Save Access**.
4. In **Managed Users**:
   - Edit the user name/email.
   - Deactivate user, then activate user again.
   - (Optional) Change role `user → admin` and save.

Each action should complete locally and trigger sync attempt.

## 3) Verify Remote DB Changes (Laravel)

Run these commands from repo root.

### 3.1 Confirm sync change log entries for RBAC tables

```powershell
php artisan tinker --execute="\App\Models\SyncChange::whereIn('table_name',['users','company_users'])->latest()->take(20)->get(['id','company_id','table_name','record_id','operation','version','created_at'])->toArray();"
```

Expected:
- Recent rows exist for `users` and/or `company_users`.
- `operation` shows `INSERT`/`UPDATE` as you performed actions.

### 3.2 Confirm user row updated remotely

```powershell
php artisan tinker --execute="\App\Models\User::where('email','<test-email@example.com>')->first(['id','email','full_name','is_active']);"
```

Expected:
- `full_name` and `is_active` match your latest Flutter action.

### 3.3 Confirm company-user mapping updated remotely

```powershell
php artisan tinker --execute="\App\Models\CompanyUser::where('company_id',<COMPANY_ID>)->where('user_id',<USER_ID>)->first(['id','company_id','user_id','role','is_active']);"
```

Expected:
- Role and active status match latest assignment in Flutter.

## 4) API-Level Sync Status Check (optional)

If needed, verify pending sync count from API:

```powershell
curl -X GET "http://127.0.0.1:8000/api/sync/status?company_id=<COMPANY_ID>&device_id=<DEVICE_ID>" -H "Authorization: Bearer <TOKEN>" -H "Accept: application/json"
```

Expected:
- `success: true`
- `pending_changes` decreases to `0` after successful sync cycle.

## 5) Pass Criteria

- Flutter changes are visible immediately in app.
- Remote DB reflects same user/profile/status/role values.
- `sync_changes` contains corresponding RBAC table entries.
- No sync failure snackbar for tested operations.

## 6) If Sync Fails

1. Check app snackbar for full sync error.
2. Confirm server token is valid (logout/login again once).
3. Verify API health and DB connectivity on Laravel.
4. Re-run Section 3 queries to confirm whether writes reached server.
