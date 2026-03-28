import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/providers.dart';
import '../../core/providers/rbac_providers.dart';
import '../../core/providers/sync_providers.dart';
import '../../features/companies/services/company_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();

    // Safety timeout to prevent infinite loading
    Timer(const Duration(seconds: 10), () {
      if (mounted && !_isNavigating) {
        print('Splash timeout reached, navigating to login');
        _navigateToLogin();
      }
    });
  }

  void _navigateToLogin() {
    if (!_isNavigating && mounted) {
      _isNavigating = true;
      context.go('/login');
    }
  }

  Future<void> _checkAuthAndNavigate() async {
    try {
      // Small delay to show splash
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // Cache all providers at the start
      final authService = ref.read(authServiceProvider);
      final apiClient = ref.read(apiClientProvider);
      final rbacService = ref.read(rbacServiceProvider);
      final isarService = ref.read(isarServiceProvider);
      final syncService = ref.read(syncServiceProvider);

      // Validate and restore current session from the stored auth token.
      if (authService.isLoggedIn) {
        final user = await authService.restoreAuthenticatedUser(apiClient);

        if (user != null) {
          // Restore user state
          ref.read(currentUserProvider.notifier).state = user;
          await rbacService.ensureBootstrapAssignmentsForUser(user.id);
          await rbacService.cacheGlobalAdminState(user.id);

          // Check if company has been selected
          if (authService.hasSelectedCompany) {
            // Load and set the selected company
            final companyId = authService.selectedCompanyId;
            if (companyId != null) {
              try {
                final isar = isarService.isar;
                final service = CompanyService(isar);
                final company = await service.getCompanyById(companyId);

                if (company != null && company.isActive) {
                  // Restore company state
                  ref.read(currentCompanyProvider.notifier).state = company;
                  ref.read(selectedCompanyIdProvider.notifier).state =
                      company.id;
                  await rbacService.cacheCurrentCompanyRole(
                    userId: user.id,
                    companyId: company.id,
                  );

                  // Try automatic server login + sync in background.
                  Future(() async {
                    await syncService.autoLoginAndSyncAllLocalCompanies();
                  });

                  // Navigate to dashboard with safety check
                  if (mounted && !_isNavigating) {
                    _isNavigating = true;
                    context.go('/dashboard');
                  }
                } else {
                  // Company no longer exists or is inactive, go to company selection
                  await authService.clearSelectedCompany();
                  await rbacService.clearCachedCurrentCompanyRole();
                  if (mounted && !_isNavigating) {
                    _isNavigating = true;
                    context.go('/company');
                  }
                }
              } catch (e) {
                print('Error loading company: $e');
                // Error loading company, go to company selection
                await authService.clearSelectedCompany();
                await rbacService.clearCachedCurrentCompanyRole();
                if (mounted && !_isNavigating) {
                  _isNavigating = true;
                  context.go('/company');
                }
              }
            } else {
              // Invalid company ID, go to company selection
              await rbacService.clearCachedCurrentCompanyRole();
              if (mounted && !_isNavigating) {
                _isNavigating = true;
                context.go('/company');
              }
            }
          } else {
            await rbacService.clearCachedCurrentCompanyRole();
            // Try automatic server login + sync in background.
            Future(() async {
              await syncService.autoLoginAndSyncAllLocalCompanies();
            });

            // No company selected, go to company selection
            if (mounted && !_isNavigating) {
              _isNavigating = true;
              context.go('/company');
            }
          }
        } else {
          // Token is missing or invalid.
          await authService.clearAuthSession();
          await rbacService.clearAllCachedRoleState();
          if (mounted && !_isNavigating) {
            _isNavigating = true;
            context.go('/login');
          }
        }
      } else {
        // Not logged in, go to login
        await rbacService.clearAllCachedRoleState();
        if (mounted && !_isNavigating) {
          _isNavigating = true;
          context.go('/login');
        }
      }
    } catch (e, stackTrace) {
      print('Error in _checkAuthAndNavigate: $e');
      print('Stack trace: $stackTrace');

      // Fallback to login on any error
      if (!mounted || _isNavigating) return;
      final router = GoRouter.of(context);
      try {
        final authService = ref.read(authServiceProvider);
        await authService.clearAuthSession();
        await ref.read(rbacServiceProvider).clearAllCachedRoleState();
      } catch (_) {
        // Ignore logout errors
      }
      _isNavigating = true;
      router.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icons/splash_logo.png',
                width: 280,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.account_balance_wallet,
                  size: 96,
                  color: Colors.blueAccent,
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(
                color: Colors.blueAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
