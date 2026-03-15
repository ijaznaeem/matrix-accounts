import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veyo_sync/features/cash_in_hand.dart';
import 'package:veyo_sync/features/parties/presentation/party_form_screen.dart';
import 'package:veyo_sync/features/plans.dart';
import 'package:veyo_sync/features/profit_loss.dart';
import 'package:veyo_sync/features/purchases/presentation/purchase_return_form_screen.dart';
import 'package:veyo_sync/features/purchases/presentation/purchase_return_list_screen.dart'
    show PurchaseReturnListScreen;
import 'package:veyo_sync/features/purchases/purchase_report.dart';
import 'package:veyo_sync/features/reports/presentation/account_ledger_screen.dart';
import 'package:veyo_sync/features/sales/presentation/sale_return_form_screen.dart';
import 'package:veyo_sync/features/sales/presentation/sale_return_list_screen.dart';
import 'package:veyo_sync/features/settings/presentation/company_settings_screen.dart';
import 'package:veyo_sync/features/settings/presentation/user_access_management_screen.dart';
import 'package:veyo_sync/settings/about_settings_screen.dart';
import 'package:veyo_sync/settings/financial_year_settings_screen.dart';
import 'package:veyo_sync/settings/lock_screen.dart';
import 'package:veyo_sync/settings/setting.dart';
import 'package:veyo_sync/settings/tax_settings_screen.dart'
    show TaxSettingsScreen;
import 'package:veyo_sync/settings/theme_settings_screen.dart';

import '../../features/companies/presentation/company_form_screen.dart';
import '../../features/companies/presentation/company_list_screen.dart';
import '../../features/expenses/presentation/expense_form_screen.dart';
import '../../features/expenses/presentation/expense_list_screen.dart';
import '../../features/inventory/presentation/category_list_screen.dart';
import '../../features/inventory/presentation/product_list_screen.dart';
import '../../features/parties/presentation/party_list_screen.dart';
import '../../features/payments/presentation/payment_in_form_screen.dart';
import '../../features/payments/presentation/payment_in_list_screen.dart';
import '../../features/payments/presentation/payment_out_form_screen.dart';
import '../../features/payments/presentation/payment_out_list_screen.dart';
import '../../features/purchases/presentation/purchase_invoice_form_screen.dart';
import '../../features/purchases/presentation/purchase_invoice_list_screen.dart';
import '../../features/reports/presentation/balance_sheet_screen.dart';
import '../../features/reports/presentation/cashflow_screen.dart';
import '../../features/reports/presentation/daybook_screen.dart';
import '../../features/reports/presentation/profit_report_screen.dart';
import '../../features/reports/presentation/stock_report_screen.dart';
import '../../features/reports/presentation/trial_balance_screen.dart';
import '../../features/reports/sale_report.dart';
import '../../features/sales/presentation/sale_invoice_list_screen.dart';
import '../../features/sales/presentation/sales_invoice_form_screen.dart';
import '../../presentation/screens/about_screen.dart';
import '../../presentation/screens/admin_registration_screen.dart';
import '../../presentation/screens/company_selector_screen.dart';
import '../../presentation/screens/dashboard_screen.dart';
import '../../presentation/screens/help_screen.dart';
import '../../presentation/screens/login_screen.dart';
import '../../presentation/screens/profile_screen.dart';
import '../../presentation/screens/splash_screen.dart';

final Future<SharedPreferences> _prefsFuture = SharedPreferences.getInstance();

const Set<String> _publicPaths = {
  '/splash',
  '/login',
  '/register-admin',
  '/lock',
  '/help',
  '/about',
};

bool _isAdminOnlyPath(String path) {
  return path == '/masters/companies' ||
      path == '/masters/companies/form' ||
      path == '/settings/user-access';
}

String? _menuKeyForPath(String path) {
  if (path == '/dashboard') return 'dashboard';
  if (path.startsWith('/sales')) return 'sales';
  if (path.startsWith('/purchases') || path.startsWith('/purchase/return')) {
    return 'purchases';
  }
  if (path.startsWith('/payments')) return 'payments';
  if (path.startsWith('/expenses')) return 'expenses';
  if (path.startsWith('/accounts') || path.startsWith('/parties/stateentry')) {
    return 'accounts_parties';
  }
  if (path.startsWith('/cash-in-hand')) return 'cash_bank';
  if (path == '/masters/products' || path == '/masters/categories') {
    return 'masters_products';
  }
  if (path == '/masters/parties') return 'masters_parties';
  if (path.startsWith('/reports') || path.startsWith('/profit/loss')) {
    return 'reports';
  }
  if (path.startsWith('/settings')) return 'settings';
  if (path == '/company') return 'switch_company';
  return null;
}

Future<bool> _canAccessByRbac(String path) async {
  final prefs = await _prefsFuture;
  final hasToken = (prefs.getString('auth_token') ?? '').isNotEmpty;
  if (path == '/register-admin') {
    final anyAdminExists = prefs.getBool('rbac_any_admin_exists') ?? false;
    return !anyAdminExists;
  }

  if (_publicPaths.contains(path)) return true;

  if (!hasToken) {
    return false;
  }

  final userId = prefs.getInt('user_id');
  final selectedCompanyId = prefs.getInt('selected_company_id');
  final isAdminAnywhere = prefs.getBool('rbac_is_admin_anywhere') ?? false;
  final isAdminCurrentCompany =
      prefs.getBool('rbac_is_admin_current_company') ?? false;

  if (_isAdminOnlyPath(path)) {
    return isAdminAnywhere || isAdminCurrentCompany;
  }

  final menuKey = _menuKeyForPath(path);
  if (menuKey == null) {
    return true;
  }

  if (isAdminCurrentCompany || isAdminAnywhere) {
    return true;
  }

  if (menuKey == 'switch_company') {
    return true;
  }

  if (userId == null || selectedCompanyId == null) {
    return path == '/company';
  }

  final allowed =
      prefs.getStringList('menu_access_${userId}_$selectedCompanyId');
  if (allowed == null || allowed.isEmpty) {
    return true;
  }

  return allowed.contains(menuKey);
}

Future<String?> _redirectForAccess(GoRouterState state) async {
  final path = state.uri.path;
  final prefs = await _prefsFuture;
  final hasToken = (prefs.getString('auth_token') ?? '').isNotEmpty;
  final selectedCompanyId = prefs.getInt('selected_company_id');

  if (path == '/splash') {
    return null;
  }

  if (path == '/register-admin') {
    final anyAdminExists = prefs.getBool('rbac_any_admin_exists') ?? false;
    if (!anyAdminExists) {
      return null;
    }
    return hasToken ? '/splash' : '/login';
  }

  if (!hasToken && !_publicPaths.contains(path)) {
    return '/login';
  }

  if (hasToken && path == '/login') {
    return '/splash';
  }

  if (hasToken &&
      selectedCompanyId == null &&
      path != '/company' &&
      !_isAdminOnlyPath(path) &&
      !_publicPaths.contains(path)) {
    return '/company';
  }

  final allowed = await _canAccessByRbac(path);
  if (!allowed) {
    return selectedCompanyId != null ? '/dashboard' : '/company';
  }

  return null;
}

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) async {
      return _redirectForAccess(state);
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register-admin',
        builder: (context, state) => const AdminRegistrationScreen(),
      ),
      GoRoute(
        path: '/company',
        builder: (context, state) => const CompanySelectorScreen(),
      ),
      GoRoute(
        path: '/lock',
        builder: (context, state) => const LockScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/plans',
        builder: (context, state) => const PlansScreen(),
      ),
      GoRoute(
        path: '/sales',
        builder: (context, state) => const SaleInvoiceListScreen(),
      ),
      GoRoute(
        path: '/sales/invoice/form',
        builder: (context, state) {
          final idParam = state.uri.queryParameters['id'];
          final invoiceId = idParam != null ? int.tryParse(idParam) : null;
          return SalesInvoiceFormScreen(invoiceId: invoiceId);
        },
      ),
      GoRoute(
        path: '/purchases',
        builder: (context, state) => const PurchaseInvoiceListScreen(),
      ),
      GoRoute(
        path: '/purchases/invoice/form',
        builder: (context, state) {
          final idParam = state.uri.queryParameters['id'];
          final invoiceId = idParam != null ? int.tryParse(idParam) : null;
          return PurchaseInvoiceFormScreen(invoiceId: invoiceId);
        },
      ),
      GoRoute(
        path: '/purchases/return/form',
        builder: (context, state) => const PurchaseReturnFormScreen(),
      ),
      GoRoute(
        path: '/expenses',
        builder: (context, state) => const ExpenseListScreen(),
      ),
      GoRoute(
        path: '/expenses/form',
        builder: (context, state) {
          final idParam = state.uri.queryParameters['id'];
          final expenseId = idParam != null ? int.tryParse(idParam) : null;
          return ExpenseFormScreen(expenseId: expenseId);
        },
      ),
      GoRoute(
        path: '/payments/in',
        builder: (context, state) => const PaymentInListScreen(),
      ),
      GoRoute(
        path: '/payments/in/form',
        builder: (context, state) {
          final idParam = state.uri.queryParameters['id'];
          final paymentInId = idParam != null ? int.tryParse(idParam) : null;
          return PaymentInFormScreen(paymentInId: paymentInId);
        },
      ),
      GoRoute(
        path: '/payments/out',
        builder: (context, state) => const PaymentOutListScreen(),
      ),
      GoRoute(
        path: '/payments/out/form',
        builder: (context, state) {
          final idParam = state.uri.queryParameters['id'];
          final paymentOutId = idParam != null ? int.tryParse(idParam) : null;
          return PaymentOutFormScreen(paymentOutId: paymentOutId);
        },
      ),
      GoRoute(
        path: '/masters/companies',
        builder: (context, state) => const CompanyListScreen(),
      ),
      GoRoute(
        path: '/masters/companies/form',
        builder: (context, state) {
          final idParam = state.uri.queryParameters['id'];
          final companyId = idParam != null ? int.tryParse(idParam) : null;
          return CompanyFormScreen(companyId: companyId);
        },
      ),
      GoRoute(
        path: '/masters/parties',
        builder: (context, state) => const PartyListScreen(),
      ),
      GoRoute(
        path: '/masters/products',
        builder: (context, state) => const ProductListScreen(),
      ),
      GoRoute(
        path: '/masters/categories',
        builder: (context, state) => const CategoryListScreen(),
      ),
      GoRoute(
        path: '/reports/stock',
        builder: (context, state) => const StockReportScreen(),
      ),
      GoRoute(
        path: '/reports/profit',
        builder: (context, state) => const ProfitReportScreen(),
      ),
      GoRoute(
        path: '/reports/daybook',
        builder: (context, state) => const DaybookScreen(),
      ),
      GoRoute(
        path: '/reports/balance-sheet',
        builder: (context, state) => const BalanceSheetScreen(),
      ),
      GoRoute(
        path: '/reports/cashflow',
        builder: (context, state) => const CashFlowScreen(),
      ),
      GoRoute(
        path: '/reports/trial-balance',
        builder: (context, state) => const TrialBalanceScreen(),
      ),
      GoRoute(
          path: '/accounts/ledger',
          builder: (context, state) => const AccountLedgerScreen()),
      GoRoute(
          path: '/parties/stateentry',
          builder: (context, state) => const PartyFormScreen()),
      GoRoute(
        path: '/cash-in-hand',
        builder: (context, state) => const CashInHandScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const Settings_Screen(),
      ),
      GoRoute(
        path: '/reports/purchases',
        builder: (context, state) => const PurchaseReportScreen(),
      ),
      GoRoute(
        path: '/sales/report',
        builder: (context, state) => const SaleReportScreen(),
      ),
      GoRoute(
          path: '/profit/loss',
          builder: (context, state) {
            return const ProfitLossScreen();
          }),
      GoRoute(
          path: '/purchase/return',
          builder: (context, state) {
            return const PurchaseReturnListScreen();
          }),
      GoRoute(
        path: '/sale/return',
        builder: (context, state) => const SaleReturnListScreen(),
      ),
      GoRoute(
        path: '/sales/return/form',
        builder: (context, state) {
          final idParam = state.uri.queryParameters['id'];
          final returnId = idParam != null ? int.tryParse(idParam) : null;
          return SaleReturnFormScreen(returnId: returnId);
        },
      ),

      // Main Settings Screen
      GoRoute(
        path: '/settings',
        builder: (context, state) => const Settings_Screen(),
      ),

      // Settings Sub-screens
      GoRoute(
        path: '/settings/company-settings',
        builder: (context, state) => const CompanySettingsScreen(),
      ),
      GoRoute(
        path: '/settings/user-access',
        builder: (context, state) => const UserAccessManagementScreen(),
      ),
      GoRoute(
        path: '/settings/financial-year',
        builder: (context, state) => const FinancialYearSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/tax-settings',
        builder: (context, state) => const TaxSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/theme-settings',
        builder: (context, state) => const ThemeSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/about-settings',
        builder: (context, state) => const AboutSettingsScreen(),
      ),

      GoRoute(
        path: '/help',
        builder: (context, state) => const HelpScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
  );
}
