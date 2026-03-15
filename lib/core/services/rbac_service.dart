import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/company_model.dart';
import '../../data/models/sync_change_model.dart';
import '../../data/models/user_model.dart';

enum UserRole { admin, user }

class RbacService {
  final Isar isar;
  final SharedPreferences prefs;

  RbacService({
    required this.isar,
    required this.prefs,
  });

  static const List<String> menuKeys = [
    'dashboard',
    'sales',
    'purchases',
    'payments',
    'expenses',
    'accounts_parties',
    'cash_bank',
    'masters_products',
    'masters_parties',
    'reports',
    'settings',
    'switch_company',
  ];

  static const Map<String, String> menuLabels = {
    'dashboard': 'Dashboard',
    'sales': 'Sales',
    'purchases': 'Purchase',
    'payments': 'Payments',
    'expenses': 'Expenses',
    'accounts_parties': 'Accounts/Parties',
    'cash_bank': 'Cash and Bank',
    'masters_products': 'Masters - Products',
    'masters_parties': 'Masters - Parties',
    'reports': 'Reports',
    'settings': 'Settings',
    'switch_company': 'Switch Company',
  };

  static const String _keyIsAdminAnywhere = 'rbac_is_admin_anywhere';
  static const String _keyIsAdminCurrentCompany =
      'rbac_is_admin_current_company';
  static const String _keyCurrentRole = 'rbac_current_role';
  static const String _keyBootstrapAdminUserId = 'rbac_bootstrap_admin_user_id';
  static const String _keyAnyAdminExists = 'rbac_any_admin_exists';

  String _menuAccessKey(int userId, int companyId) {
    return 'menu_access_${userId}_$companyId';
  }

  Future<void> ensureBootstrapAssignmentsForUser(int userId) async {
    final mappings = await isar.companyUsers
        .filter()
        .userIdEqualTo(userId)
        .isActiveEqualTo(true)
        .findAll();

    if (mappings.isNotEmpty) {
      return;
    }

    final ownedCompanies = await isar.companys
        .filter()
        .subscriberIdEqualTo(userId)
        .isActiveEqualTo(true)
        .findAll();

    if (ownedCompanies.isEmpty) {
      final allCompanies =
          await isar.companys.filter().isActiveEqualTo(true).findAll();
      for (final company in allCompanies) {
        await assignUserToCompany(
          userId: userId,
          companyId: company.id,
          role: UserRole.admin,
        );
      }
      return;
    }

    for (final company in ownedCompanies) {
      await assignUserToCompany(
        userId: userId,
        companyId: company.id,
        role: UserRole.admin,
      );
    }
  }

  Future<List<User>> getActiveUsers() async {
    return isar.users.filter().isActiveEqualTo(true).sortByFullName().findAll();
  }

  Future<List<User>> getManagedUsersForAdmin(int adminUserId) async {
    final companies = await getAccessibleCompaniesForUser(adminUserId);
    final companyIds = companies.map((company) => company.id).toSet();
    if (companyIds.isEmpty) {
      return [];
    }

    final mappings = await isar.companyUsers.filter().isActiveEqualTo(true).findAll();
    final userIds = mappings
        .where((mapping) => companyIds.contains(mapping.companyId))
        .map((mapping) => mapping.userId)
        .where((userId) => userId != adminUserId)
        .toSet()
        .toList();

    if (userIds.isEmpty) {
      return [];
    }

    final users = await isar.users.getAll(userIds);
    final managedUsers = users.whereType<User>().toList();
    managedUsers.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return managedUsers;
  }

  Future<void> updateUserProfile({
    required int userId,
    required String fullName,
    required String email,
    required int companyId,
  }) async {
    final normalizedName = fullName.trim();
    final normalizedEmail = email.trim();
    if (normalizedName.isEmpty) {
      throw Exception('Full name is required');
    }
    if (normalizedEmail.isEmpty) {
      throw Exception('Email is required');
    }

    final users = await isar.users.where().findAll();
    final emailTaken = users.any(
      (user) =>
          user.id != userId &&
          user.email.toLowerCase() == normalizedEmail.toLowerCase(),
    );
    if (emailTaken) {
      throw Exception('Email already exists');
    }

    await isar.writeTxn(() async {
      final user = await isar.users.get(userId);
      if (user == null) {
        throw Exception('User not found');
      }

      user.fullName = normalizedName;
      user.email = normalizedEmail;
      await isar.users.put(user);
      await _recordUserUpdateSyncChange(companyId: companyId, user: user);
    });
  }

  Future<void> setUserActiveStatus({
    required int userId,
    required bool isActive,
    required int companyId,
  }) async {
    await isar.writeTxn(() async {
      final user = await isar.users.get(userId);
      if (user == null) {
        throw Exception('User not found');
      }

      user.isActive = isActive;
      await isar.users.put(user);
      await _recordUserUpdateSyncChange(companyId: companyId, user: user);
    });
  }

  Future<void> _recordUserUpdateSyncChange({
    required int companyId,
    required User user,
  }) async {
    await isar.syncChanges.put(
      SyncChange()
        ..companyId = companyId
        ..table = 'users'
        ..operation = ChangeOperation.update
        ..recordId = user.id
        ..data = jsonEncode({
          'id': user.id,
          'email': user.email,
          'full_name': user.fullName,
          'is_active': user.isActive,
        })
        ..createdAt = DateTime.now()
        ..synced = false,
    );
  }

  Future<List<Company>> getAccessibleCompaniesForUser(int userId) async {
    final mappings = await isar.companyUsers
        .filter()
        .userIdEqualTo(userId)
        .isActiveEqualTo(true)
        .findAll();

    if (mappings.isEmpty) {
      return isar.companys.filter().isActiveEqualTo(true).findAll();
    }

    final companyIds =
        mappings.map((mapping) => mapping.companyId).toSet().toList();
    if (companyIds.isEmpty) {
      return [];
    }

    final companies = await isar.companys.getAll(companyIds);
    return companies
        .whereType<Company>()
        .where((company) => company.isActive)
        .toList();
  }

  Future<bool> isUserAdminAnywhere(int userId) async {
    final bootstrapAdminUserId = prefs.getInt(_keyBootstrapAdminUserId);
    if (bootstrapAdminUserId == userId) {
      return true;
    }

    final adminMapping = await isar.companyUsers
        .filter()
        .userIdEqualTo(userId)
        .isActiveEqualTo(true)
        .roleEqualTo(UserRole.admin.name, caseSensitive: false)
        .findFirst();
    if (adminMapping != null) {
      return true;
    }

    final ownedCompany = await isar.companys
        .filter()
        .subscriberIdEqualTo(userId)
        .isActiveEqualTo(true)
        .findFirst();
    return ownedCompany != null;
  }

  Future<void> markBootstrapAdminUser(int userId) async {
    await prefs.setInt(_keyBootstrapAdminUserId, userId);
    await prefs.setBool(_keyIsAdminAnywhere, true);
    await prefs.setBool(_keyAnyAdminExists, true);
  }

  bool get hasAnyAdminRegistered => prefs.getBool(_keyAnyAdminExists) ?? false;

  Future<void> markAnyAdminRegistered() async {
    await prefs.setBool(_keyAnyAdminExists, true);
  }

  Future<void> clearBootstrapAdminUserIfOwnedCompanyExists(int userId) async {
    final ownedCompany = await isar.companys
        .filter()
        .subscriberIdEqualTo(userId)
        .isActiveEqualTo(true)
        .findFirst();
    if (ownedCompany == null) {
      return;
    }

    final bootstrapAdminUserId = prefs.getInt(_keyBootstrapAdminUserId);
    if (bootstrapAdminUserId == userId) {
      await prefs.remove(_keyBootstrapAdminUserId);
    }
  }

  Future<void> cacheGlobalAdminState(int userId) async {
    await clearBootstrapAdminUserIfOwnedCompanyExists(userId);
    final isAdmin = await isUserAdminAnywhere(userId);
    await prefs.setBool(_keyIsAdminAnywhere, isAdmin);
    if (isAdmin) {
      await prefs.setBool(_keyAnyAdminExists, true);
    }
  }

  Future<void> cacheCurrentCompanyRole({
    required int userId,
    required int companyId,
  }) async {
    final role =
        await getUserRoleForCompany(userId: userId, companyId: companyId);
    await prefs.setString(_keyCurrentRole, role.name);
    await prefs.setBool(_keyIsAdminCurrentCompany, role == UserRole.admin);
  }

  Future<void> clearCachedCurrentCompanyRole() async {
    await prefs.remove(_keyCurrentRole);
    await prefs.remove(_keyIsAdminCurrentCompany);
  }

  Future<void> clearAllCachedRoleState() async {
    await clearCachedCurrentCompanyRole();
    await prefs.remove(_keyIsAdminAnywhere);
  }

  Future<CompanyUser?> getCompanyUserMapping({
    required int userId,
    required int companyId,
  }) async {
    return isar.companyUsers
        .filter()
        .userIdEqualTo(userId)
        .companyIdEqualTo(companyId)
        .isActiveEqualTo(true)
        .findFirst();
  }

  Future<UserRole> getUserRoleForCompany({
    required int userId,
    required int companyId,
  }) async {
    final mapping = await getCompanyUserMapping(
      userId: userId,
      companyId: companyId,
    );

    if (mapping == null) {
      return UserRole.user;
    }

    return mapping.role.toLowerCase() == UserRole.admin.name
        ? UserRole.admin
        : UserRole.user;
  }

  Future<bool> isAdminForCompany({
    required int userId,
    required int companyId,
  }) async {
    final role =
        await getUserRoleForCompany(userId: userId, companyId: companyId);
    return role == UserRole.admin;
  }

  Future<void> assignUserToCompany({
    required int userId,
    required int companyId,
    required UserRole role,
  }) async {
    await isar.writeTxn(() async {
      final existing = await isar.companyUsers
          .filter()
          .userIdEqualTo(userId)
          .companyIdEqualTo(companyId)
          .findFirst();

      if (existing != null) {
        existing.role = role.name;
        existing.isActive = true;
        await isar.companyUsers.put(existing);

        await isar.syncChanges.put(
          SyncChange()
            ..companyId = companyId
            ..table = 'company_users'
            ..operation = ChangeOperation.update
            ..recordId = existing.id
            ..data = jsonEncode({
              'id': existing.id,
              'company_id': existing.companyId,
              'user_id': existing.userId,
              'role': existing.role,
              'user_group_id': existing.userGroupId,
              'is_active': existing.isActive,
            })
            ..createdAt = DateTime.now()
            ..synced = false,
        );
        return;
      }

      final mapping = CompanyUser()
        ..userId = userId
        ..companyId = companyId
        ..role = role.name
        ..isActive = true;
      final mappingId = await isar.companyUsers.put(mapping);

      await isar.syncChanges.put(
        SyncChange()
          ..companyId = companyId
          ..table = 'company_users'
          ..operation = ChangeOperation.create
          ..recordId = mappingId
          ..data = jsonEncode({
            'id': mappingId,
            'company_id': companyId,
            'user_id': userId,
            'role': role.name,
            'user_group_id': mapping.userGroupId,
            'is_active': true,
          })
          ..createdAt = DateTime.now()
          ..synced = false,
      );
    });
  }

  Future<void> removeUserFromCompany({
    required int userId,
    required int companyId,
  }) async {
    await isar.writeTxn(() async {
      final mapping = await isar.companyUsers
          .filter()
          .userIdEqualTo(userId)
          .companyIdEqualTo(companyId)
          .isActiveEqualTo(true)
          .findFirst();
      if (mapping != null) {
        mapping.isActive = false;
        await isar.companyUsers.put(mapping);

        await isar.syncChanges.put(
          SyncChange()
            ..companyId = companyId
            ..table = 'company_users'
            ..operation = ChangeOperation.update
            ..recordId = mapping.id
            ..data = jsonEncode({
              'id': mapping.id,
              'company_id': mapping.companyId,
              'user_id': mapping.userId,
              'role': mapping.role,
              'user_group_id': mapping.userGroupId,
              'is_active': false,
            })
            ..createdAt = DateTime.now()
            ..synced = false,
        );
      }
    });
  }

  Future<Map<String, bool>> getMenuAccess({
    required int userId,
    required int companyId,
  }) async {
    final isAdmin =
        await isAdminForCompany(userId: userId, companyId: companyId);
    if (isAdmin) {
      return {for (final key in menuKeys) key: true};
    }

    final stored = prefs.getStringList(_menuAccessKey(userId, companyId));
    if (stored == null || stored.isEmpty) {
      return {for (final key in menuKeys) key: true};
    }

    final allowed = stored.toSet();
    return {for (final key in menuKeys) key: allowed.contains(key)};
  }

  Future<void> setMenuAccess({
    required int userId,
    required int companyId,
    required Set<String> allowedMenuKeys,
  }) async {
    await prefs.setStringList(
      _menuAccessKey(userId, companyId),
      allowedMenuKeys.where((key) => menuKeys.contains(key)).toList(),
    );
  }

  Future<bool> canAccessMenu({
    required int userId,
    required int companyId,
    required String menuKey,
  }) async {
    if (!menuKeys.contains(menuKey)) {
      return false;
    }

    final access = await getMenuAccess(userId: userId, companyId: companyId);
    return access[menuKey] == true;
  }
}
