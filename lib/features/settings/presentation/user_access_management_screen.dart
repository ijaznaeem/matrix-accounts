import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/providers/rbac_providers.dart';
import '../../../core/providers/sync_providers.dart';
import '../../../core/services/rbac_service.dart';
import '../../../data/models/company_model.dart';
import '../../../data/models/user_model.dart';

class UserAccessManagementScreen extends ConsumerStatefulWidget {
  const UserAccessManagementScreen({super.key});

  @override
  ConsumerState<UserAccessManagementScreen> createState() =>
      _UserAccessManagementScreenState();
}

class _UserAccessManagementScreenState
    extends ConsumerState<UserAccessManagementScreen> {
  int? _selectedUserId;
  int? _selectedCompanyId;
  Company? _selectedCompany;
  bool _creatingUser = false;
  bool _updatingUser = false;
  int _managedUsersVersion = 0;

  Future<void> _syncCompanyToRemote(int companyId) async {
    final syncResult = await ref.read(syncServiceProvider).fullSync(companyId);
    if (!mounted || syncResult.success) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved locally, but sync to server failed: ${syncResult.error ?? 'Unknown error'}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  User? _findUserById(List<User> users, int? userId) {
    if (userId == null) return null;
    for (final user in users) {
      if (user.id == userId) return user;
    }
    return null;
  }

  Company? _findCompanyById(List<Company> companies, int? companyId) {
    if (companyId == null) return null;
    for (final company in companies) {
      if (company.id == companyId) return company;
    }
    return null;
  }

  Future<void> _showAddUserDialog() async {
    final company = _selectedCompany;
    if (company == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a company first to create a user.'),
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    var passwordVisible = false;
    var confirmPasswordVisible = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add User'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        textInputAction: TextInputAction.next,
                        decoration:
                            const InputDecoration(labelText: 'Full Name'),
                        validator: (value) {
                          final name = value?.trim() ?? '';
                          if (name.isEmpty) return 'Full name is required';
                          if (name.length < 3) {
                            return 'Full name must be at least 3 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return 'Email is required';
                          if (!email.contains('@') ||
                              email.startsWith('@') ||
                              email.endsWith('@') ||
                              !email.split('@').last.contains('.')) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordController,
                        obscureText: !passwordVisible,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                passwordVisible = !passwordVisible;
                              });
                            },
                            icon: Icon(
                              passwordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password is required';
                          }
                          if (value.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmPasswordController,
                        obscureText: !confirmPasswordVisible,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                confirmPasswordVisible =
                                    !confirmPasswordVisible;
                              });
                            },
                            icon: Icon(
                              confirmPasswordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm password';
                          }
                          if (value != passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      _creatingUser ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _creatingUser
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }

                          setState(() => _creatingUser = true);

                          try {
                            final apiClient = ref.read(apiClientProvider);
                            final rbac = ref.read(rbacServiceProvider);
                            final isar = ref.read(isarServiceProvider).isar;

                            final response = await apiClient.post(
                              '/api/auth/register',
                              {
                                'name': nameController.text.trim(),
                                'email': emailController.text.trim(),
                                'role': 'user',
                                'password': passwordController.text,
                                'password_confirmation':
                                    confirmPasswordController.text,
                              },
                            );

                            if (response['success'] != true) {
                              throw Exception(
                                response['message']?.toString() ??
                                    'User registration failed',
                              );
                            }

                            final userData =
                                response['user'] as Map<String, dynamic>?;
                            final userId = (userData?['id'] as int?) ?? 0;
                            if (userId <= 0) {
                              throw Exception(
                                  'Invalid user returned from server');
                            }

                            final email = userData?['email']?.toString() ??
                                emailController.text.trim();
                            final fullName =
                                userData?['full_name']?.toString() ??
                                    userData?['name']?.toString() ??
                                    nameController.text.trim();

                            final createdUser = User()
                              ..id = userId
                              ..email = email
                              ..fullName = fullName
                              ..passwordHash = ''
                              ..isActive = true;

                            await isar.writeTxn(() async {
                              await isar.users.put(createdUser);
                            });

                            await rbac.assignUserToCompany(
                              userId: userId,
                              companyId: company.id,
                              role: UserRole.user,
                            );

                            await rbac.setMenuAccess(
                              userId: userId,
                              companyId: company.id,
                              allowedMenuKeys: RbacService.menuKeys.toSet(),
                            );

                            await _syncCompanyToRemote(company.id);

                            if (!mounted) return;
                            setState(() => _managedUsersVersion++);

                            if (!context.mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'User created with user role for ${company.name}',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to create user: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _creatingUser = false);
                            }
                          }
                        },
                  child: _creatingUser
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create User'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
  }

  Future<void> _toggleUserStatus(User user) async {
    if (_updatingUser) return;
    final messenger = ScaffoldMessenger.of(context);

    if (user.isActive) {
      final shouldDeactivate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Deactivate User'),
            content: Text(
              'Are you sure you want to deactivate ${user.fullName}? They will lose access until activated again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Deactivate'),
              ),
            ],
          );
        },
      );

      if (shouldDeactivate != true) {
        return;
      }
    }

    setState(() => _updatingUser = true);
    try {
      final companyId =
          _selectedCompanyId ?? ref.read(currentCompanyProvider)?.id;
      if (companyId == null) {
        throw Exception('No company selected for sync context');
      }

      await ref.read(rbacServiceProvider).setUserActiveStatus(
            userId: user.id,
            isActive: !user.isActive,
            companyId: companyId,
          );

      if (!mounted) return;

      setState(() => _managedUsersVersion++);
      await _syncCompanyToRemote(companyId);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            user.isActive
                ? 'User deactivated successfully'
                : 'User activated successfully',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update user status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingUser = false);
      }
    }
  }

  Future<void> _showEditUserDialog(User user) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: user.fullName);
    final emailController = TextEditingController(text: user.email);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit User'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Full Name'),
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.isEmpty) return 'Full name is required';
                      if (name.length < 3) {
                        return 'Full name must be at least 3 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) return 'Email is required';
                      if (!email.contains('@') ||
                          email.startsWith('@') ||
                          email.endsWith('@') ||
                          !email.split('@').last.contains('.')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  _updatingUser ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _updatingUser
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      final messenger = ScaffoldMessenger.of(context);

                      setState(() => _updatingUser = true);
                      try {
                        final companyId = _selectedCompanyId ??
                            ref.read(currentCompanyProvider)?.id;
                        if (companyId == null) {
                          throw Exception(
                              'No company selected for sync context');
                        }

                        await ref.read(rbacServiceProvider).updateUserProfile(
                              userId: user.id,
                              fullName: nameController.text,
                              email: emailController.text,
                              companyId: companyId,
                            );

                        if (!mounted) return;
                        navigator.pop();
                        setState(() => _managedUsersVersion++);
                        await _syncCompanyToRemote(companyId);
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('User updated successfully'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Failed to update user: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        if (mounted) {
                          setState(() => _updatingUser = false);
                        }
                      }
                    },
              child: _updatingUser
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
  }

  Future<void> _showChangePasswordDialog({
    required User targetUser,
    required bool isSelf,
  }) async {
    final formKey = GlobalKey<FormState>();
    final currentPasswordController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    var currentPasswordVisible = false;
    var passwordVisible = false;
    var confirmPasswordVisible = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(isSelf
                  ? 'Change My Password'
                  : 'Change Password - ${targetUser.fullName}'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelf) ...[
                        TextFormField(
                          controller: currentPasswordController,
                          obscureText: !currentPasswordVisible,
                          decoration: InputDecoration(
                            labelText: 'Current Password',
                            suffixIcon: IconButton(
                              onPressed: () {
                                setDialogState(() {
                                  currentPasswordVisible =
                                      !currentPasswordVisible;
                                });
                              },
                              icon: Icon(
                                currentPasswordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (isSelf && (value == null || value.isEmpty)) {
                              return 'Current password is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: passwordController,
                        obscureText: !passwordVisible,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                passwordVisible = !passwordVisible;
                              });
                            },
                            icon: Icon(
                              passwordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'New password is required';
                          }
                          if (value.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmPasswordController,
                        obscureText: !confirmPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                confirmPasswordVisible =
                                    !confirmPasswordVisible;
                              });
                            },
                            icon: Icon(
                              confirmPasswordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm password';
                          }
                          if (value != passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      _updatingUser ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _updatingUser
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }

                          setState(() => _updatingUser = true);
                          try {
                            final apiClient = ref.read(apiClientProvider);
                            final payload = <String, dynamic>{
                              'password': passwordController.text,
                              'password_confirmation':
                                  confirmPasswordController.text,
                            };

                            if (isSelf) {
                              payload['current_password'] =
                                  currentPasswordController.text;
                            } else {
                              payload['target_user_id'] = targetUser.id;
                            }

                            final response = await apiClient.post(
                              '/api/auth/change-password',
                              payload,
                            );

                            if (response['success'] != true) {
                              throw Exception(
                                response['message']?.toString() ??
                                    'Failed to change password',
                              );
                            }

                            if (!mounted) return;
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  response['message']?.toString() ??
                                      (isSelf
                                          ? 'Password updated successfully'
                                          : 'User password changed successfully'),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to change password: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _updatingUser = false);
                            }
                          }
                        },
                  child: _updatingUser
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isSelf ? 'Update' : 'Reset Password'),
                ),
              ],
            );
          },
        );
      },
    );

    currentPasswordController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final currentCompany = ref.watch(currentCompanyProvider);

    if (currentUser == null || currentCompany == null) {
      return const Scaffold(
        body: Center(child: Text('Please select a company first')),
      );
    }

    final isAdminAsync = ref.watch(currentUserIsAdminProvider);

    return isAdminAsync.when(
      data: (isAdmin) {
        if (!isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('User Access Management')),
            body: const Center(
              child: Text('Only admin users can manage user access.'),
            ),
          );
        }

        return FutureBuilder<List<dynamic>>(
          future: Future.wait([
            ref.read(rbacServiceProvider).getActiveUsers(),
            ref
                .read(rbacServiceProvider)
                .getAccessibleCompaniesForUser(currentUser.id),
            ref
                .read(rbacServiceProvider)
                .getManagedUsersForAdmin(currentUser.id),
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text('User Access Management')),
                body: Center(child: Text('Error: ${snapshot.error}')),
              );
            }

            final users = (snapshot.data?[0] as List<User>? ?? [])
                .where((user) => user.id != currentUser.id)
                .toList();
            final companies = snapshot.data?[1] as List<Company>? ?? [];
            final managedUsers = snapshot.data?[2] as List<User>? ?? [];
            final selectedUser = _findUserById(users, _selectedUserId);
            final selectedCompanyId = _selectedCompanyId ?? currentCompany.id;
            final selectedCompany =
                _findCompanyById(companies, selectedCompanyId);
            _selectedCompany = selectedCompany;

            return Scaffold(
              appBar: AppBar(title: const Text('User Management')),
              body: ListView(
                key: ValueKey('managed_users_$_managedUsersVersion'),
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Manage users and company access',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              FilledButton.icon(
                                onPressed:
                                    _creatingUser ? null : _showAddUserDialog,
                                icon: _creatingUser
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.person_add_alt_1),
                                label: const Text('Add User'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<Company>(
                            initialValue: selectedCompany,
                            decoration: const InputDecoration(
                              labelText: 'Company Context',
                              border: OutlineInputBorder(),
                            ),
                            items: companies
                                .map((company) => DropdownMenuItem<Company>(
                                      value: company,
                                      child: Text(company.name),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedCompanyId = value?.id;
                                _selectedCompany = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<User>(
                            initialValue: selectedUser,
                            decoration: const InputDecoration(
                              labelText: 'User for Access Setup',
                              border: OutlineInputBorder(),
                            ),
                            items: users
                                .map(
                                  (user) => DropdownMenuItem<User>(
                                    value: user,
                                    child: Text(user.fullName),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedUserId = value?.id;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _showChangePasswordDialog(
                                  targetUser: currentUser,
                                  isSelf: true,
                                ),
                                icon: const Icon(Icons.password_outlined),
                                label: const Text('Change My Password'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: selectedUser == null
                                    ? null
                                    : () async {
                                        final changed =
                                            await Navigator.push<bool>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                _UserAccessEditorScreen(
                                              user: selectedUser,
                                              companies: companies,
                                              initialCompanyId:
                                                  selectedCompany!.id,
                                            ),
                                          ),
                                        );

                                        if (!mounted || changed != true) {
                                          return;
                                        }

                                        setState(() => _managedUsersVersion++);
                                      },
                                icon: const Icon(Icons.lock_open_outlined),
                                label: const Text('Manage Access'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final changed = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => _ManageUsersScreen(
                                        managedUsers: managedUsers,
                                        companies: companies,
                                        selectedCompany: selectedCompany!,
                                        currentUser: currentUser,
                                        updatingUser: _updatingUser,
                                        onEditUser: _showEditUserDialog,
                                        onToggleUser: _toggleUserStatus,
                                        onChangePassword:
                                            _showChangePasswordDialog,
                                      ),
                                    ),
                                  );

                                  if (!mounted || changed != true) return;
                                  setState(() => _managedUsersVersion++);
                                },
                                icon: const Icon(Icons.group_outlined),
                                label: const Text('Manage Users'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        managedUsers.isEmpty
                            ? 'No users available under your companies.'
                            : '${managedUsers.length} users available. Tap "Manage Users" to view and edit users.',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('User Access Management')),
        body: Center(child: Text('Error: $error')),
      ),
    );
  }
}

class _ManageUsersScreen extends StatelessWidget {
  const _ManageUsersScreen({
    required this.managedUsers,
    required this.companies,
    required this.selectedCompany,
    required this.currentUser,
    required this.updatingUser,
    required this.onEditUser,
    required this.onToggleUser,
    required this.onChangePassword,
  });

  final List<User> managedUsers;
  final List<Company> companies;
  final Company selectedCompany;
  final User currentUser;
  final bool updatingUser;
  final Future<void> Function(User user) onEditUser;
  final Future<void> Function(User user) onToggleUser;
  final Future<void> Function({
    required User targetUser,
    required bool isSelf,
  }) onChangePassword;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Users')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: const Text('Admin Account'),
              subtitle: Text(currentUser.email),
              trailing: OutlinedButton.icon(
                onPressed: () => onChangePassword(
                  targetUser: currentUser,
                  isSelf: true,
                ),
                icon: const Icon(Icons.password_outlined),
                label: const Text('Change My Password'),
              ),
            ),
          ),
          if (managedUsers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No users available under your companies.'),
              ),
            )
          else
            ...managedUsers.map(
              (user) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.fullName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(user.email),
                              ],
                            ),
                          ),
                          Chip(
                            label: Text(
                              user.isActive ? 'Active' : 'Inactive',
                            ),
                            backgroundColor: user.isActive
                                ? Colors.green.shade50
                                : Colors.grey.shade300,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                updatingUser ? null : () => onEditUser(user),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit'),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                updatingUser ? null : () => onToggleUser(user),
                            icon: Icon(
                              user.isActive
                                  ? Icons.person_off_outlined
                                  : Icons.person_outline,
                            ),
                            label: Text(
                              user.isActive ? 'Deactivate' : 'Activate',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: updatingUser
                                ? null
                                : () => onChangePassword(
                                      targetUser: user,
                                      isSelf: false,
                                    ),
                            icon: const Icon(Icons.password_outlined),
                            label: const Text('Change Password'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final changed = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _UserAccessEditorScreen(
                                    user: user,
                                    companies: companies,
                                    initialCompanyId: selectedCompany.id,
                                  ),
                                ),
                              );

                              if (!context.mounted) return;
                              if (changed == true) {
                                Navigator.pop(context, true);
                              }
                            },
                            icon: const Icon(Icons.lock_open_outlined),
                            label: const Text('Manage Access'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserAccessEditorScreen extends ConsumerStatefulWidget {
  const _UserAccessEditorScreen({
    required this.user,
    required this.companies,
    required this.initialCompanyId,
  });

  final User user;
  final List<Company> companies;
  final int initialCompanyId;

  @override
  ConsumerState<_UserAccessEditorScreen> createState() =>
      _UserAccessEditorScreenState();
}

class _UserAccessEditorScreenState
    extends ConsumerState<_UserAccessEditorScreen> {
  int? _selectedCompanyId;
  UserRole _selectedRole = UserRole.user;
  UserRole _loadedRole = UserRole.user;
  Map<String, bool> _menuAccess = {
    for (final key in RbacService.menuKeys) key: true,
  };
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedCompanyId = widget.initialCompanyId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAccess();
    });
  }

  Company? get _selectedCompany {
    for (final company in widget.companies) {
      if (company.id == _selectedCompanyId) return company;
    }
    return null;
  }

  Future<void> _syncCompanyToRemote(int companyId) async {
    final syncResult = await ref.read(syncServiceProvider).fullSync(companyId);
    if (!mounted || syncResult.success) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved locally, but sync to server failed: ${syncResult.error ?? 'Unknown error'}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _loadAccess() async {
    final company = _selectedCompany;
    if (company == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);
    final rbac = ref.read(rbacServiceProvider);
    final role = await rbac.getUserRoleForCompany(
      userId: widget.user.id,
      companyId: company.id,
    );
    final menuAccess = await rbac.getMenuAccess(
      userId: widget.user.id,
      companyId: company.id,
    );

    if (!mounted) return;
    setState(() {
      _selectedRole = role;
      _loadedRole = role;
      _menuAccess = menuAccess;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final company = _selectedCompany;
    if (company == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a company first')),
      );
      return;
    }

    if (_loadedRole == UserRole.admin && _selectedRole == UserRole.user) {
      final shouldDowngrade = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Change Admin Role'),
            content: Text(
              'Are you sure you want to change ${widget.user.fullName} from Admin to User?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      );

      if (shouldDowngrade != true) {
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final rbac = ref.read(rbacServiceProvider);
      await rbac.assignUserToCompany(
        userId: widget.user.id,
        companyId: company.id,
        role: _selectedRole,
      );

      await rbac.setMenuAccess(
        userId: widget.user.id,
        companyId: company.id,
        allowedMenuKeys: _menuAccess.entries
            .where((entry) => entry.value)
            .map((entry) => entry.key)
            .toSet(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User access updated successfully'),
          backgroundColor: Colors.green,
        ),
      );

      _loadedRole = _selectedRole;
      await _syncCompanyToRemote(company.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save access: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Access - ${widget.user.fullName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField<Company>(
                      initialValue: _selectedCompany,
                      decoration: const InputDecoration(
                        labelText: 'Company',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.companies
                          .map(
                            (company) => DropdownMenuItem<Company>(
                              value: company,
                              child: Text(company.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCompanyId = value?.id;
                        });
                        _loadAccess();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Role',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<UserRole>(
                          segments: const [
                            ButtonSegment<UserRole>(
                              value: UserRole.admin,
                              label: Text('Admin'),
                            ),
                            ButtonSegment<UserRole>(
                              value: UserRole.user,
                              label: Text('User'),
                            ),
                          ],
                          selected: {_selectedRole},
                          onSelectionChanged: (value) {
                            setState(() => _selectedRole = value.first);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Menu Access',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...RbacService.menuKeys.map(
                          (key) => SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _selectedRole == UserRole.admin
                                ? true
                                : (_menuAccess[key] ?? false),
                            onChanged: _selectedRole == UserRole.admin
                                ? null
                                : (value) {
                                    setState(() {
                                      _menuAccess[key] = value;
                                    });
                                  },
                            title: Text(RbacService.menuLabels[key] ?? key),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(_saving ? 'Saving...' : 'Save Access'),
        ),
      ),
    );
  }
}
