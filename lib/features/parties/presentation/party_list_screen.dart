// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/database/dao/party_dao.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/widgets/navigation_drawer_helper.dart';
import '../../../data/models/party_model.dart';
import '../logic/party_provider.dart';
import 'party_form_screen.dart';
import 'party_ledger_screen.dart';

class PartyListScreen extends ConsumerStatefulWidget {
  const PartyListScreen({super.key});

  @override
  ConsumerState<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends ConsumerState<PartyListScreen> {
  PartyType? selectedPartyType;
  String searchQuery = '';

  /// Get current party balance from accounting ledger
  Future<double> _getPartyBalance(int partyId) async {
    final company = ref.read(currentCompanyProvider);
    if (company == null) return 0.0;

    final isarService = ref.read(isarServiceProvider);
    final partyDao = PartyDao(isarService.isar);

    try {
      return await partyDao.getPartyBalance(
        partyId: partyId,
        companyId: company.id,
      );
    } catch (e) {
      print('Error getting party balance: $e');
      return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final partyAsync = ref.watch(partyListProvider);
    final company = ref.watch(currentCompanyProvider);
    final settings = ref.watch(settingsProvider);
    final currencySymbol =
        SettingsConstants.currencySymbols[settings.defaultCurrency] ??
            settings.defaultCurrency;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: const Text('Party Master'),
        elevation: 0,
        actions: [
          if (company != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  company.name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
        ],
      ),
      drawer: NavigationDrawerHelper.buildNavigationDrawer(
        context,
        ref: ref,
        selectedItem: 'parties',
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PartyFormScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: partyAsync.when(
        data: (list) {
          // Filter logic
          var filteredList = list.where((party) {
            final matchesSearch =
                party.name.toLowerCase().contains(searchQuery.toLowerCase());
            final matchesType = selectedPartyType == null ||
                party.partyType == selectedPartyType;
            return matchesSearch && matchesType;
          }).toList();

          return SingleChildScrollView(
            child: Column(
              children: [
                _buildSearchBar(),
                _buildFilterChips(),
                if (filteredList.isEmpty)
                  _buildEmptyState()
                else
                  _buildPartyList(filteredList, currencySymbol),
              ],
            ),
          );
        },
        error: (_, __) => const Center(child: Text('Error loading parties')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        onChanged: (value) {
          setState(() {
            searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText: 'Search party name...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectedPartyType != null || searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Text(
                    'Active Filters',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('Clear All'),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              const Text(
                'Party Type',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<PartyType?>(
                  value: selectedPartyType,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  hint: const Text('All'),
                  items: const [
                    DropdownMenuItem<PartyType?>(
                      value: null,
                      child: Text('All'),
                    ),
                    DropdownMenuItem<PartyType?>(
                      value: PartyType.customer,
                      child: Text('Customer'),
                    ),
                    DropdownMenuItem<PartyType?>(
                      value: PartyType.supplier,
                      child: Text('Supplier'),
                    ),
                    DropdownMenuItem<PartyType?>(
                      value: PartyType.both,
                      child: Text('Both'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedPartyType = value;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPartyList(List<Party> parties, String currencySymbol) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: parties.length,
        itemBuilder: (_, i) {
          final p = parties[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildPartyCard(p, currencySymbol),
          );
        },
      ),
    );
  }

  Widget _buildPartyCard(Party party, String currencySymbol) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PartyFormScreen(party: party)),
        );
      },
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rows 1 & 2: name + live balance (via FutureBuilder)
              FutureBuilder<double>(
                future: _getPartyBalance(party.id),
                builder: (context, snapshot) {
                  final balance = snapshot.data ?? 0.0;
                  final isLoading =
                      snapshot.connectionState == ConnectionState.waiting;

                  // Positive balance = customer owes us (DR on AR) → red
                  // Zero balance → grey
                  final Color balanceColor = balance > 0
                      ? Colors.red.shade700
                      : balance < 0
                          ? Colors.green.shade700
                          : Colors.grey.shade700;

                  final String statusLabel = balance > 0
                      ? 'RECEIVABLE'
                      : balance < 0
                          ? 'CREDIT'
                          : 'CLEARED';

                  final Color statusBg = balance > 0
                      ? Colors.red.shade100
                      : balance < 0
                          ? Colors.green.shade100
                          : Colors.grey.shade100;

                  return Column(
                    children: [
                      // Row 1: Party Name + Balance Amount
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              party.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          isLoading
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.grey.shade400,
                                  ),
                                )
                              : Text(
                                  '$currencySymbol ${balance.abs().toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: balanceColor,
                                  ),
                                ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Row 2: Type Badge + Balance Status
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                _buildCompactBadge(
                                  party.partyType.name.toUpperCase(),
                                  Colors.blue,
                                ),
                                const SizedBox(width: 6),
                              ],
                            ),
                          ),
                          if (!isLoading)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: balanceColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 6),

              // Row 3: Phone (left) + Action Buttons (right)
              Row(
                children: [
                  Expanded(
                    child: party.phone != null && party.phone!.isNotEmpty
                        ? Row(
                            children: [
                              Icon(Icons.phone,
                                  size: 12, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  party.phone!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'No phone',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400,
                            ),
                          ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Party actions',
                    icon: Icon(
                      Icons.more_vert,
                      color: Colors.grey.shade700,
                    ),
                    onSelected: (value) {
                      if (value == 'ledger') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PartyLedgerScreen(party: party),
                          ),
                        );
                        return;
                      }

                      if (value == 'edit') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PartyFormScreen(party: party),
                          ),
                        );
                        return;
                      }

                      if (value == 'delete') {
                        _showDeleteConfirmation(context, party, ref);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'ledger',
                        child: Text('View Ledger'),
                      ),
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text('Edit Party'),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete Party'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(
            Icons.person_outline,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No Parties Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            searchQuery.isNotEmpty
                ? 'No parties match your search'
                : 'No parties added yet',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      selectedPartyType = null;
      searchQuery = '';
    });
  }

  void _showDeleteConfirmation(
      BuildContext context, Party party, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Party'),
        content: Text(
          'Are you sure you want to delete ${party.name}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final partyDao = ref.read(partyDaoProvider);
                await partyDao.deleteParty(party.id);
                ref.invalidate(partyListProvider);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Party deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error deleting party: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
