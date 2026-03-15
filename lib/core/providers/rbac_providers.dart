import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/providers.dart';
import '../services/rbac_service.dart';
import 'sync_providers.dart';

final rbacServiceProvider = Provider<RbacService>((ref) {
  final isar = ref.watch(isarServiceProvider).isar;
  final prefs = ref.watch(sharedPreferencesProvider);
  return RbacService(isar: isar, prefs: prefs);
});

final currentUserRoleProvider = FutureProvider<UserRole>((ref) async {
  final user = ref.watch(currentUserProvider);
  final company = ref.watch(currentCompanyProvider);

  if (user == null || company == null) {
    return UserRole.user;
  }

  return ref.read(rbacServiceProvider).getUserRoleForCompany(
        userId: user.id,
        companyId: company.id,
      );
});

final currentUserIsAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;

  return ref.read(rbacServiceProvider).isUserAdminAnywhere(user.id);
});

final currentMenuAccessProvider =
    FutureProvider<Map<String, bool>>((ref) async {
  final user = ref.watch(currentUserProvider);
  final company = ref.watch(currentCompanyProvider);

  if (user == null || company == null) {
    return {for (final key in RbacService.menuKeys) key: false};
  }

  return ref.read(rbacServiceProvider).getMenuAccess(
        userId: user.id,
        companyId: company.id,
      );
});
