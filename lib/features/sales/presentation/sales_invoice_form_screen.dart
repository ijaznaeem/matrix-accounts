// ignore_for_file: unused_local_variable, avoid_print, unused_element, use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:matrix_accounts/data/models/transaction_model.dart';
import 'package:matrix_accounts/features/parties/logic/party_provider.dart';

import '../../../core/config/providers.dart';
import '../../../core/database/dao/sales_dao.dart';
import '../../../data/models/account_models.dart' as account_models;
import '../../../data/models/company_model.dart';
import '../../../data/models/inventory_models.dart';
import '../../../data/models/invoice_stock_models.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/payment_models.dart';
import '../../../data/models/user_model.dart';
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
  final _itemSearchFocus = FocusNode();
  final List<SaleLineDraft> _lines = [];
  final List<PaymentLineDraft> _paymentLines = []; // NEW: payment lines
  String _discountType = 'Flat';
  double _discountValue = 0;
  double _vat = 0;
  double _shippingCharge = 0;
  double _paidAmount = 0;
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

        // Load payment lines from account transactions
        _paymentLines.clear();
        _loadPaymentLines(invoice.companyId, invoice.id);

        _isLoading = false;
      });
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

      double totalPaidAmount = 0; // Track total paid amount

      for (final payment in payments) {
        // Get the account to check if it's a cash/bank account (not AR)
        final account = await isar.accounts.get(payment.accountId);
        if (account != null &&
            (account.code == '1000' || account.code == '1100')) {
          // This is a cash/bank payment, determine the account type
          PaymentAccountType accountType;
          if (account.code == '1000') {
            accountType = PaymentAccountType.cash;
          } else {
            accountType = PaymentAccountType.bank;
          }

          // Find a matching payment account or use first of same type
          final matchingAccounts = paymentAccounts
              .where((pa) => pa.accountType == accountType)
              .toList();
          if (matchingAccounts.isNotEmpty && mounted) {
            final paymentAccount = matchingAccounts.first;
            final paidAmount = payment.debit; // Debit represents cash received

            setState(() {
              _paymentLines.add(PaymentLineDraft(
                accountId: paymentAccount.id,
                accountName: paymentAccount.accountName,
                accountIcon: paymentAccount.icon,
                amount: paidAmount,
              ));
              totalPaidAmount += paidAmount; // Add to total
            });
          }
        }
      }

      // Set the total paid amount
      if (mounted) {
        setState(() {
          _paidAmount = totalPaidAmount;
        });
      }

      // If no payment lines were loaded, add a default cash line
      if (mounted && _paymentLines.isEmpty) {
        final cashAccount = paymentAccounts
            .where((a) => a.accountType == PaymentAccountType.cash)
            .firstOrNull;

        if (cashAccount != null) {
          setState(() {
            _paymentLines.add(PaymentLineDraft(
              accountId: cashAccount.id,
              accountName: cashAccount.accountName,
              accountIcon: cashAccount.icon,
              amount: 0,
            ));
            _paidAmount = 0; // Initialize paid amount
          });
        }
      }
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
    super.dispose();
  }

  double get _subTotal =>
      _lines.fold<double>(0, (sum, l) => sum + (l.qty * l.rate));

  double get _totalDiscount {
    if (_discountType == 'Flat') return _discountValue;
    return _subTotal * (_discountValue / 100);
  }

  double get _afterDiscount => _subTotal - _totalDiscount;

  double get _totalVAT => _afterDiscount * (_vat / 100);

  double get _grandTotal => _afterDiscount + _totalVAT + _shippingCharge;

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
              Padding(
                padding: EdgeInsets.only(right: isTablet ? 32 : 16),
                child: Center(
                  child: Text(
                    company.name,
                    style: TextStyle(
                      fontSize: isTablet ? 16 : 12,
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
                  SizedBox(height: isTablet ? 32 : 20),
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
                  SizedBox(height: isTablet ? 32 : 20),
                  // Cash Amount to be Paid
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    padding: EdgeInsets.all(isTablet ? 20 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cash Amount to be Paid',
                          style: TextStyle(
                            fontSize: isTablet ? 16 : 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        SizedBox(height: isTablet ? 16 : 12),
                        TextField(
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: TextStyle(fontSize: isTablet ? 18 : 16),
                          decoration: InputDecoration(
                            hintText: 'Enter cash amount',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: isTablet ? 16 : 14,
                            ),
                            prefixText: 'RS ',
                            prefixStyle: TextStyle(
                              fontSize: isTablet ? 18 : 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color: Colors.grey.shade600, width: 2),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 16 : 12,
                              vertical: isTablet ? 14 : 12,
                            ),
                            suffixIcon: Icon(
                              Icons.currency_rupee,
                              color: Colors.grey.shade600,
                              size: isTablet ? 24 : 20,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _paidAmount = double.tryParse(value) ?? 0;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isTablet ? 20 : 16),
                  // Summary Card - Total and Balance
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    padding: EdgeInsets.all(isTablet ? 20 : 16),
                    child: Column(
                      children: [
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
                        // Paid Amount Row
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
                        // Balance Due Row
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
                    ),
                  ),
                  SizedBox(height: isTablet ? 32 : 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                                vertical: buttonHeight / 3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            side: BorderSide(color: Colors.red.shade600),
                          ),
                          onPressed: () {
                            Navigator.of(context).maybePop();
                          },
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.red.shade600,
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isTablet ? 20 : 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            padding: EdgeInsets.symmetric(
                                vertical: buttonHeight / 3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () =>
                              _saveSalesInvoice(salesDao, company, user),
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
                  SizedBox(height: isTablet ? 20 : 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await _saveAndShareInvoice(salesDao, company, user);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding:
                            EdgeInsets.symmetric(vertical: buttonHeight / 3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.share, color: Colors.white),
                      label: Text(
                        'Save & Share',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isTablet ? 32 : 20),
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

    // Prepare payment lines - combine manual payments with paid amount
    final allPaymentLines = <PaymentLineDraft>[..._paymentLines];

    // If user entered a paid amount, update the first payment line (usually cash)
    if (_paidAmount > 0 && allPaymentLines.isNotEmpty) {
      allPaymentLines[0].amount = _paidAmount;
    }

    final validPaymentLines = allPaymentLines
        .where((p) => p.accountId != null && p.amount > 0)
        .toList();

    final paymentInputs = validPaymentLines.isNotEmpty
        ? validPaymentLines
            .map((p) => PaymentLineInput(
                  paymentAccountId: p.accountId!,
                  amount: p.amount,
                ))
            .toList()
        : null;

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
        Navigator.pop(context, true); // Return true to signal refresh
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
        Navigator.pop(context, true); // Return true to signal refresh
      }
    }
  }

  Widget _buildCustomerSelector(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final partyAsync = ref.watch(partyListProvider);

    return partyAsync.when(
      data: (parties) {
        final customers =
            parties.where((p) => p.partyType != PartyType.supplier).toList();
        final searchQuery = _customerSearchCtrl.text.toLowerCase();
        final filtered = customers
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
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _selectedCustomer != null
                            ? const Color(0xFFFF8C42)
                            : Colors.grey.shade300,
                      ),
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
                        hintText:
                            _selectedCustomer?.name ?? 'Search Customer...',
                        hintStyle: TextStyle(
                          color: _selectedCustomer?.name != null
                              ? Colors.grey.shade900
                              : Colors.grey.shade500,
                          fontSize: isTablet ? 15 : 13,
                        ),
                        prefixIcon: Icon(
                          Icons.person,
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
                // Customer Balance Display (right side)
                if (_selectedCustomer != null) ...[
                  SizedBox(width: isTablet ? 12 : 8),
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _selectedCustomer!.openingBalance >= 0
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedCustomer!.openingBalance >= 0
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                        ),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 12 : 8,
                        vertical: isTablet ? 12 : 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selectedCustomer!.openingBalance >= 0
                                ? Icons.account_balance_wallet
                                : Icons.warning,
                            size: isTablet ? 18 : 16,
                            color: _selectedCustomer!.openingBalance >= 0
                                ? Colors.green.shade600
                                : Colors.red.shade600,
                          ),
                          SizedBox(width: isTablet ? 8 : 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Customer Balance',
                                  style: TextStyle(
                                    fontSize: isTablet ? 10 : 9,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _selectedCustomer!.openingBalance >= 0
                                      ? 'Credit: Rs ${_selectedCustomer!.openingBalance.toStringAsFixed(2)}'
                                      : 'Due: Rs ${_selectedCustomer!.openingBalance.abs().toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: isTablet ? 14 : 12,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        _selectedCustomer!.openingBalance >= 0
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            // Dropdown suggestions - show all customers when focused or when searching
            if (_customerSearchFocus.hasFocus || searchQuery.isNotEmpty)
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
                  maxHeight: searchQuery.isEmpty
                      ? (customers.length * (isTablet ? 65.0 : 55.0)) +
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
                                ? 'Add "$searchQuery" as new customer'
                                : 'Add New Customer',
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
                            ? customers.length
                            : filtered.length,
                        itemBuilder: (context, index) {
                          final party = searchQuery.isEmpty
                              ? customers[index]
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
                            subtitle: Text(
                              party.openingBalance >= 0
                                  ? 'Credit: Rs ${party.openingBalance.toStringAsFixed(2)}'
                                  : 'Due: Rs ${party.openingBalance.abs().toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: isTablet ? 11 : 10,
                                color: party.openingBalance >= 0
                                    ? Colors.green.shade600
                                    : Colors.red.shade600,
                              ),
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              size: isTablet ? 14 : 12,
                              color: Colors.grey.shade400,
                            ),
                            onTap: () {
                              setState(() {
                                _selectedCustomer = party;
                                _customerSearchCtrl.text = party.name;
                                _customerSearchFocus.unfocus();
                              });
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
    final amount = (line.qty * line.rate).toStringAsFixed(0);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
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
                  '${line.qty.toStringAsFixed(0)} X ${line.rate.toStringAsFixed(0)} = $amount',
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
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              style: TextStyle(fontSize: isTablet ? 14 : 12),
              initialValue: line.qty > 0 ? line.qty.toStringAsFixed(0) : '',
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
                  }
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          // Delete Button
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.close, size: 16),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: isTablet ? 32 : 28,
                minHeight: isTablet ? 32 : 28,
              ),
              color: Colors.red.shade700,
              onPressed: () {
                setState(() => _lines.removeAt(index));
              },
            ),
          ),
          const SizedBox(width: 8),
          // Rate Field
          SizedBox(
            width: isTablet ? 100 : 80,
            height: isTablet ? 40 : 35,
            child: TextFormField(
              initialValue: line.rate > 0 ? line.rate.toStringAsFixed(2) : '',
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
        // Enhanced dropdown suggestions - show all items when focused or filtered results
        if (_showAllItems || searchQuery.isNotEmpty)
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
                                  color: isAlreadyAdded
                                      ? Colors.grey.shade300
                                      : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  isAlreadyAdded ? Icons.check : Icons.add,
                                  size: isTablet ? 20 : 16,
                                  color: isAlreadyAdded
                                      ? Colors.grey.shade600
                                      : Colors.red.shade600,
                                ),
                              ),
                              title: Text(
                                product.name,
                                style: TextStyle(
                                  fontSize: isTablet ? 14 : 12,
                                  fontWeight: FontWeight.w500,
                                  color: isAlreadyAdded
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade900,
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
                                  Text(
                                    'Rate: RS ${product.salePrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: isTablet ? 11 : 10,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: isAlreadyAdded
                                  ? null
                                  : () {
                                      setState(() {
                                        _lines.add(SaleLineDraft(
                                          productId: product.id,
                                          productName: product.name,
                                          qty: 1,
                                          rate: product.salePrice,
                                        ));
                                        _itemSearchCtrl.clear();
                                      });

                                      // Show success feedback
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              '${product.name} added to invoice'),
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
              Text(_totalDiscount.toStringAsFixed(0)),
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
              Text(_totalVAT.toStringAsFixed(0)),
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
              Text(_shippingCharge.toStringAsFixed(0)),
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
      {bool isBold = false, bool isTablet = false}) {
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
          value.toStringAsFixed(0),
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
                                child: Text(line.qty.toStringAsFixed(0),
                                    style: TextStyle(
                                        fontSize: isTablet ? 13 : 11,
                                        color: Colors.grey.shade700),
                                    textAlign: TextAlign.center)),
                            Expanded(
                                child: Text(line.rate.toStringAsFixed(0),
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

    // Prepare payment lines - combine manual payments with paid amount
    final allPaymentLines = <PaymentLineDraft>[..._paymentLines];

    // If user entered a paid amount, update the first payment line (usually cash)
    if (_paidAmount > 0 && allPaymentLines.isNotEmpty) {
      allPaymentLines[0].amount = _paidAmount;
    }

    final validPaymentLines = allPaymentLines
        .where((p) => p.accountId != null && p.amount > 0)
        .toList();

    final paymentInputs = validPaymentLines.isNotEmpty
        ? validPaymentLines
            .map((p) => PaymentLineInput(
                  paymentAccountId: p.accountId!,
                  amount: p.amount,
                ))
            .toList()
        : null;

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
            List<Map<String, dynamic>>? paymentDetails;
            if (validPaymentLines.isNotEmpty) {
              paymentDetails = [];
              for (final payLine in validPaymentLines) {
                if (payLine.accountId != null) {
                  final account = await isar.accounts.get(payLine.accountId!);
                  paymentDetails.add({
                    'accountName':
                        account?.name ?? payLine.accountName ?? 'Unknown',
                    'amount': payLine.amount,
                  });
                }
              }
            }

            // Call invoice generator
            await InvoiceGenerator.shareInvoice(
              context: context,
              company: company,
              party: _selectedCustomer!,
              invoice: invoice,
              transaction: transaction,
              lineItems: lineItems,
              paymentLines: paymentDetails,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
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
      // Refresh the parties list
      ref.refresh(partyListProvider);

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
      ..customerClass = CustomerClass.retailer
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
      // Refresh the parties list
      ref.refresh(partyListProvider);

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
}
