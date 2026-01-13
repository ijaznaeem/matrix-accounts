// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_accounts/OTHER/cash_in_hand.dart';
import 'package:matrix_accounts/features/expenses/presentation/expense_list_screen.dart';
import 'package:matrix_accounts/features/inventory/presentation/product_list_screen.dart';
import 'package:matrix_accounts/features/parties/presentation/party_list_screen.dart';
import 'package:matrix_accounts/features/payments/presentation/payment_in_list_screen.dart';
import 'package:matrix_accounts/features/payments/presentation/payment_out_list_screen.dart';
import 'package:matrix_accounts/features/purchases/presentation/purchase_invoice_list_screen.dart';
import 'package:matrix_accounts/features/reports/presentation/stock_report_screen.dart';
import 'package:matrix_accounts/features/sales/presentation/sale_invoice_list_screen.dart';
import 'package:matrix_accounts/presentation/screens/settings_screen.dart'
    show SettingsScreen;

import '../../core/config/providers.dart';
import '../../core/widgets/navigation_drawer_helper.dart';

// Provider for bottom navigation state
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width > 600;
  }

  bool _isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  bool _shouldShowBottomNav(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Hide bottom nav on large screens (tablets in landscape)
    return !(size.width > 1000 && _isLandscape(context));
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required int currentIndex,
    required VoidCallback onTap,
    required ThemeData theme,
    required bool isTablet,
    required bool showLabel,
  }) {
    final isActive = index == currentIndex;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          splashColor: theme.primaryColor.withOpacity(0.2),
          highlightColor: theme.primaryColor.withOpacity(0.1),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 12 : 8,
              vertical: isTablet ? 6 : 4,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isActive
                  ? theme.primaryColor.withOpacity(0.15)
                  : Colors.transparent,
              border: isActive
                  ? Border.all(
                      color: theme.primaryColor.withOpacity(0.3),
                      width: 1,
                    )
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOutCubic,
                  child: Icon(
                    isActive ? activeIcon : icon,
                    color: isActive ? theme.primaryColor : Colors.grey.shade600,
                    size: isTablet ? 28 : 24,
                  ),
                ),
                if (showLabel) ...[
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: 10,
                      color:
                          isActive ? theme.primaryColor : Colors.grey.shade600,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                    child: Text(label),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(currentCompanyProvider);

    return Scaffold(
      drawer: NavigationDrawerHelper.buildNavigationDrawer(
        context,
        ref: ref,
        selectedItem: 'dashboard',
      ),
      appBar: AppBar(
        title: Text(company?.name ?? 'Dashboard'),
        elevation: 0,
        backgroundColor: Colors.blueAccent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Quick Links",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final screenWidth = constraints.maxWidth;
                final isTablet = screenWidth > 600;
                final crossAxisCount = isTablet ? 4 : 3;
                final childAspectRatio = isTablet ? 1.1 : 1.0;

                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: isTablet ? 16 : 12,
                  crossAxisSpacing: isTablet ? 16 : 12,
                  childAspectRatio: childAspectRatio,
                  children: [
                    _QuickLinkCard(
                        label: 'Sales',
                        icon: Icons.point_of_sale,
                        color: Colors.green,
                        onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SaleInvoiceListScreen(),
                              ),
                            )),
                    _QuickLinkCard(
                        label: 'Purchases',
                        icon: Icons.shopping_cart,
                        color: Colors.orange,
                        onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    PurchaseInvoiceListScreen(),
                              ),
                            )),
                    _QuickLinkCard(
                        label: 'Parties',
                        icon: Icons.people,
                        color: Colors.blue,
                        onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PartyListScreen(),
                              ),
                            )),
                    _QuickLinkCard(
                        label: 'Products',
                        icon: Icons.inventory,
                        color: Colors.purple,
                        onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProductListScreen(),
                              ),
                            )),
                    _QuickLinkCard(
                        label: 'Cash & Bank',
                        icon: Icons.account_balance_wallet,
                        color: Colors.teal,
                        onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CashInHandScreen(),
                              ),
                            )),
                    _QuickLinkCard(
                        label: 'Reports',
                        icon: Icons.assessment,
                        color: Colors.indigo,
                        onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => StockReportScreen(),
                              ),
                            )),
                    _QuickLinkCard(
                        label: 'Payments In',
                        icon: Icons.monetization_on,
                        color: Colors.green.shade700,
                        onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PaymentInListScreen(),
                              ),
                            )),
                    _QuickLinkCard(
                        label: 'Payments Out',
                        icon: Icons.payment,
                        color: Colors.red.shade600,
                        onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PaymentOutListScreen(),
                              ),
                            )),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: _shouldShowBottomNav(context)
          ? Consumer(
              builder: (context, ref, child) {
                final currentIndex = ref.watch(bottomNavIndexProvider);
                final theme = Theme.of(context);
                final isTablet = _isTablet(context);
                final screenWidth = MediaQuery.of(context).size.width;

                return Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                  ),
                  child: SafeArea(
                    child: Container(
                      height: isTablet ? 64 : 56,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildNavItem(
                            context: context,
                            icon: Icons.dashboard_outlined,
                            activeIcon: Icons.dashboard,
                            label: 'Dashboard',
                            index: 0,
                            currentIndex: currentIndex,
                            onTap: () {
                              ref.read(bottomNavIndexProvider.notifier).state =
                                  0;
                              // Already on dashboard, no need to navigate
                            },
                            theme: theme,
                            isTablet: isTablet,
                            showLabel: screenWidth > 400,
                          ),
                          _buildNavItem(
                            context: context,
                            icon: Icons.receipt_long_outlined,
                            activeIcon: Icons.receipt_long,
                            label: 'Expenses',
                            index: 2,
                            currentIndex: currentIndex,
                            onTap: () {
                              ref.read(bottomNavIndexProvider.notifier).state =
                                  2;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ExpenseListScreen(),
                                ),
                              );
                            },
                            theme: theme,
                            isTablet: isTablet,
                            showLabel: screenWidth > 400,
                          ),
                          _buildNavItem(
                            context: context,
                            icon: Icons.settings_outlined,
                            activeIcon: Icons.settings,
                            label: 'Settings',
                            index: 3,
                            currentIndex: currentIndex,
                            onTap: () {
                              ref.read(bottomNavIndexProvider.notifier).state =
                                  3;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SettingsScreen(),
                                ),
                              );
                            },
                            theme: theme,
                            isTablet: isTablet,
                            showLabel: screenWidth > 400,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            )
          : null,
    );
  }
}

class _QuickLinkCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickLinkCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: color.withOpacity(0.2),
        highlightColor: color.withOpacity(0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.9),
                Colors.white.withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200.withOpacity(0.5),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.8),
                blurRadius: 1,
                offset: const Offset(0, 1),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOutCubic,
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withOpacity(0.2),
                        color.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: color.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
