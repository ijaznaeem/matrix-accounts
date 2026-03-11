// ignore_for_file: unused_local_variable, avoid_print, unused_element, use_build_context_synchronously, deprecated_member_use, prefer_const_constructors

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/providers.dart';
import '../../../core/database/dao/party_dao.dart';
import '../../../core/database/dao/sales_dao.dart';
import '../../../core/services/whatsapp_service.dart';
import '../../../data/models/account_models.dart' as account_models;
import '../../../data/models/company_model.dart';
import '../../../data/models/inventory_models.dart';
import '../../../data/models/invoice_stock_models.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/payment_models.dart';
import '../../../data/models/transaction_model.dart';
import '../../../data/models/user_model.dart';
import '../../parties/logic/party_provider.dart';
import '../../parties/presentation/party_form_screen.dart';
import '../../payments/logic/payment_providers.dart';
import '../logic/sales_providers.dart';
import '../services/invoice_generator.dart';
import '../services/sales_invoice_service.dart';

class SaleLineDraft {
  int? productId;
  String? productName;
  double qty;
  double rate;

  SaleLineDraft({
    this.productId,
    this.productName,
    this.qty = 1,
    this.rate = 0,
  });
}

class PaymentLineDraft {
  int? accountId;
  String? accountName;
  String? accountIcon;
  double amount;

  PaymentLineDraft({
    this.accountId,
    this.accountName,
    this.accountIcon,
    this.amount = 0,
  });
}

class SalesInvoiceFormScreen extends ConsumerStatefulWidget {
  final int? invoiceId;

  const SalesInvoiceFormScreen({super.key, this.invoiceId});

  @override
  ConsumerState<SalesInvoiceFormScreen> createState() {
    return _SalesInvoiceFormScreenState();
  }
}

class _SalesInvoiceFormScreenState
    extends ConsumerState<SalesInvoiceFormScreen> {
  Party? _selectedCustomer;
  DateTime _date = DateTime.now();
  final _refNoCtrl = TextEditingController();
  final _customerSearchCtrl = TextEditingController();
  final _customerSearchFocus = FocusNode();
  final _itemSearchCtrl = TextEditingController();
  final _cashAmountCtrl = TextEditingController();
  final _itemSearchFocus = FocusNode();
  final List<SaleLineDraft> _lines = [];
  final List<PaymentLineDraft> _paymentLines = []; // NEW: payment lines
  final Map<int, TextEditingController> _qtyControllers = {};
  final Map<int, TextEditingController> _rateControllers = {};
  String _discountType = 'Flat';
  double _discountValue = 0;
  double _vat = 0;
  double _shippingCharge = 0;
  double _paidAmount = 0;
  double _previousBalance = 0;
  double _totalPayableAmount = 0;
  double _remainingBalance = 0;
  bool _isLoading = true;
  bool _showAllItems = false;

  @override
  void initState() {
    super.initState();
    _customerSearchFocus.addListener(() {
      setState(() {});
    });
    _itemSearchFocus.addListener(() {
      setState(() {
        _showAllItems = _itemSearchFocus.hasFocus;
        // Force rebuild when focus changes
      });
    });
    if (widget.invoiceId != null) {
      _loadInvoice();
    } else {
      _refNoCtrl.text = 'INV-${DateTime.now().millisecondsSinceEpoch}';
      _addDefaultCashPayment().then((_) {
        if (mounted) {
          setState(() => _isLoading = false);
          _calculateTotalPayable(); // Initialize calculations
        }
      });
    }
  }

  Future<void> _addDefaultCashPayment() async {
    // Load the actual cash account
    final paymentDao = ref.read(paymentDaoProvider);
    final company = ref.read(currentCompanyProvider);
    if (company != null) {
      final accounts = await paymentDao.getPaymentAccounts(company.id);
      final cashAccount = accounts
          .where((a) => a.accountType == PaymentAccountType.cash)
          .firstOrNull;

      if (cashAccount != null && mounted) {
        setState(() {
          _paymentLines.add(PaymentLineDraft(
            accountId: cashAccount.id,
            accountName: cashAccount.accountName,
            accountIcon: cashAccount.icon,
            amount: 0,
          ));
        });
      }
    }
  }

  /// Get current customer balance from accounting ledger
  Future<double> _getCustomerBalance(int customerId) async {
    final company = ref.read(currentCompanyProvider);
    if (company == null) return 0.0;

    final isarService = ref.read(isarServiceProvider);
    final partyDao = PartyDao(isarService.isar);

    try {
      return await partyDao.getPartyBalance(
        partyId: customerId,
        companyId: company.id,
      );
    } catch (e) {
      print('Error getting customer balance: $e');
      return 0.0;
    }
  }

  /// Returns the live AR balance for both the balance card and _previousBalance.
  /// A single call to [_getCustomerBalance] is enough — no need to fetch the
  /// static party.openingBalance separately.
  Future<Map<String, double>> _getCustomerBalances(int customerId) async {
    try {
      final live = await _getCustomerBalance(customerId);
      return {'current': live};
    } catch (e) {
      print('Error getting customer balances: $e');
      return {'current': 0.0};
    }
  }

  Future<void> _loadInvoice() async {
    try {
      final salesDao = ref.read(salesDaoProvider);
      final isarService = ref.read(isarServiceProvider);
      final isar = isarService.isar;

      final invoice = await salesDao.getInvoiceById(widget.invoiceId!);
      if (invoice == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invoice not found')),
          );
          Navigator.pop(context);
        }
        return;
      }

      final transaction =
          await salesDao.getTransactionForInvoice(widget.invoiceId!);
      if (transaction == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaction not found')),
          );
          Navigator.pop(context);
        }
        return;
      }

      final lines = await salesDao.getTransactionLines(transaction.id);
      final customer = await isar.partys.get(invoice.partyId);

      setState(() {
        _selectedCustomer = customer;
        _date = invoice.invoiceDate;
        _refNoCtrl.text = transaction.referenceNo;
        _lines.clear();

        for (final line in lines) {
          final productId = line.productId;
          final product =
              productId != null ? isar.products.getSync(productId) : null;
          _lines.add(SaleLineDraft(
            productId: line.productId,
            productName: product?.name ?? 'Unknown',
            qty: line.quantity,
            rate: line.unitPrice,
          ));
        }

        if (_lines.isEmpty) {
          _lines.add(SaleLineDraft());
        }

        // Restore paid amount directly from the saved invoice field —
        // this is the single source of truth; do NOT rely on reconstructing
        // it from AccountTransactions (PaymentAccount lookup can fail).
        _paidAmount = invoice.paidAmount;
        _cashAmountCtrl.text =
            invoice.paidAmount > 0 ? invoice.paidAmount.toStringAsFixed(2) : '';

        // Clear payment lines synchronously; load them below AFTER setState
        _paymentLines.clear();

        _isLoading = false;
      });

      // Await payment lines load OUTSIDE setState so the async work is not fire-and-forget.
      // _loadPaymentLines now only resolves the PaymentAccount (for accountId / icon) —
      // it no longer owns _paidAmount.
      await _loadPaymentLines(invoice.companyId, invoice.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading invoice: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _loadPaymentLines(int companyId, int invoiceId) async {
    try {
      final isarService = ref.read(isarServiceProvider);
      final isar = isarService.isar;
      final paymentDao = ref.read(paymentDaoProvider);

      // Get all payment account transactions for this invoice (manual query to avoid extension issues)
      final allAccountTransactions =
          await isar.accountTransactions.where().findAll();
      final payments = allAccountTransactions
          .where((p) =>
              p.companyId == companyId &&
              p.referenceId == invoiceId &&
              p.transactionType == account_models.TransactionType.saleInvoice)
          .toList();

      final paymentAccounts = await paymentDao.getPaymentAccounts(companyId);

      // Identify which PaymentAccount corresponds to each cash/bank transaction.
      // We intentionally do NOT override _paidAmount here — it was already set
      // from invoice.paidAmount in _loadInvoice and is the source of truth.
      bool foundPaymentLine = false;

      for (final payment in payments) {
        // Only process cash/bank debit entries (code 1000 = cash, 1100 = bank)
        final account = await isar.accounts.get(payment.accountId);
        if (account == null) continue;
        if (account.code != '1000' && account.code != '1100') continue;
        if (payment.debit <= 0) continue; // skip credit (AR reduction) entries

        final accountType = account.code == '1000'
            ? PaymentAccountType.cash
            : PaymentAccountType.bank;

        final matchingAccount = paymentAccounts
            .where((pa) => pa.accountType == accountType)
            .firstOrNull;

        if (matchingAccount != null && mounted) {
          setState(() {
            _paymentLines.add(PaymentLineDraft(
              accountId: matchingAccount.id,
              accountName: matchingAccount.accountName,
              accountIcon: matchingAccount.icon,
              // Use _paidAmount (from invoice) so the draft stays consistent
              amount: _paidAmount,
            ));
          });
          foundPaymentLine = true;
          break; // one payment line is enough for the cash receipt field
        }
      }

      // If no matching PaymentAccount was found, fall back to the default cash
      // account so the user can re-save without losing the amount.
      if (!foundPaymentLine && mounted) {
        final cashAccount = paymentAccounts
            .where((a) => a.accountType == PaymentAccountType.cash)
            .firstOrNull;

        if (cashAccount != null) {
          setState(() {
            _paymentLines.add(PaymentLineDraft(
              accountId: cashAccount.id,
              accountName: cashAccount.accountName,
              accountIcon: cashAccount.icon,
              amount: _paidAmount, // keep the amount from invoice
            ));
          });
        }
      }

      // Ensure _calculateTotalPayable reflects the restored paid amount
      // (_calculateTotalPayable calls setState internally, so don't nest it)
      if (mounted) _calculateTotalPayable();
    } catch (e) {
      // Silently fail - user can manually add payments
      print('Error loading payment lines: $e');
    }
  }

  @override
  void dispose() {
    _refNoCtrl.dispose();
    _customerSearchCtrl.dispose();
    _customerSearchFocus.dispose();
    _itemSearchCtrl.dispose();
    _itemSearchFocus.dispose();
    for (var controller in _qtyControllers.values) {
      controller.dispose();
    }
    for (var controller in _rateControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double get _subTotal =>
      _lines.fold<double>(0, (sum, l) => sum + (l.qty * l.rate));

  double get _totalQty => _lines.fold<double>(0, (sum, l) => sum + l.qty);

  double get _totalDiscount {
    if (_discountType == 'Flat') return _discountValue;
    return _subTotal * (_discountValue / 100);
  }

  double get _afterDiscount => _subTotal - _totalDiscount;

  double get _totalVAT => _afterDiscount * (_vat / 100);

  double get _grandTotal => _afterDiscount + _totalVAT + _shippingCharge;

  /// Update paid amount and recalculate remaining balance
  void _updatePaidAmount(double amount) {
    setState(() {
      _paidAmount = amount;
      // Keep the first payment line in sync so save logic always has a consistent amount
      if (_paymentLines.isNotEmpty) {
        _paymentLines[0].amount = amount;
      }
      _calculateTotalPayable(); // Recalculate when paid amount changes
    });
  }

  /// Trigger recalculation when line items change
  void _onLineItemChanged() {
    _calculateTotalPayable();
  }

  /// Returns the live AR balance for a customer using the same
  /// [PartyDao.getPartyBalance] path used by the party list and the DAO on
  /// save — so the opening balance shown on the form always matches what the
  /// party list displays.
  Future<double> _getPreviousUnpaidBalance(int customerId) =>
      _getCustomerBalance(customerId);

  /// Calculate total payable amount (previous balance + new sale amount)
  void _calculateTotalPayable() {
    final newSaleAmount =
        _subTotal; // Use subtotal to avoid circular references
    _totalPayableAmount = _previousBalance + newSaleAmount;
    _remainingBalance = _totalPayableAmount - _paidAmount;
    if (mounted) {
      setState(() {});
    }
  }

  /// Update customer selection and fetch previous balance
  Future<void> _onCustomerSelected(Party customer) async {
    setState(() {
      _selectedCustomer = customer;
      _customerSearchCtrl.text = customer.name;
    });

    // Fetch previous unpaid balance
    final previousBalance = await _getPreviousUnpaidBalance(customer.id);
    setState(() {
      _previousBalance = previousBalance;
    });

    _calculateTotalPayable();
    _customerSearchFocus.unfocus();
  }

  /// Check if customer has any previous transaction history
  Future<bool> _hasTransactionHistory(int customerId) async {
    final company = ref.read(currentCompanyProvider);
    if (company == null) return false;

    final isarService = ref.read(isarServiceProvider);
    final isar = isarService.isar;

    try {
      // Check for any previous invoices (excluding current one being edited)
      final invoicesCount = await isar.invoices
          .filter()
          .companyIdEqualTo(company.id)
          .partyIdEqualTo(customerId)
          .invoiceTypeEqualTo(InvoiceType.sale)
          .count();

      final hasInvoices = widget.invoiceId != null
          ? invoicesCount >
              1 // More than 1 means there are others besides current
          : invoicesCount > 0; // Any invoices for new invoice creation

      // Check for any payments
      final allAccountTransactions =
          await isar.accountTransactions.where().findAll();
      final paymentsCount = allAccountTransactions
          .where((p) =>
              p.companyId == company.id &&
              p.partyId == customerId &&
              (p.transactionType == account_models.TransactionType.paymentOut ||
                  p.transactionType ==
                      account_models.TransactionType.paymentIn))
          .length;

      // Check if opening balance is non-zero
      final customer = await isar.partys.get(customerId);
      final hasOpeningBalance = (customer?.openingBalance ?? 0.0) != 0.0;

      return hasInvoices || paymentsCount > 0 || hasOpeningBalance;
    } catch (e) {
      print('Error checking transaction history: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(currentCompanyProvider);
    final user = ref.watch(currentUserProvider);
    final productAsync = ref.watch(productListProvider);
    final salesDao = ref.read(salesDaoProvider);

    if (company == null) {
      return const Scaffold(
        body: Center(child: Text('No company selected')),
      );
    }

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth > 600;
        final horizontalPadding = isTablet ? 32.0 : 16.0;
        final verticalPadding = isTablet ? 24.0 : 16.0;
        final buttonHeight = isTablet ? 60.0 : 50.0;
        final fontSize = isTablet ? 18.0 : 16.0;
        final titleFontSize = isTablet ? 24.0 : 20.0;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.invoiceId != null ? 'Edit Sales' : 'Add Sales',
              style: TextStyle(fontSize: titleFontSize),
            ),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            actions: [
              // Share button for all invoices (new and existing)
              PopupMenuButton<String>(
                icon: const Icon(Icons.share),
                tooltip: 'Share Invoice',
                onSelected: (String value) {
                  if (value == 'whatsapp') {
                    _shareToWhatsApp(company);
                  } else if (value == 'pdf') {
                    _shareAsPDF(company);
                  } else if (value == 'image') {
                    _shareAsImage(company);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'whatsapp',
                    child: Row(
                      children: [
                        Icon(Icons.chat, color: Colors.green),
                        SizedBox(width: 12),
                        Text('Share to WhatsApp'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'image',
                    child: Row(
                      children: [
                        Icon(Icons.image, color: Colors.blue),
                        SizedBox(width: 12),
                        Text('Share as Image'),
                      ],
                    ),
                  ),
                ],
              ),
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
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                verticalPadding,
                horizontalPadding,
                verticalPadding + MediaQuery.of(context).viewInsets.bottom,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCustomerSelector(context),
                  SizedBox(height: verticalPadding),
                  productAsync.when(
                    data: (products) => Column(
                      children: [
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _lines.length,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: false,
                          itemBuilder: (_, i) => Padding(
                            padding:
                                EdgeInsets.only(bottom: isTablet ? 18 : 12),
                            child:
                                _buildLineItem(context, _lines[i], products, i),
                          ),
                        ),
                        SizedBox(height: isTablet ? 16 : 12),
                        _buildAddItemsSearch(
                            isTablet, fontSize, context, products),
                      ],
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) =>
                        const Center(child: Text('Error loading products')),
                  ),
                  SizedBox(height: verticalPadding * 1.5),
                  // Cash Payment Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cash Payment',
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      SizedBox(height: isTablet ? 12 : 10),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        padding: EdgeInsets.all(isTablet ? 16 : 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet,
                              color: Colors.green.shade600,
                              size: isTablet ? 22 : 20,
                            ),
                            SizedBox(width: isTablet ? 12 : 8),
                            Expanded(
                              child: TextField(
                                controller: _cashAmountCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                style: TextStyle(
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade900,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Enter cash amount',
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: isTablet ? 14 : 12,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (value) {
                                  final cashAmount =
                                      double.tryParse(value) ?? 0;
                                  _updatePaidAmount(cashAmount);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isTablet ? 12 : 8),
                      Row(
                        children: [
                          Container(
                            width: isTablet ? 20 : 16,
                            height: isTablet ? 20 : 16,
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Icon(
                              Icons.account_balance_wallet,
                              size: isTablet ? 12 : 10,
                              color: Colors.green.shade600,
                            ),
                          ),
                          SizedBox(width: isTablet ? 8 : 6),
                          Text(
                            'Cash',
                            style: TextStyle(
                              fontSize: isTablet ? 14 : 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Spacer(),
                          Icon(
                            Icons.delete_outline,
                            color: Colors.red.shade400,
                            size: isTablet ? 18 : 16,
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: verticalPadding),
                  // Summary Card - Total and Balance
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade200,
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(isTablet ? 20 : 16),
                    child: Column(
                      children: [
                        // Total Quantity Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Quantity',
                              style: TextStyle(
                                fontSize: isTablet ? 16 : 14,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _totalQty == _totalQty.roundToDouble()
                                  ? _totalQty.toStringAsFixed(0)
                                  : _totalQty.toStringAsFixed(2),
                              style: TextStyle(
                                fontSize: isTablet ? 18 : 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: isTablet ? 12 : 10),
                        Divider(color: Colors.grey.shade300),
                        SizedBox(height: isTablet ? 12 : 10),
                        // Total Amount Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Amount',
                              style: TextStyle(
                                fontSize: isTablet ? 16 : 14,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  'RS ',
                                  style: TextStyle(
                                    fontSize: isTablet ? 14 : 12,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _grandTotal.toStringAsFixed(2),
                                  style: TextStyle(
                                    fontSize: isTablet ? 18 : 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: isTablet ? 12 : 10),
                        Divider(color: Colors.grey.shade300),
                        SizedBox(height: isTablet ? 12 : 10),
                        // Paid Amount Row - only show if paid amount is entered
                        if (_paidAmount > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Paid Amount',
                                style: TextStyle(
                                  fontSize: isTablet ? 16 : 14,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    'RS ',
                                    style: TextStyle(
                                      fontSize: isTablet ? 14 : 12,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    _paidAmount.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: isTablet ? 18 : 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: isTablet ? 12 : 10),
                          Divider(color: Colors.grey.shade300),
                          SizedBox(height: isTablet ? 12 : 10),
                          // Balance Due Row - only show if paid amount is entered
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Balance Due',
                                style: TextStyle(
                                  fontSize: isTablet ? 16 : 14,
                                  color: Colors.grey.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    'RS ',
                                    style: TextStyle(
                                      fontSize: isTablet ? 14 : 12,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    (_grandTotal - _paidAmount)
                                        .toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: isTablet ? 20 : 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.grey.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: verticalPadding * 1.5),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                                vertical: isTablet ? 16 : 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(
                                color: Colors.grey.shade400, width: 2),
                          ),
                          onPressed: () {
                            Navigator.of(context).maybePop();
                          },
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isTablet ? 12 : 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            padding: EdgeInsets.symmetric(
                                vertical: isTablet ? 16 : 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          onPressed: () async {
                            await _saveSalesInvoice(salesDao, company, user);
                          },
                          child: Text(
                            'Save',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveSalesInvoice(
      SalesDao salesDao, Company company, User? user) async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a customer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final validLines = _lines
        .where((l) => l.productId != null && l.qty > 0 && l.rate > 0)
        .toList();

    if (validLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one item'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final inputs = validLines
        .map((l) => SaleLineInput(
              productId: l.productId!,
              qty: l.qty,
              rate: l.rate,
            ))
        .toList();

    // Build payment input directly from _paidAmount + the first payment line's accountId.
    // _updatePaidAmount() keeps _paymentLines[0].amount in sync, so _paidAmount is the
    // single source of truth; no shallow-copy mutation needed.
    List<PaymentLineInput>? paymentInputs;
    if (_paidAmount > 0) {
      // Guard: amount entered but no payment account available → show error, abort
      if (_paymentLines.isEmpty || _paymentLines[0].accountId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No payment account found. '
                'Please set up a Cash/Bank account under Settings before recording a payment.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      paymentInputs = [
        PaymentLineInput(
          paymentAccountId: _paymentLines[0].accountId!,
          amount: _paidAmount,
        ),
      ];
    }

    try {
      if (widget.invoiceId != null) {
        // Update existing invoice
        await salesDao.updateSaleInvoice(
          invoiceId: widget.invoiceId!,
          companyId: company.id,
          customer: _selectedCustomer!,
          date: _date,
          referenceNo: _refNoCtrl.text.trim(),
          lines: inputs,
          paymentLines: paymentInputs,
          userId: user?.id,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invoice updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Create new invoice
        await salesDao.createSaleInvoice(
          companyId: company.id,
          customer: _selectedCustomer!,
          date: _date,
          referenceNo: _refNoCtrl.text.trim(),
          lines: inputs,
          paymentLines: paymentInputs,
          userId: user?.id,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invoice saved successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Widget _buildCustomerSelector(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final partyAsync = ref.watch(partyListProvider);

    return partyAsync.when(
      data: (parties) {
        // Show all parties regardless of type
        final allParties = parties.toList();
        final searchQuery = _customerSearchCtrl.text.toLowerCase();
        final filtered = allParties
            .where((c) => c.name.toLowerCase().contains(searchQuery))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Single row with customer selector and balance
            Row(
              children: [
                // Customer Selector (left side)
                Expanded(
                  flex: _selectedCustomer != null ? 2 : 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedCustomer != null
                            ? const Color(0xFFFF8C42)
                            : Colors.grey.shade300,
                        width: 2,
                      ),
                      color: Colors.white,
                      boxShadow: _customerSearchFocus.hasFocus
                          ? [
                              BoxShadow(
                                color: Colors.grey.shade200,
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: TextField(
                      controller: _customerSearchCtrl,
                      focusNode: _customerSearchFocus,
                      onChanged: (value) => setState(() {}),
                      onTap: () {
                        // Show all customers when field is tapped
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        hintText: _selectedCustomer?.name ?? 'Search Party',
                        hintStyle: TextStyle(
                          color: _selectedCustomer?.name != null
                              ? Colors.grey.shade900
                              : Colors.grey.shade500,
                          fontSize: isTablet ? 15 : 13,
                        ),
                        prefixIcon: Icon(
                          Icons.business,
                          size: isTablet ? 20 : 18,
                          color: _selectedCustomer != null
                              ? const Color(0xFFFF8C42)
                              : Colors.grey.shade400,
                        ),
                        suffixIcon: _selectedCustomer != null
                            ? IconButton(
                                icon:
                                    Icon(Icons.clear, size: isTablet ? 18 : 16),
                                onPressed: () {
                                  setState(() {
                                    _selectedCustomer = null;
                                    _customerSearchCtrl.clear();
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 12 : 10,
                          vertical: isTablet ? 12 : 10,
                        ),
                      ),
                    ),
                  ),
                ),
                // Customer Current Balance Display (right side)
                if (_selectedCustomer != null) ...[
                  SizedBox(width: isTablet ? 12 : 8),
                  Expanded(
                    flex: 1,
                    child: FutureBuilder<Map<String, double>>(
                      future: _getCustomerBalances(_selectedCustomer!.id),
                      builder: (context, snapshot) {
                        final balances = snapshot.data ?? {'current': 0.0};
                        final liveBalance = balances['current'] ?? 0.0;
                        final isLoading =
                            snapshot.connectionState == ConnectionState.waiting;

                        return Container(
                          decoration: BoxDecoration(
                            color: liveBalance <= 0
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: liveBalance <= 0
                                  ? Colors.green.shade300
                                  : Colors.orange.shade300,
                              width: 1.5,
                            ),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 12 : 8,
                            vertical: isTablet ? 12 : 10,
                          ),
                          child: Row(
                            children: [
                              if (isLoading)
                                SizedBox(
                                  width: isTablet ? 16 : 14,
                                  height: isTablet ? 16 : 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.grey.shade600,
                                  ),
                                )
                              else
                                Icon(
                                  liveBalance <= 0
                                      ? Icons.check_circle_outline
                                      : Icons.account_balance_wallet,
                                  size: isTablet ? 18 : 16,
                                  color: liveBalance <= 0
                                      ? Colors.green.shade600
                                      : Colors.orange.shade700,
                                ),
                              SizedBox(width: isTablet ? 8 : 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Prev. Balance',
                                      style: TextStyle(
                                        fontSize: isTablet ? 9 : 8,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      isLoading
                                          ? '...'
                                          : 'Rs ${liveBalance.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: isTablet ? 11 : 10,
                                        fontWeight: FontWeight.w600,
                                        color: liveBalance <= 0
                                            ? Colors.green.shade600
                                            : Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),

            // Dropdown suggestions - show all customers when focused or when searching
            if (_customerSearchFocus.hasFocus || searchQuery.isNotEmpty)
              Container(
                // decoration: BoxDecoration(
                //   color: Colors.white,
                //   border: Border(
                //     left: BorderSide(color: Colors.grey.shade300),
                //     right: BorderSide(color: Colors.grey.shade300),
                //     bottom: BorderSide(color: Colors.grey.shade300),
                //   ),
                //   borderRadius: const BorderRadius.only(
                //     bottomLeft: Radius.circular(8),
                //     bottomRight: Radius.circular(8),
                //   ),
                // ),
                constraints: BoxConstraints(
                  maxHeight: searchQuery.isEmpty
                      ? (allParties.length * (isTablet ? 65.0 : 55.0)) +
                          (_selectedCustomer == null
                              ? (isTablet ? 70.0 : 60.0)
                              : 0)
                      : (filtered.length * (isTablet ? 65.0 : 55.0)) +
                          (_selectedCustomer == null
                              ? (isTablet ? 70.0 : 60.0)
                              : 0),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Add New Party button (only show when no customer is selected)
                    if (_selectedCustomer == null)
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.person_add,
                            color: Colors.green.shade600,
                            size: isTablet ? 20 : 18,
                          ),
                          title: Text(
                            searchQuery.isNotEmpty
                                ? 'Add "$searchQuery" as new supplier'
                                : 'Add New Supplier',
                            style: TextStyle(
                              fontSize: isTablet ? 14 : 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            size: isTablet ? 16 : 14,
                            color: Colors.green.shade600,
                          ),
                          onTap: () {
                            if (searchQuery.isNotEmpty) {
                              _addNewPartyWithName(searchQuery);
                            } else {
                              _addNewParty();
                            }
                          },
                        ),
                      ),
                    // Existing customers list
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const ClampingScrollPhysics(),
                        itemCount: searchQuery.isEmpty
                            ? allParties.length
                            : filtered.length,
                        itemBuilder: (context, index) {
                          final party = searchQuery.isEmpty
                              ? allParties[index]
                              : filtered[index];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: isTablet ? 16 : 14,
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                party.name.isNotEmpty
                                    ? party.name[0].toUpperCase()
                                    : 'C',
                                style: TextStyle(
                                  fontSize: isTablet ? 14 : 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                            title: Text(
                              party.name,
                              style: TextStyle(
                                fontSize: isTablet ? 14 : 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              size: isTablet ? 14 : 12,
                              color: Colors.grey.shade400,
                            ),
                            onTap: () {
                              _onCustomerSelected(party);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Text('Error loading customers'),
      ),
    );
  }

  Widget _buildLineItem(
    BuildContext context,
    SaleLineDraft line,
    List<Product> products,
    int index,
  ) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final amount = (line.qty * line.rate).toStringAsFixed(2);

    // Ensure controllers exist for this index
    if (!_qtyControllers.containsKey(index)) {
      _qtyControllers[index] = TextEditingController(
        text: line.qty > 0
            ? (line.qty == line.qty.roundToDouble()
                ? line.qty.toStringAsFixed(0)
                : line.qty.toString())
            : '',
      );
    }
    if (!_rateControllers.containsKey(index)) {
      _rateControllers[index] = TextEditingController(
        text: line.rate > 0 ? line.rate.toStringAsFixed(2) : '',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.all(isTablet ? 16 : 12),
      child: Row(
        children: [
          // Product Name and Calculation
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.productName ?? 'Tap to select product',
                  style: TextStyle(
                    fontSize: isTablet ? 16 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${line.qty.toStringAsFixed(line.qty == line.qty.roundToDouble() ? 0 : 2)} X ${line.rate.toStringAsFixed(2)} = $amount',
                  style: TextStyle(
                    fontSize: isTablet ? 12 : 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Quantity Field
          SizedBox(
            width: isTablet ? 80 : 60,
            height: isTablet ? 40 : 35,
            child: TextFormField(
              controller: _qtyControllers[index],
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              style: TextStyle(fontSize: isTablet ? 14 : 12),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  vertical: isTablet ? 8 : 6,
                  horizontal: 4,
                ),
                isDense: true,
              ),
              onChanged: (value) {
                if (value.isNotEmpty) {
                  final qty = double.tryParse(value);
                  if (qty != null && qty > 0 && qty != line.qty) {
                    setState(() {
                      line.qty = qty;
                    });
                    _onLineItemChanged(); // Trigger recalculation
                  }
                }
              },
            ),
          ),
          const SizedBox(width: 8),

          const SizedBox(width: 8),
          // Rate Field
          SizedBox(
            width: isTablet ? 100 : 80,
            height: isTablet ? 40 : 35,
            child: TextFormField(
              controller: _rateControllers[index],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              style: TextStyle(fontSize: isTablet ? 14 : 12),
              decoration: InputDecoration(
                labelText: 'Rate',
                labelStyle: TextStyle(fontSize: isTablet ? 12 : 10),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 12 : 8,
                  vertical: isTablet ? 8 : 6,
                ),
              ),
              onChanged: (v) {
                if (v.isNotEmpty) {
                  final rate = double.tryParse(v);
                  if (rate != null && rate != line.rate) {
                    setState(() {
                      line.rate = rate;
                    });
                    _onLineItemChanged(); // Trigger recalculation
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddItemsSearch(bool isTablet, double fontSize,
      BuildContext context, List<Product> products) {
    final searchQuery = _itemSearchCtrl.text.toLowerCase();

    // Enhanced search - search by name, SKU, and category
    final filtered = searchQuery.isEmpty
        ? products // Show all products when no search query
        : products.where((p) {
            final nameMatch = p.name.toLowerCase().contains(searchQuery);
            final skuMatch = p.sku.toLowerCase().contains(searchQuery);
            return nameMatch || skuMatch;
          }).toList();

    // Sort filtered results by relevance (exact matches first, then partial matches)
    if (searchQuery.isNotEmpty) {
      filtered.sort((a, b) {
        final aNameExact = a.name.toLowerCase() == searchQuery;
        final bNameExact = b.name.toLowerCase() == searchQuery;
        final aSkuExact = a.sku.toLowerCase() == searchQuery;
        final bSkuExact = b.sku.toLowerCase() == searchQuery;

        if (aNameExact && !bNameExact) return -1;
        if (bNameExact && !aNameExact) return 1;
        if (aSkuExact && !bSkuExact) return -1;
        if (bSkuExact && !aSkuExact) return 1;

        return a.name.compareTo(b.name);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextField(
            controller: _itemSearchCtrl,
            focusNode: _itemSearchFocus,
            onChanged: (value) => setState(() {}),
            onTap: () {
              setState(() {
                _showAllItems = true;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search & Add Items (Name, SKU)...',
              hintStyle: TextStyle(
                color: Colors.grey.shade500,
                fontSize: isTablet ? 15 : 13,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: isTablet ? 22 : 20,
                color: Colors.red.shade600,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_itemSearchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.clear, size: isTablet ? 18 : 16),
                      onPressed: () {
                        setState(() {
                          _itemSearchCtrl.clear();
                        });
                      },
                    ),
                  Icon(
                    Icons.add_circle_outline,
                    size: isTablet ? 20 : 18,
                    color: Colors.red.shade600,
                  ),
                  SizedBox(width: isTablet ? 8 : 6),
                ],
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: isTablet ? 12 : 10,
                vertical: isTablet ? 12 : 10,
              ),
            ),
          ),
        ),
        // Enhanced dropdown suggestions - show items when search is focused or has text
        if (_itemSearchFocus.hasFocus || _itemSearchCtrl.text.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                left: BorderSide(color: Colors.grey.shade300),
                right: BorderSide(color: Colors.grey.shade300),
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            constraints: BoxConstraints(
              maxHeight: isTablet ? 300 : 250,
            ),
            child: Column(
              children: [
                // Header showing count
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 12 : 10,
                    vertical: isTablet ? 8 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        searchQuery.isEmpty
                            ? 'All Items (${filtered.length})'
                            : 'Found ${filtered.length} items',
                        style: TextStyle(
                          fontSize: isTablet ? 12 : 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (searchQuery.isNotEmpty)
                        Text(
                          'Tap to add',
                          style: TextStyle(
                            fontSize: isTablet ? 10 : 9,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                ),
                // Items list
                Expanded(
                  child: filtered.isEmpty
                      ? Container(
                          padding: EdgeInsets.all(isTablet ? 20 : 16),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.inventory_2_outlined,
                                  size: isTablet ? 32 : 28,
                                  color: Colors.grey.shade400,
                                ),
                                SizedBox(height: isTablet ? 8 : 6),
                                Text(
                                  searchQuery.isNotEmpty
                                      ? 'No items found for "$searchQuery"'
                                      : 'No products available',
                                  style: TextStyle(
                                    fontSize: isTablet ? 14 : 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final product = filtered[index];
                            final isAlreadyAdded = _lines
                                .any((line) => line.productId == product.id);

                            return ListTile(
                              dense: true,
                              leading: Container(
                                width: isTablet ? 40 : 32,
                                height: isTablet ? 40 : 32,
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: isAlreadyAdded
                                    ? Stack(
                                        children: [
                                          Positioned.fill(
                                            child: Icon(
                                              Icons.add,
                                              size: isTablet ? 20 : 16,
                                              color: Colors.red.shade600,
                                            ),
                                          ),
                                          Positioned(
                                            top: 2,
                                            right: 2,
                                            child: Container(
                                              width: 12,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.check,
                                                size: 8,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Icon(
                                        Icons.add,
                                        size: isTablet ? 20 : 16,
                                        color: Colors.red.shade600,
                                      ),
                              ),
                              title: Text(
                                product.name,
                                style: TextStyle(
                                  fontSize: isTablet ? 14 : 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (product.sku.isNotEmpty)
                                    Text(
                                      'SKU: ${product.sku}',
                                      style: TextStyle(
                                        fontSize: isTablet ? 10 : 9,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      Text(
                                        'Rate: RS ${product.salePrice.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: isTablet ? 11 : 10,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.red.shade700,
                                        ),
                                      ),
                                      if (isAlreadyAdded) ...[
                                        SizedBox(width: 8),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade100,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            'Added',
                                            style: TextStyle(
                                              fontSize: isTablet ? 9 : 8,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.green.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () {
                                setState(() {
                                  _lines.add(SaleLineDraft(
                                    productId: product.id,
                                    productName: product.name,
                                    qty: 1,
                                    rate:
                                        0, // Start with empty rate for custom entry
                                  ));
                                  // Keep search field and items visible after selection
                                });
                                _onLineItemChanged(); // Trigger recalculation

                                // Show success feedback
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '${product.name} added to invoice${isAlreadyAdded ? ' (duplicate)' : ''}'),
                                    backgroundColor: Colors.green,
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCalculationCard() {
    final isTablet = MediaQuery.of(context).size.width > 600;
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      child: Column(
        children: [
          _buildCalcRow('Sub Total', _subTotal, isTablet: isTablet),
          const Divider(),
          Row(
            children: [
              Expanded(
                  child: Text('Discount',
                      style: TextStyle(fontSize: isTablet ? 16 : 14))),
              SizedBox(
                width: isTablet ? 90 : 70,
                child: DropdownButton<String>(
                  value: _discountType,
                  isExpanded: true,
                  items: ['Flat', '%']
                      .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text(e,
                                style: TextStyle(fontSize: isTablet ? 16 : 14)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _discountType = v ?? 'Flat');
                  },
                ),
              ),
              SizedBox(width: isTablet ? 12 : 8),
              SizedBox(
                width: isTablet ? 90 : 70,
                child: TextField(
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onChanged: (v) {
                    setState(() => _discountValue = double.tryParse(v) ?? 0);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(_totalDiscount.toStringAsFixed(2)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: Text('VAT',
                      style: TextStyle(fontSize: isTablet ? 16 : 14))),
              SizedBox(
                width: isTablet ? 90 : 70,
                child: DropdownButton<String>(
                  value: '%',
                  isExpanded: true,
                  items: ['%']
                      .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text(e,
                                style: TextStyle(fontSize: isTablet ? 16 : 14)),
                          ))
                      .toList(),
                  onChanged: (_) {},
                ),
              ),
              SizedBox(width: isTablet ? 12 : 8),
              SizedBox(
                width: isTablet ? 90 : 70,
                child: TextField(
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: 'Select',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onChanged: (v) {
                    setState(() => _vat = double.tryParse(v) ?? 0);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(_totalVAT.toStringAsFixed(2)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: Text('Shipping Charge',
                      style: TextStyle(fontSize: isTablet ? 16 : 14))),
              const Spacer(),
              SizedBox(
                width: isTablet ? 90 : 70,
                child: TextField(
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onChanged: (v) {
                    setState(() => _shippingCharge = double.tryParse(v) ?? 0);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(_shippingCharge.toStringAsFixed(2)),
            ],
          ),
          const Divider(),
          _buildCalcRow('Total', _grandTotal, isBold: true, isTablet: isTablet),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Text('Rounding (+/-)')),
              const Spacer(),
              SizedBox(
                width: 70,
                child: Container(),
              ),
              const SizedBox(width: 8),
              const Text('0'),
            ],
          ),
          const SizedBox(height: 12),
          _buildCalcRow('Rounded Total', _grandTotal,
              isBold: true, isTablet: isTablet),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(child: Text('Received Amount')),
              Spacer(),
              SizedBox(
                width: 70,
                child: TextField(
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text('0'),
            ],
          ),
          const Divider(),
          _buildCalcRow('Due Amount', _grandTotal,
              isBold: true, isTablet: isTablet),
        ],
      ),
    );
  }

  Widget _buildCalcRow(String label, double value,
      {bool isBold = false, bool isTablet = false, bool isQuantity = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isTablet ? 16 : 14,
          ),
        ),
        Text(
          isQuantity
              ? (value == value.roundToDouble()
                  ? value.toStringAsFixed(0)
                  : value.toStringAsFixed(2))
              : value.toStringAsFixed(2),
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isTablet ? 16 : 14,
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceSummaryCard(bool isTablet) {
    final validLines =
        _lines.where((l) => l.productId != null && l.qty > 0 && l.rate > 0);
    final totalQty = validLines.fold<double>(0, (sum, l) => sum + l.qty);
    final totalAmount =
        validLines.fold<double>(0, (sum, l) => sum + (l.qty * l.rate));
    final balanceDue = totalAmount - _paidAmount;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Column(
          children: [
            // Billed Items Header
            Container(
              padding: EdgeInsets.all(isTablet ? 16 : 12),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                color: Colors.grey.shade50,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Billed Items',
                    style: TextStyle(
                      fontSize: isTablet ? 16 : 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  Text(
                    'Delete Items',
                    style: TextStyle(
                      fontSize: isTablet ? 12 : 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            // Items List Table
            if (validLines.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 16 : 12,
                  vertical: isTablet ? 12 : 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                        flex: 2,
                        child: Text('Item Name',
                            style: TextStyle(
                                fontSize: isTablet ? 12 : 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600))),
                    Expanded(
                        child: Text('Qty',
                            style: TextStyle(
                                fontSize: isTablet ? 12 : 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600),
                            textAlign: TextAlign.center)),
                    Expanded(
                        child: Text('Rate',
                            style: TextStyle(
                                fontSize: isTablet ? 12 : 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600),
                            textAlign: TextAlign.center)),
                    Expanded(
                        child: Text('Amount',
                            style: TextStyle(
                                fontSize: isTablet ? 12 : 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600),
                            textAlign: TextAlign.right)),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              ...validLines
                  .map((line) => Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 16 : 12,
                            vertical: isTablet ? 10 : 8),
                        child: Row(
                          children: [
                            Expanded(
                                flex: 2,
                                child: Text(line.productName ?? 'Unknown',
                                    style: TextStyle(
                                        fontSize: isTablet ? 13 : 11,
                                        color: Colors.grey.shade900),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            Expanded(
                                child: Text(
                                    line.qty == line.qty.roundToDouble()
                                        ? line.qty.toStringAsFixed(0)
                                        : line.qty.toStringAsFixed(2),
                                    style: TextStyle(
                                        fontSize: isTablet ? 13 : 11,
                                        color: Colors.grey.shade700),
                                    textAlign: TextAlign.center)),
                            Expanded(
                                child: Text(line.rate.toStringAsFixed(2),
                                    style: TextStyle(
                                        fontSize: isTablet ? 13 : 11,
                                        color: Colors.grey.shade700),
                                    textAlign: TextAlign.center)),
                            Expanded(
                                child: Text(
                                    (line.qty * line.rate).toStringAsFixed(1),
                                    style: TextStyle(
                                        fontSize: isTablet ? 13 : 11,
                                        color: Colors.grey.shade900,
                                        fontWeight: FontWeight.w600),
                                    textAlign: TextAlign.right)),
                          ],
                        ),
                      ))
                  .toList(),
              Divider(height: 1, color: Colors.grey.shade300),
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 16 : 12,
                    vertical: isTablet ? 10 : 8),
                child: Row(
                  children: [
                    Expanded(
                        flex: 2,
                        child: Text('Total',
                            style: TextStyle(
                                fontSize: isTablet ? 14 : 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade900))),
                    Expanded(
                        child: Text(totalQty.toStringAsFixed(1),
                            style: TextStyle(
                                fontSize: isTablet ? 14 : 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade900),
                            textAlign: TextAlign.center)),
                    const Expanded(child: SizedBox()),
                    Expanded(
                        child: Text(totalAmount.toStringAsFixed(1),
                            style: TextStyle(
                                fontSize: isTablet ? 14 : 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade900),
                            textAlign: TextAlign.right)),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
            ],
            // Total Amount
            Padding(
              padding: EdgeInsets.all(isTablet ? 16 : 12),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Amount',
                        style: TextStyle(
                            fontSize: isTablet ? 14 : 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500)),
                    Row(children: [
                      Text('Rs',
                          style: TextStyle(
                              fontSize: isTablet ? 14 : 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500)),
                      SizedBox(width: isTablet ? 16 : 12),
                      Text(totalAmount.toStringAsFixed(1),
                          style: TextStyle(
                              fontSize: isTablet ? 18 : 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade900))
                    ]),
                  ]),
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            // Paid Section
            Padding(
              padding: EdgeInsets.all(isTablet ? 16 : 12),
              child: Row(children: [
                Checkbox(value: _paidAmount > 0, onChanged: (value) {}),
                Text('Paid',
                    style: TextStyle(
                        fontSize: isTablet ? 14 : 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500)),
                const Spacer(),
                Text('Rs',
                    style: TextStyle(
                        fontSize: isTablet ? 12 : 11,
                        color: Colors.grey.shade600)),
                SizedBox(width: isTablet ? 12 : 8),
                SizedBox(
                  width: isTablet ? 140 : 100,
                  child: TextField(
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    controller: TextEditingController(
                        text: _paidAmount > 0
                            ? _paidAmount.toStringAsFixed(2)
                            : ''),
                    style: TextStyle(fontSize: isTablet ? 14 : 12),
                    decoration: InputDecoration(
                        isDense: true,
                        border: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: Colors.grey.shade300)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6)),
                    onChanged: (value) => setState(
                        () => _paidAmount = double.tryParse(value) ?? 0),
                  ),
                ),
              ]),
            ),
            Divider(height: 1, color: Colors.grey.shade300),
            // Balance Due
            Container(
              padding: EdgeInsets.all(isTablet ? 16 : 12),
              decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12)),
                  color: const Color(0xFF26C485).withOpacity(0.05)),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Balance Due',
                        style: TextStyle(
                            fontSize: isTablet ? 16 : 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF26C485))),
                    Row(children: [
                      Text('Rs',
                          style: TextStyle(
                              fontSize: isTablet ? 14 : 12,
                              color: const Color(0xFF26C485),
                              fontWeight: FontWeight.w600)),
                      SizedBox(width: isTablet ? 16 : 12),
                      Text(balanceDue.toStringAsFixed(1),
                          style: TextStyle(
                              fontSize: isTablet ? 20 : 18,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF26C485)))
                    ]),
                  ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentLinesSection() {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final paymentAccountsAsync = ref.watch(paymentAccountsProvider);

    return paymentAccountsAsync.when(
      data: (accounts) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        padding: EdgeInsets.all(isTablet ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet,
                        color: Colors.green.shade600),
                    const SizedBox(width: 8),
                    const Text(
                      'Payment Accounts',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: () => _showPaymentTypeDialog(accounts),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_paymentLines.isEmpty)
              Container(
                padding: EdgeInsets.symmetric(
                  vertical: isTablet ? 20 : 16,
                ),
                child: Center(
                  child: Text(
                    'Tap "Add" to add payment accounts',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: isTablet ? 16 : 14,
                    ),
                  ),
                ),
              )
            else
              Column(
                children: List.generate(_paymentLines.length, (index) {
                  return _buildPaymentLine(
                      _paymentLines[index], accounts, index);
                }),
              ),
          ],
        ),
      ),
      loading: () => const CircularProgressIndicator(),
      error: (_, __) => const Text('Error loading payment accounts'),
    );
  }

  Widget _buildPaymentLine(
    PaymentLineDraft line,
    List<PaymentAccount> accounts,
    int index,
  ) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    return Container(
      margin: EdgeInsets.only(bottom: isTablet ? 12 : 8),
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 8 : 4,
        vertical: isTablet ? 8 : 6,
      ),
      child: Row(
        children: [
          Text(
            line.accountIcon ?? '💰',
            style: TextStyle(fontSize: isTablet ? 26 : 22),
          ),
          SizedBox(width: isTablet ? 12 : 8),
          Expanded(
            child: Text(
              line.accountName ?? 'Unknown',
              style: TextStyle(
                fontSize: isTablet ? 17 : 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: Colors.red,
              size: isTablet ? 24 : 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              try {
                setState(() => _paymentLines.removeAt(index));
              } catch (e) {
                print('Error removing payment line: $e');
              }
            },
          ),
          SizedBox(width: isTablet ? 12 : 8),
          SizedBox(
            width: isTablet ? 160 : 140,
            child: TextFormField(
              key: ValueKey('payment_amount_${index}_${line.accountId}'),
              initialValue:
                  line.amount > 0 ? line.amount.toStringAsFixed(2) : '',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              style: TextStyle(fontSize: isTablet ? 16 : 14),
              decoration: InputDecoration(
                prefixText: 'RS ',
                prefixStyle: TextStyle(
                  fontSize: isTablet ? 16 : 14,
                  color: Colors.grey.shade700,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 12 : 8,
                  vertical: isTablet ? 10 : 8,
                ),
              ),
              onChanged: (value) {
                try {
                  final amount = double.tryParse(value) ?? 0;
                  if (amount != line.amount) {
                    setState(() {
                      line.amount = amount;
                    });
                  }
                } catch (e) {
                  print('Error updating payment amount: $e');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentTypeDialog(List<PaymentAccount> accounts) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Payment Account',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...accounts.where((account) {
                final name = account.accountName.toLowerCase();
                return !name.contains('cheque') && !name.contains('check');
              }).map((account) {
                return ListTile(
                  leading: Text(
                    account.icon ?? '💰',
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(account.accountName),
                  subtitle: account.accountType == PaymentAccountType.bank
                      ? Text(account.bankName ?? '')
                      : null,
                  onTap: () {
                    setState(() {
                      _paymentLines.add(PaymentLineDraft(
                        accountId: account.id,
                        accountName: account.accountName,
                        accountIcon: account.icon,
                        amount: 0,
                      ));
                    });
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _shareAsPDF(Company company) async {
    if (widget.invoiceId == null) return;

    try {
      // Get the invoice data
      final invoiceData = await _getInvoiceDataForShare(company);
      if (invoiceData == null) return;
    } catch (e) {
      print('Error sharing PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareToWhatsApp(Company company) async {
    if (widget.invoiceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please save the invoice first before sharing'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Sending via WhatsApp...'),
            ],
          ),
        ),
      );

      // Get the invoice data
      final invoiceData = await _getInvoiceDataForShare(company);
      if (invoiceData == null) {
        if (mounted) Navigator.pop(context); // Close loading dialog
        return;
      }

      final customer = invoiceData['customer'] as Party;
      final transaction = invoiceData['transaction'] as Transaction;
      final invoice = invoiceData['invoice'] as Invoice;

      if (mounted) Navigator.pop(context); // Close loading dialog

      // Use enhanced WhatsApp service with automatic phone detection
      final whatsappService = WhatsAppService();

      // Extract customer phone number from various sources
      String? customerPhone = customer.phone;
      if (customerPhone == null || customerPhone.isEmpty) {
        // Try to extract from customer name or address
        customerPhone = WhatsAppService.extractPhoneNumber(customer.name) ??
            WhatsAppService.extractPhoneNumber(customer.address);
      }

      final success = await whatsappService.shareInvoice(
        invoiceNumber: transaction.referenceNo,
        amount: invoice.grandTotal,
        currency: 'Rs',
        customerName: customer.name,
        customerPhone: customerPhone,
        invoiceType: 'Sales Invoice',
        additionalDetails:
            'Date: ${invoice.invoiceDate.toString().split(' ')[0]}',
      );

      if (mounted) {
        if (success) {
          // Also generate and share the invoice image if phone number was found
          if (customerPhone != null && customerPhone.isNotEmpty) {
            // Generate invoice image for attachment
            final imageBytes = await InvoiceGenerator.generateInvoiceImage(
              company: invoiceData['company'],
              party: invoiceData['customer'],
              invoice: invoiceData['invoice'],
              transaction: invoiceData['transaction'],
              lineItems: invoiceData['lineItems'],
              paymentLines: invoiceData['paymentDetails'],
              customerBalance: invoiceData['customerBalance'],
              openingBalance: invoiceData['openingBalance'],
            );

            // Save image to temporary directory
            final tempDir = await getTemporaryDirectory();
            final fileName =
                'invoice_${transaction.referenceNo}_${DateTime.now().millisecondsSinceEpoch}.png';
            final file = File('${tempDir.path}/$fileName');
            await file.writeAsBytes(imageBytes);

            // Share the image as well
            await Share.shareXFiles(
              [XFile(file.path)],
              text: 'Invoice attachment for ${customer.name}',
            );

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Invoice sent to ${customer.name} via WhatsApp!'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Invoice shared via WhatsApp! (No phone number found for direct messaging)'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Failed to send via WhatsApp. Please check customer phone number.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog if open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing invoice: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('Error sharing to WhatsApp: $e');
    }
  }

  Future<void> _shareAsImage(Company company) async {
    if (widget.invoiceId == null) return;

    try {
      // Get the invoice data
      final invoiceData = await _getInvoiceDataForShare(company);
      if (invoiceData == null) return;

      // Call image share method directly
      await InvoiceGenerator.shareAsImage(
        company: invoiceData['company'],
        party: invoiceData['customer'],
        invoice: invoiceData['invoice'],
        transaction: invoiceData['transaction'],
        lineItems: invoiceData['lineItems'],
        paymentLines: invoiceData['paymentDetails'],
        customerBalance: invoiceData['customerBalance'],
        openingBalance: invoiceData['openingBalance'],
      );
    } catch (e) {
      print('Error sharing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _getInvoiceDataForShare(Company company) async {
    // Get the invoice using the service
    final isarService = ref.read(isarServiceProvider);
    final isar = isarService.isar;
    final invoiceService = SalesInvoiceService(isar);
    final salesDao = SalesDao(isar);

    // Fetch the invoice
    final invoice = await invoiceService.getSaleInvoiceById(widget.invoiceId!);
    if (invoice == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }

    // Get the customer
    final customer = await isar.partys.get(invoice.partyId);
    if (customer == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }

    // Get transaction
    final transaction = await isar.transactions.get(invoice.transactionId);
    if (transaction == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }

    // Get transaction lines
    final transactionLines = await salesDao.getTransactionLines(transaction.id);

    // Prepare line items with product names
    final lineItems = <Map<String, dynamic>>[];
    for (final txLine in transactionLines) {
      if (txLine.productId != null) {
        final product = await isar.products.get(txLine.productId!);
        lineItems.add({
          'productName': product?.name ?? 'Unknown',
          'qty': txLine.quantity,
          'rate': txLine.unitPrice,
        });
      }
    }

    // Get payment details - retrieve actual payment information
    List<Map<String, dynamic>>? paymentDetails = [];

    print('=== PAYMENT DATA DEBUG in _getInvoiceDataForShare ===');
    print('widget.invoiceId: ${widget.invoiceId}');
    print('_paidAmount: $_paidAmount');
    print('_paymentLines.length: ${_paymentLines.length}');

    // Get payment lines from database if invoice exists
    if (widget.invoiceId != null) {
      try {
        await _loadPaymentLines(company.id, widget.invoiceId!);
        print('After loading payment lines: ${_paymentLines.length}');
        // Convert payment lines to the format expected by the generator
        for (final paymentLine in _paymentLines) {
          if (paymentLine.amount > 0) {
            print(
                'Adding payment line: ${paymentLine.accountName} - ${paymentLine.amount}');
            paymentDetails.add({
              'accountName': paymentLine.accountName ?? 'Cash',
              'amount': paymentLine.amount,
            });
          }
        }
      } catch (e) {
        print('Error loading payment lines: $e');
      }
    }

    // ALWAYS include the current paid amount if it's greater than 0
    // This ensures the user's current input is reflected in the shared invoice
    if (_paidAmount > 0) {
      print('Adding current paid amount: $_paidAmount');

      // Check if we already have a cash payment and update it, or add new one
      bool foundCashPayment = false;
      for (int i = 0; i < paymentDetails.length; i++) {
        final payment = paymentDetails[i];
        if (payment['accountName'] == 'Cash') {
          // Update existing cash payment with current paid amount
          paymentDetails[i]['amount'] = _paidAmount;
          foundCashPayment = true;
          print('Updated existing cash payment to: $_paidAmount');
          break;
        }
      }

      // If no cash payment found, add one
      if (!foundCashPayment) {
        paymentDetails.add({
          'accountName': 'Cash',
          'amount': _paidAmount,
        });
        print('Added new cash payment: $_paidAmount');
      }
    }

    print('Final payment details: $paymentDetails');
    print('================================================');

    // Set to null if no payments
    if (paymentDetails.isEmpty) {
      paymentDetails = null;
    }

    // Calculate customer current balance
    final customerBalance = await _calculateCustomerBalance(customer.id);

    // Use the live AR balance as opening balance (same source as party list)
    final openingBalance = await _getCustomerBalance(customer.id);

    return {
      'company': company,
      'invoice': invoice,
      'customer': customer,
      'transaction': transaction,
      'lineItems': lineItems,
      'paymentDetails': paymentDetails,
      'customerBalance': customerBalance,
      'openingBalance': openingBalance,
    };
  }

  Future<void> _shareExistingInvoice(Company company) async {
    if (widget.invoiceId == null) return;

    try {
      // Get the invoice using the service
      final isarService = ref.read(isarServiceProvider);
      final isar = isarService.isar;
      final invoiceService = SalesInvoiceService(isar);
      final salesDao = SalesDao(isar);

      // Fetch the invoice
      final invoice =
          await invoiceService.getSaleInvoiceById(widget.invoiceId!);
      if (invoice == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invoice not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get the customer
      final customer = await isar.partys.get(invoice.partyId);
      if (customer == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Customer not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get transaction
      final transaction = await isar.transactions.get(invoice.transactionId);
      if (transaction == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get transaction lines
      final transactionLines =
          await salesDao.getTransactionLines(transaction.id);

      // Prepare line items with product names
      final lineItems = <Map<String, dynamic>>[];
      for (final txLine in transactionLines) {
        if (txLine.productId != null) {
          final product = await isar.products.get(txLine.productId!);
          lineItems.add({
            'productName': product?.name ?? 'Unknown',
            'qty': txLine.quantity,
            'rate': txLine.unitPrice,
          });
        }
      }

      // Get payment details - retrieve actual payment information
      List<Map<String, dynamic>>? paymentDetails = [];

      print('=== PAYMENT DATA DEBUG in _shareExistingInvoice ===');
      print('invoice.id: ${invoice.id}');
      print('_paidAmount: $_paidAmount');
      print('_paymentLines.length: ${_paymentLines.length}');

      // Get payment lines from database
      try {
        await _loadPaymentLines(company.id, invoice.id);
        print('After loading payment lines: ${_paymentLines.length}');
        // Convert payment lines to the format expected by the generator
        for (final paymentLine in _paymentLines) {
          if (paymentLine.amount > 0) {
            print(
                'Adding payment line: ${paymentLine.accountName} - ${paymentLine.amount}');
            paymentDetails.add({
              'accountName': paymentLine.accountName ?? 'Cash',
              'amount': paymentLine.amount,
            });
          }
        }
      } catch (e) {
        print('Error loading payment lines: $e');
      }

      // ALWAYS include the current paid amount if it's greater than 0
      // This ensures the user's current input is reflected in the shared invoice
      if (_paidAmount > 0) {
        print('Adding current paid amount: $_paidAmount');

        // Check if we already have a cash payment and update it, or add new one
        bool foundCashPayment = false;
        for (int i = 0; i < paymentDetails.length; i++) {
          final payment = paymentDetails[i];
          if (payment['accountName'] == 'Cash') {
            // Update existing cash payment with current paid amount
            paymentDetails[i]['amount'] = _paidAmount;
            foundCashPayment = true;
            print('Updated existing cash payment to: $_paidAmount');
            break;
          }
        }

        // If no cash payment found, add one
        if (!foundCashPayment) {
          paymentDetails.add({
            'accountName': 'Cash',
            'amount': _paidAmount,
          });
          print('Added new cash payment: $_paidAmount');
        }
      }

      print('Final payment details: $paymentDetails');
      print('================================================');

      // Set to null if no payments
      if (paymentDetails.isEmpty) {
        paymentDetails = null;
      }

      // Calculate customer current balance (this would typically come from a service)
      final customerBalance = await _calculateCustomerBalance(customer.id);

      // Use the live AR balance as opening balance (same source as party list)
      final openingBalance = await _getCustomerBalance(customer.id);

      // Call invoice generator with opening balance
      await InvoiceGenerator.shareInvoice(
        context: context,
        company: company,
        party: customer,
        invoice: invoice,
        transaction: transaction,
        lineItems: lineItems,
        paymentLines: paymentDetails,
        customerBalance: customerBalance,
        openingBalance: openingBalance,
      );
    } catch (e) {
      print('Error sharing invoice: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing invoice: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<double?> _calculateCustomerBalance(int customerId) async {
    try {
      // This is a simplified calculation - in a real app you'd want to
      // calculate the actual balance from all transactions
      final isarService = ref.read(isarServiceProvider);
      final isar = isarService.isar;
      final salesDao = ref.read(salesDaoProvider);

      // Get all transactions for this customer
      final allTransactions =
          await isar.transactions.filter().partyIdEqualTo(customerId).findAll();

      double totalReceivables = 0;
      double totalPayments = 0;

      for (final transaction in allTransactions) {
        if (transaction.type == TransactionType.sale) {
          // Calculate total from transaction lines
          final lines = await salesDao.getTransactionLines(transaction.id);
          final amount = lines.fold<double>(
              0, (sum, line) => sum + (line.quantity * line.unitPrice));
          totalReceivables += amount;
        } else if (transaction.type == TransactionType.payment) {
          // For payment transactions, sum the debit amounts
          final accountTransactions = await isar.accountTransactions
              .filter()
              .referenceIdEqualTo(transaction.id)
              .findAll();
          final amount =
              accountTransactions.fold<double>(0, (sum, at) => sum + at.debit);
          totalPayments += amount;
        }
      }

      return totalReceivables - totalPayments;
    } catch (e) {
      print('Error calculating customer balance: $e');
      return null;
    }
  }

  Future<void> _saveAndShareInvoice(
    SalesDao salesDao,
    Company company,
    User? user,
  ) async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a customer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final validLines = _lines
        .where((l) => l.productId != null && l.qty > 0 && l.rate > 0)
        .toList();

    if (validLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one item'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final inputs = validLines
        .map((l) => SaleLineInput(
              productId: l.productId!,
              qty: l.qty,
              rate: l.rate,
            ))
        .toList();

    // Build payment input directly from _paidAmount + the first payment line's accountId.
    // _updatePaidAmount() keeps _paymentLines[0].amount in sync, so _paidAmount is the
    // single source of truth; no shallow-copy mutation needed.
    List<PaymentLineInput>? paymentInputs;
    if (_paidAmount > 0) {
      // Guard: amount entered but no payment account available → show error, abort
      if (_paymentLines.isEmpty || _paymentLines[0].accountId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No payment account found. '
                'Please set up a Cash/Bank account under Settings before recording a payment.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      paymentInputs = [
        PaymentLineInput(
          paymentAccountId: _paymentLines[0].accountId!,
          amount: _paidAmount,
        ),
      ];
    }

    try {
      String refNo = _refNoCtrl.text.trim();

      if (widget.invoiceId != null) {
        await salesDao.updateSaleInvoice(
          invoiceId: widget.invoiceId!,
          companyId: company.id,
          customer: _selectedCustomer!,
          date: _date,
          referenceNo: refNo,
          lines: inputs,
          paymentLines: paymentInputs,
          userId: user?.id,
        );
      } else {
        await salesDao.createSaleInvoice(
          companyId: company.id,
          customer: _selectedCustomer!,
          date: _date,
          referenceNo: refNo,
          lines: inputs,
          paymentLines: paymentInputs,
          userId: user?.id,
        );
      }

      if (mounted) {
        // Get the saved invoice using the service
        final isarService = ref.read(isarServiceProvider);
        final isar = isarService.isar;
        final invoiceService = SalesInvoiceService(isar);

        // Fetch invoice by ID or by finding the most recent for this customer/date
        Invoice? invoice;
        if (widget.invoiceId != null) {
          invoice = await invoiceService.getSaleInvoiceById(widget.invoiceId!);
        } else {
          // For newly created invoice, find by date and customer
          final allInvoices =
              await invoiceService.getAllSaleInvoices(company.id);
          invoice = allInvoices
              .where((i) =>
                  i.invoiceDate.day == _date.day &&
                  i.invoiceDate.month == _date.month &&
                  i.invoiceDate.year == _date.year &&
                  i.partyId == _selectedCustomer!.id)
              .lastOrNull;
        }

        if (invoice != null) {
          // Get transaction - need to access isar directly
          final transaction =
              await isar.transactions.get(invoice.transactionId);

          if (transaction != null) {
            // Get transaction lines using salesDao
            final transactionLines =
                await salesDao.getTransactionLines(transaction.id);

            // Prepare line items with product names
            final lineItems = <Map<String, dynamic>>[];
            for (final txLine in transactionLines) {
              if (txLine.productId != null) {
                final product = await isar.products.get(txLine.productId!);
                lineItems.add({
                  'productName': product?.name ?? 'Unknown',
                  'qty': txLine.quantity,
                  'rate': txLine.unitPrice,
                });
              }
            }

            // Debug: Check if lineItems is empty
            if (lineItems.isEmpty) {
              print('Warning: No line items found for invoice ${invoice.id}');
              print('Transaction lines count: ${transactionLines.length}');
            } else {
              print('Found ${lineItems.length} line items');
            }

            // Prepare payment details if any
            // Use _paymentLines directly (amount is kept in sync by _updatePaidAmount)
            final activePaymentLines = _paymentLines
                .where((p) => p.accountId != null && p.amount > 0)
                .toList();
            List<Map<String, dynamic>>? paymentDetails;
            if (activePaymentLines.isNotEmpty) {
              paymentDetails = [];
              for (final payLine in activePaymentLines) {
                final account = await isar.accounts.get(payLine.accountId!);
                paymentDetails.add({
                  'accountName':
                      account?.name ?? payLine.accountName ?? 'Unknown',
                  'amount': payLine.amount,
                });
              }
            } else if (_paidAmount > 0) {
              // If no specific payment lines but there's a paid amount, add as cash payment
              paymentDetails = [
                {
                  'accountName': 'Cash',
                  'amount': _paidAmount,
                }
              ];
            }

            // Calculate customer current balance
            final customerBalance =
                await _calculateCustomerBalance(_selectedCustomer!.id);

            // Use the live AR balance as opening balance (same source as party list)
            final openingBalance =
                await _getCustomerBalance(_selectedCustomer!.id);

            // Call invoice generator with customer balance and opening balance
            await InvoiceGenerator.shareInvoice(
              context: context,
              company: company,
              party: _selectedCustomer!,
              invoice: invoice,
              transaction: transaction,
              lineItems: lineItems,
              paymentLines: paymentDetails,
              customerBalance: customerBalance,
              openingBalance: openingBalance,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  /// Navigate to add new party screen
  Future<void> _addNewParty() async {
    final result = await Navigator.of(context).push<Party>(
      MaterialPageRoute(
        builder: (context) => const PartyFormScreen(),
      ),
    );

    if (result != null) {
      // Invalidate the parties list so it reloads on next read
      ref.invalidate(partyListProvider);

      // Select the newly added party
      setState(() {
        _selectedCustomer = result;
        _customerSearchCtrl.text = result.name;
        _customerSearchFocus.unfocus();
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Customer "${result.name}" added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Navigate to add new party with pre-filled name
  Future<void> _addNewPartyWithName(String name) async {
    // Create a new Party instance with the searched name
    final newParty = Party()
      ..name = name
      ..partyType = PartyType.customer
      ..openingBalance = 0
      ..creditLimit = 0
      ..paymentTermsDays = 0
      ..isActive = true;

    final result = await Navigator.of(context).push<Party>(
      MaterialPageRoute(
        builder: (context) => PartyFormScreen(party: newParty),
      ),
    );

    if (result != null) {
      // Invalidate the parties list so it reloads on next read
      ref.invalidate(partyListProvider);

      // Select the newly added party
      setState(() {
        _selectedCustomer = result;
        _customerSearchCtrl.text = result.name;
        _customerSearchFocus.unfocus();
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Customer "${result.name}" added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildSummaryRow(
    String label,
    double amount, {
    required Color color,
    required bool isTablet,
    bool isBold = false,
    double? fontSize,
    Color? backgroundColor,
  }) {
    return Container(
      padding: backgroundColor != null
          ? EdgeInsets.symmetric(
              vertical: isTablet ? 8 : 6, horizontal: isTablet ? 12 : 8)
          : EdgeInsets.zero,
      decoration: backgroundColor != null
          ? BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize ?? (isTablet ? 14 : 12),
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
          Text(
            'Rs ${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: fontSize ?? (isTablet ? 14 : 12),
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
