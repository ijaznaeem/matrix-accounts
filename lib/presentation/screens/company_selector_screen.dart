import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/providers.dart';
import '../../core/providers/sync_providers.dart';
import '../../data/models/company_model.dart';
import '../../features/companies/services/company_service.dart';
import '../../features/inventory/logic/product_master_provider.dart';
import '../../features/parties/logic/party_provider.dart';
import '../../features/sales/logic/sales_providers.dart';

class CompanySelectorScreen extends ConsumerStatefulWidget {
  const CompanySelectorScreen({super.key});

  @override
  ConsumerState<CompanySelectorScreen> createState() =>
      _CompanySelectorScreenState();
}

class _CompanySelectorScreenState extends ConsumerState<CompanySelectorScreen> {
  bool _isSwitchingCompany = false;
  int? _switchingCompanyId;

  @override
  Widget build(BuildContext context) {
    final isar = ref.watch(isarServiceProvider).isar;
    final service = CompanyService(isar);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: const Text('Select Company'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/masters/companies'),
            tooltip: 'Manage Companies',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await context.push('/masters/companies/form');
          if (result == true && mounted) {
            setState(() {}); // Refresh list
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Company'),
      ),
      body: FutureBuilder<List<Company>>(
        future: service.getActiveCompanies(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          final companies = snapshot.data ?? [];

          if (companies.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: companies.length,
            itemBuilder: (_, i) {
              final company = companies[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildCompanyCard(context, ref, company),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCompanyCard(
    BuildContext context,
    WidgetRef ref,
    Company company,
  ) {
    return GestureDetector(
      onTap: _isSwitchingCompany
          ? null
          : () async {
              setState(() {
                _isSwitchingCompany = true;
                _switchingCompanyId = company.id;
              });

              try {
                // Persist company selection
                ref.read(currentCompanyProvider.notifier).state = company;
                ref.read(selectedCompanyIdProvider.notifier).state = company.id;

                // Save to shared preferences
                final authService = ref.read(authServiceProvider);
                await authService.saveSelectedCompany(
                  companyId: company.id,
                  companyName: company.name,
                );

                // Ensure selected company data is up-to-date before opening dashboard.
                final syncService = ref.read(syncServiceProvider);
                final tokenReady = await syncService.ensureServerToken();
                if (tokenReady) {
                  final syncResult = await syncService.fullSync(company.id);
                  if (mounted && !syncResult.success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Company selected, but sync could not complete: ${syncResult.error ?? 'Unknown error'}',
                        ),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Company selected in local mode. Connect internet to load latest server data.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }

                // Force key lists to refresh immediately for the selected company.
                ref.read(productCategoryRefreshProvider.notifier).state++;
                ref.read(inventoryProductListRefreshProvider.notifier).state++;
                ref.read(productListRefreshProvider.notifier).state++;
                ref.read(partyListRefreshProvider.notifier).state++;

                if (context.mounted) {
                  context.go('/dashboard');
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to switch company: $e'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _isSwitchingCompany = false;
                    _switchingCompanyId = null;
                  });
                }
              }
            },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade100,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    company.name.isNotEmpty ? company.name[0] : 'C',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Currency: ${company.primaryCurrency}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isSwitchingCompany && _switchingCompanyId == company.id)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No Companies Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create your first company',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
