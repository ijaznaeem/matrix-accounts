// ignore_for_file: avoid_print, avoid_unnecessary_containers, use_build_context_synchronously, unused_element, deprecated_member_use, avoid_init_to_null

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_table_plus/flutter_table_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/providers.dart';
import '../../../core/database/dao/party_dao.dart';
import '../../../core/database/dao/purchase_dao.dart';
import '../../../core/database/dao/sales_dao.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/whatsapp_service.dart';
import '../../../data/models/account_models.dart' as account_models;
import '../../../data/models/company_model.dart';
import '../../../data/models/inventory_models.dart';
import '../../../data/models/invoice_stock_models.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/payment_models.dart';
import '../../../data/models/transaction_model.dart';
import '../../../data/models/user_model.dart';
import '../../../presentation/widgets/searchable_list.dart';
import '../../parties/logic/party_provider.dart' show partyListProvider;
import '../../parties/presentation/party_form_screen.dart';
import '../../payments/logic/payment_providers.dart';
import '../../sales/logic/sales_providers.dart';
import '../logic/purchase_providers.dart';
import '../services/purchase_invoice_generator.dart';

class PurchaseLineDraft {
  int? productId;
  String? productName;
  double qty;
  double rate;

  PurchaseLineDraft({
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

class PurchaseInvoiceFormScreen extends ConsumerStatefulWidget {
  final int? invoiceId;

  const PurchaseInvoiceFormScreen({super.key, this.invoiceId});

  @override
  ConsumerState<PurchaseInvoiceFormScreen> createState() {
    return _PurchaseInvoiceFormScreenState();
  }
}

class _PurchaseInvoiceFormScreenState
    extends ConsumerState<PurchaseInvoiceFormScreen> {
  Party? _selectedSupplier;
  DateTime _date = DateTime.now();
  final _refNoCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _supplierSearchCtrl = TextEditingController();
  final _supplierSearchFocus = FocusNode();
  String? _attachmentPath;
  final _itemSearchCtrl = TextEditingController();
  final _cashAmountCtrl = TextEditingController();
  final _itemSearchFocus = FocusNode();
  final List<PurchaseLineDraft> _lines = [];
  final List<PaymentLineDraft> _paymentLines = [];
  final Map<int, TextEditingController> _qtyControllers = {};
  final Map<int, TextEditingController> _rateControllers = {};
  final String _discountType = 'Flat';
  final double _discountValue = 0;
  final double _vat = 0;
  final double _shippingCharge = 0;
  double _paidAmount = 0;
  double _previousBalance = 0;
  double _totalPayableAmount = 0;
  double _remainingBalance = 0;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showAllItems = false;

  String get _currencySymbol {
    final settings = ref.read(settingsProvider);
    return SettingsConstants.currencySymbols[settings.defaultCurrency] ??
        settings.defaultCurrency;
  }

  @override
  void initState() {
    super.initState();
    _supplierSearchFocus.addListener(() {
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
      _initializeNextReferenceNo();
      _addDefaultCashPayment().then((_) {
        if (mounted) {
          setState(() => _isLoading = false);
          _calculateTotalPayable(); // Initialize calculations
        }
      });
    }
  }

  Future<void> _initializeNextReferenceNo() async {
    final company = ref.read(currentCompanyProvider);
    if (company == null) {
      _refNoCtrl.text = 'PUR-${DateTime.now().millisecondsSinceEpoch}';
      return;
    }

    final prefix = 'PUR-${company.id}-';
    final isar = ref.read(isarServiceProvider).isar;
    final purchaseTransactions = await isar.transactions
        .filter()
        .companyIdEqualTo(company.id)
        .typeEqualTo(TransactionType.purchase)
        .findAll();

    var maxSerial = 0;
    for (final transaction in purchaseTransactions) {
      final reference = transaction.referenceNo.trim();
      if (!reference.startsWith(prefix)) continue;
      final suffix = reference.substring(prefix.length);
      final serial = int.tryParse(suffix);
      if (serial != null && serial > maxSerial) {
        maxSerial = serial;
      }
    }

    _refNoCtrl.text = '$prefix${(maxSerial + 1).toString().padLeft(5, '0')}';
  }

  /// Get current supplier balance from accounting ledger
  Future<double> _getSupplierBalance(int supplierId) async {
    final company = ref.read(currentCompanyProvider);
    if (company == null) return 0.0;

    final isarService = ref.read(isarServiceProvider);
    final partyDao = PartyDao(isarService.isar);

    try {
      return await partyDao.getPartyBalance(
        partyId: supplierId,
        companyId: company.id,
      );
    } catch (e) {
      print('Error getting supplier balance: $e');
      return 0.0;
    }
  }

  /// Get previous unpaid balance for a supplier including opening balance
  Future<double> _getPreviousUnpaidBalance(int supplierId) async {
    final company = ref.read(currentCompanyProvider);
    if (company == null) return 0.0;

    final isarService = ref.read(isarServiceProvider);
    final isar = isarService.isar;

    try {
      // Get supplier to access opening balance
      final supplier = await isar.partys.get(supplierId);
      double balance = supplier?.openingBalance ?? 0.0;

      // Get all account transactions for this supplier
      final allAccountTransactions =
          await isar.accountTransactions.where().findAll();
      final supplierTransactions = allAccountTransactions
          .where((t) =>
              t.companyId == company.id &&
              t.partyId == supplierId &&
              (t.transactionType ==
                      account_models.TransactionType.purchaseInvoice ||
                  t.transactionType ==
                      account_models.TransactionType.paymentOut ||
                  t.transactionType ==
                      account_models.TransactionType.paymentIn))
          .toList();

      // Calculate balance: credit (amount owed to supplier) - debit (amount paid to supplier)
      for (final transaction in supplierTransactions) {
        balance += transaction.credit - transaction.debit;
      }

      return balance > 0 ? balance : 0.0; // Only return positive unpaid balance
    } catch (e) {
      print('Error getting previous unpaid balance: $e');
      return 0.0;
    }
  }

  /// Calculate total payable amount (previous balance + new purchase amount)
  void _calculateTotalPayable() {
    final newPurchaseAmount =
        _subTotal; // Use subtotal instead of grandTotal to avoid circular calls
    _totalPayableAmount = _previousBalance + newPurchaseAmount;
    _remainingBalance = _totalPayableAmount - _paidAmount;
    if (mounted) {
      setState(() {});
    }
  }

  /// Update supplier selection and fetch previous balance
  Future<void> _onSupplierSelected(Party supplier) async {
    setState(() {
      _selectedSupplier = supplier;
      _supplierSearchCtrl.text = supplier.name;
    });

    // Fetch previous balance using the same path as the party list
    final previousBalance = await _getSupplierBalance(supplier.id);
    setState(() {
      _previousBalance = previousBalance;
    });

    _calculateTotalPayable();
    _supplierSearchFocus.unfocus();
  }

  Future<void> _addDefaultCashPayment() async {
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
      final purchaseDao = ref.read(purchaseDaoProvider);
      final isarService = ref.read(isarServiceProvider);
      final isar = isarService.isar;

      final invoice = await purchaseDao.getInvoiceById(widget.invoiceId!);
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
          await purchaseDao.getTransactionForInvoice(widget.invoiceId!);
      if (transaction == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaction not found')),
          );
          Navigator.pop(context);
        }
        return;
      }

      final lines = await purchaseDao.getTransactionLines(transaction.id);
      final supplier = await isar.partys.get(invoice.partyId);

      // Fetch live supplier balance (same path as party list)
      final supplierBalanceOnLoad =
          supplier != null ? await _getSupplierBalance(supplier.id) : 0.0;

      setState(() {
        _selectedSupplier = supplier;
        _previousBalance = supplierBalanceOnLoad;
        _date = invoice.invoiceDate;
        _refNoCtrl.text = transaction.referenceNo;
        _lines.clear();

        for (final line in lines) {
          final productId = line.productId;
          final product =
              productId != null ? isar.products.getSync(productId) : null;
          _lines.add(PurchaseLineDraft(
            productId: line.productId,
            productName: product?.name ?? 'Unknown',
            qty: line.quantity,
            rate: line.unitPrice,
          ));
        }

        // Always ensure at least one line exists
        if (_lines.isEmpty) {
          _lines.add(PurchaseLineDraft());
        }

        _paymentLines.clear();
        _loadPaymentLines(invoice.companyId, invoice.id);

        _notesCtrl.text = invoice.notes ?? '';
        _attachmentPath = invoice.attachmentPath;

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

      // Get all payment account transactions for this invoice
      final allAccountTransactions =
          await isar.accountTransactions.where().findAll();

      final payments = allAccountTransactions
          .where((p) =>
              p.companyId == companyId &&
              p.referenceId == invoiceId &&
              (p.transactionType ==
                      account_models.TransactionType.purchaseInvoice ||
                  p.transactionType ==
                      account_models.TransactionType.paymentOut))
          .toList();

      final paymentAccounts = await paymentDao.getPaymentAccounts(companyId);

      double totalPaidAmount = 0;

      for (final payment in payments) {
        // Get the account to check if it's a cash/bank account (not AP)
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
            final paidAmount = payment.credit; // Credit represents cash paid

            setState(() {
              _paymentLines.add(PaymentLineDraft(
                accountId: paymentAccount.id,
                accountName: paymentAccount.accountName,
                accountIcon: paymentAccount.icon,
                amount: paidAmount,
              ));
              totalPaidAmount += paidAmount;
            });
          }
        }
      }

      // Set the total paid amount
      if (mounted) {
        setState(() {
          _paidAmount = totalPaidAmount;
          _cashAmountCtrl.text =
              totalPaidAmount > 0 ? totalPaidAmount.toString() : '';
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
            _paidAmount = 0;
            _cashAmountCtrl.text = ''; // Clear cash amount field
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
    _supplierSearchCtrl.dispose();
    _supplierSearchFocus.dispose();
    _itemSearchCtrl.dispose();
    _itemSearchFocus.dispose();
    for (var controller in _qtyControllers.values) {
      controller.dispose();
    }
    for (var controller in _rateControllers.values) {
      controller.dispose();
    }
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _subTotal {
    final total = _lines.fold<double>(0, (sum, l) => sum + (l.qty * l.rate));
    print('UI _subTotal calculation: $total (from ${_lines.length} lines)');
    for (int i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      print(
          '  Line $i: Qty=${line.qty}, Rate=${line.rate}, Amount=${line.qty * line.rate}');
    }
    return total;
  }

  double get _totalDiscount {
    if (_discountType == 'Flat') return _discountValue;
    return _subTotal * (_discountValue / 100);
  }

  double get _afterDiscount => _subTotal - _totalDiscount;

  double get _totalVAT => _afterDiscount * (_vat / 100);

  double get _grandTotal {
    return _afterDiscount + _totalVAT + _shippingCharge;
  }

  /// Update paid amount and recalculate remaining balance
  void _updatePaidAmount(double amount) {
    setState(() {
      _paidAmount = amount;
      _calculateTotalPayable(); // Recalculate when paid amount changes
    });
  }

  /// Trigger recalculation when line items change
  void _onLineItemChanged() {
    _calculateTotalPayable();
  }

  Future<double> _calculateCurrentStock(
      Isar isar, int companyId, int productId) async {
    final product = await isar.collection<Product>().get(productId);
    if (product == null) return 0;

    final stockMovements = await isar.stockLedgers
        .filter()
        .companyIdEqualTo(companyId)
        .productIdEqualTo(productId)
        .findAll();

    double currentStock = product.openingQty;
    for (final movement in stockMovements) {
      currentStock += movement.quantityDelta;
    }

    return currentStock;
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(currentCompanyProvider);
    final user = ref.watch(currentUserProvider);
    final productAsync = ref.watch(productListProvider);
    final purchaseDao = ref.read(purchaseDaoProvider);
    final isTablet = MediaQuery.of(context).size.width > 600;

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

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.invoiceId != null ? 'Edit Purchase' : 'Add Purchase'),
        elevation: 0,
        backgroundColor: Colors.blueAccent,
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
                _shareAsImage(purchaseDao, company, user);
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
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(isTablet ? 24 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSupplierSelector(context),
              SizedBox(height: isTablet ? 28 : 20),
              productAsync.when(
                data: (products) => Column(
                  children: [
                    _buildProductsTable(isTablet),
                    SizedBox(height: isTablet ? 16 : 12),
                    _buildProductSelectorDropdown(isTablet, products),
                  ],
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text('Error loading products')),
              ),
              SizedBox(height: isTablet ? 28 : 20),
              _buildCashPaymentSection(isTablet),
              SizedBox(height: isTablet ? 28 : 20),
              _buildCalculationCard(),
              SizedBox(height: isTablet ? 28 : 20),
              _buildNotesAndAttachmentSection(),
              SizedBox(height: isTablet ? 28 : 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () async {
                              await _savePurchaseInvoice(
                                  purchaseDao, company, user);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isSaving ? Colors.grey : Colors.orange,
                        padding:
                            EdgeInsets.symmetric(vertical: isTablet ? 18 : 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save, color: Colors.white),
                      label: Text(
                        _isSaving ? 'Saving...' : 'Save',
                        style: TextStyle(
                          fontSize: isTablet ? 18 : 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
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
  }

  Future<void> _savePurchaseInvoice(
      PurchaseDao purchaseDao, Company company, User? user,
      {bool showActions = true}) async {
    // Prevent multiple simultaneous saves
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      if (_selectedSupplier == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a supplier'),
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
          .map((l) => PurchaseLineInput(
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
        await purchaseDao.updatePurchaseInvoice(
          invoiceId: widget.invoiceId!,
          companyId: company.id,
          supplier: _selectedSupplier!,
          date: _date,
          referenceNo: _refNoCtrl.text.trim(),
          lines: inputs,
          paymentLines: paymentInputs,
          userId: user?.id,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          attachmentPath: _attachmentPath,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Purchase updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          if (showActions) {
            await _showPostSaveActions(purchaseDao, company, user);
          }
        }
      } else {
        await purchaseDao.createPurchaseInvoice(
          companyId: company.id,
          supplier: _selectedSupplier!,
          date: _date,
          referenceNo: _refNoCtrl.text.trim(),
          lines: inputs,
          paymentLines: paymentInputs,
          userId: user?.id,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          attachmentPath: _attachmentPath,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Purchase saved successfully'),
              backgroundColor: Colors.green,
            ),
          );
          if (showActions) {
            await _showPostSaveActions(purchaseDao, company, user);
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _showPostSaveActions(
      PurchaseDao purchaseDao, Company company, User? user) async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Invoice Saved',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.chat, color: Colors.green),
                title: const Text('Send on WhatsApp'),
                onTap: () async {
                  Navigator.pop(context);
                  await _shareToWhatsApp(company);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image, color: Colors.blue),
                title: const Text('Share as Image'),
                onTap: () async {
                  Navigator.pop(context);
                  await _shareAsImage(purchaseDao, company, user);
                },
              ),
              ListTile(
                leading: const Icon(Icons.print, color: Colors.deepPurple),
                title: const Text('Print Invoice'),
                onTap: () async {
                  Navigator.pop(context);
                  await _shareAsPDF(company);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.add_circle_outline, color: Colors.orange),
                title: const Text('New Purchase'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    this.context,
                    MaterialPageRoute(
                      builder: (_) => const PurchaseInvoiceFormScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.list_alt, color: Colors.blueGrey),
                title: const Text('Back to Invoice List'),
                onTap: () {
                  Navigator.pop(context);
                  this.context.go('/purchases');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAfterShareOrPrintActions() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const Text(
                'What next?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading:
                    const Icon(Icons.add_circle_outline, color: Colors.orange),
                title: const Text('New Purchase'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    this.context,
                    MaterialPageRoute(
                      builder: (_) => const PurchaseInvoiceFormScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.list_alt, color: Colors.blueGrey),
                title: const Text('Back to Invoice List'),
                onTap: () {
                  Navigator.pop(context);
                  this.context.go('/purchases');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSupplierSelector(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final partyAsync = ref.watch(partyListProvider);

    return partyAsync.when(
      data: (parties) {
        final allSuppliers = parties.toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SearchableDropdown<Party>(
              items: allSuppliers,
              itemBuilder: (party) => ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: isTablet ? 16 : 14,
                  backgroundColor: Colors.orange.shade100,
                  child: Text(
                    party.name.isNotEmpty ? party.name[0].toUpperCase() : 'S',
                    style: TextStyle(
                      fontSize: isTablet ? 14 : 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
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
              ),
              searchMatcher: (party) => party.name,
              onSelected: _onSupplierSelected,
              hintText: _selectedSupplier?.name ?? 'Search Supplier',
              headerBuilder: _buildSupplierModalHeader,
              isSelected: _selectedSupplier != null,
              onClear: _selectedSupplier != null
                  ? () {
                      setState(() {
                        _selectedSupplier = null;
                        _supplierSearchCtrl.clear();
                        _previousBalance = 0;
                      });
                      _calculateTotalPayable();
                    }
                  : null,
              maxHeight: 300,
            ),
            if (_selectedSupplier != null) ...[
              SizedBox(height: isTablet ? 12 : 8),
              FutureBuilder<double>(
                future: _getSupplierBalance(_selectedSupplier!.id),
                builder: (context, snapshot) {
                  final liveBalance = snapshot.data ?? 0.0;
                  final isLoading =
                      snapshot.connectionState == ConnectionState.waiting;

                  return Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: liveBalance >= 0
                          ? Colors.orange.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: liveBalance >= 0
                            ? Colors.orange.shade300
                            : Colors.green.shade300,
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
                            child:
                                const CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            liveBalance >= 0
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: isTablet ? 18 : 16,
                            color: liveBalance >= 0
                                ? Colors.orange.shade700
                                : Colors.green.shade700,
                          ),
                        SizedBox(width: isTablet ? 8 : 6),
                        Expanded(
                          child: Text(
                            'Supplier Balance: $_currencySymbol ${liveBalance.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: isTablet ? 13 : 11,
                              fontWeight: FontWeight.w600,
                              color: liveBalance >= 0
                                  ? Colors.orange.shade800
                                  : Colors.green.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
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
        child: const Text('Error loading suppliers'),
      ),
    );
  }

  Widget _buildSupplierModalHeader(String searchQuery) {
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        bottom: false,
        child: ListTile(
          dense: true,
          leading: Icon(
            Icons.business_outlined,
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
    );
  }

  void _ensurePurchaseLineControllers(int index, PurchaseLineDraft line) {
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
  }

  void _removePurchaseLineAt(int index) {
    if (index < 0 || index >= _lines.length) return;

    setState(() {
      _lines.removeAt(index);

      final removedQty = _qtyControllers.remove(index);
      final removedRate = _rateControllers.remove(index);
      removedQty?.dispose();
      removedRate?.dispose();

      final shiftedQty = <int, TextEditingController>{};
      final shiftedRate = <int, TextEditingController>{};

      _qtyControllers.forEach((key, controller) {
        shiftedQty[key > index ? key - 1 : key] = controller;
      });
      _rateControllers.forEach((key, controller) {
        shiftedRate[key > index ? key - 1 : key] = controller;
      });

      _qtyControllers
        ..clear()
        ..addAll(shiftedQty);
      _rateControllers
        ..clear()
        ..addAll(shiftedRate);
    });

    _onLineItemChanged();
  }

  void _addProductToPurchase(Product product) {
    final isAlreadyAdded = _lines.any((line) => line.productId == product.id);
    setState(() {
      _lines.add(PurchaseLineDraft(
        productId: product.id,
        productName: product.name,
        qty: 1,
        rate: product.lastCost > 0 ? product.lastCost : product.salePrice,
      ));
    });
    _onLineItemChanged();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${product.name} added to purchase${isAlreadyAdded ? ' (duplicate)' : ''}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _buildProductsTable(bool isTablet) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalCellPadding = isTablet ? 6.0 : 4.0;
        final tableInnerWidth =
            (constraints.maxWidth - 8).clamp(260.0, 1800.0).toDouble();

        var actionColumnWidth = (isTablet ? 0.05 : 0.06) * tableInnerWidth;
        var qtyColumnWidth = (isTablet ? 0.12 : 0.13) * tableInnerWidth;
        var rateColumnWidth = (isTablet ? 0.15 : 0.16) * tableInnerWidth;
        var amountColumnWidth = (isTablet ? 0.19 : 0.20) * tableInnerWidth;

        final minAction = isTablet ? 28.0 : 24.0;
        final minQty = isTablet ? 52.0 : 46.0;
        final minRate = isTablet ? 64.0 : 52.0;
        final minAmount = isTablet ? 86.0 : 72.0;
        final minProduct = isTablet ? 180.0 : 110.0;

        if (actionColumnWidth < minAction) actionColumnWidth = minAction;
        if (qtyColumnWidth < minQty) qtyColumnWidth = minQty;
        if (rateColumnWidth < minRate) rateColumnWidth = minRate;
        if (amountColumnWidth < minAmount) amountColumnWidth = minAmount;

        var productColumnWidth = tableInnerWidth -
            (qtyColumnWidth +
                rateColumnWidth +
                amountColumnWidth +
                actionColumnWidth);

        if (productColumnWidth < minProduct) {
          var deficit = minProduct - productColumnWidth;

          final amountReducible = amountColumnWidth - minAmount;
          if (amountReducible > 0 && deficit > 0) {
            final cut = amountReducible < deficit ? amountReducible : deficit;
            amountColumnWidth -= cut;
            deficit -= cut;
          }

          final rateReducible = rateColumnWidth - minRate;
          if (rateReducible > 0 && deficit > 0) {
            final cut = rateReducible < deficit ? rateReducible : deficit;
            rateColumnWidth -= cut;
            deficit -= cut;
          }

          final qtyReducible = qtyColumnWidth - minQty;
          if (qtyReducible > 0 && deficit > 0) {
            final cut = qtyReducible < deficit ? qtyReducible : deficit;
            qtyColumnWidth -= cut;
            deficit -= cut;
          }

          final actionReducible = actionColumnWidth - minAction;
          if (actionReducible > 0 && deficit > 0) {
            final cut = actionReducible < deficit ? actionReducible : deficit;
            actionColumnWidth -= cut;
            deficit -= cut;
          }

          productColumnWidth = tableInnerWidth -
              (qtyColumnWidth +
                  rateColumnWidth +
                  amountColumnWidth +
                  actionColumnWidth);
        }

        final columns = TableColumnsBuilder<PurchaseLineDraft>()
          ..addColumn(
            'product',
            TablePlusColumn<PurchaseLineDraft>(
              key: 'product',
              label: 'Product',
              order: 1,
              width: productColumnWidth,
              sortable: false,
              valueAccessor: (line) => line.productName ?? 'Select product',
              statefulCellBuilder: (context, row, isSelected, isDim) {
                return Text(
                  row.productName ?? 'Select product',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isTablet ? 13 : 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade900,
                  ),
                );
              },
            ),
          )
          ..addColumn(
            'qty',
            TablePlusColumn<PurchaseLineDraft>(
              key: 'qty',
              label: 'Qty',
              order: 2,
              width: qtyColumnWidth,
              sortable: false,
              alignment: Alignment.center,
              textAlign: TextAlign.center,
              valueAccessor: (line) => line.qty,
              statefulCellBuilder: (context, row, isSelected, isDim) {
                final index = _lines.indexOf(row);
                if (index < 0) return const SizedBox.shrink();
                _ensurePurchaseLineControllers(index, row);

                return SizedBox(
                  height: isTablet ? 34 : 30,
                  child: TextFormField(
                    controller: _qtyControllers[index],
                    textAlign: TextAlign.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    style: TextStyle(fontSize: isTablet ? 12 : 11),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        final qty = double.tryParse(value);
                        if (qty != null && qty > 0 && qty != row.qty) {
                          setState(() {
                            row.qty = qty;
                          });
                          _onLineItemChanged();
                        }
                      }
                    },
                  ),
                );
              },
            ),
          )
          ..addColumn(
            'rate',
            TablePlusColumn<PurchaseLineDraft>(
              key: 'rate',
              label: 'Rate',
              order: 3,
              width: rateColumnWidth,
              sortable: false,
              alignment: Alignment.center,
              textAlign: TextAlign.center,
              valueAccessor: (line) => line.rate,
              statefulCellBuilder: (context, row, isSelected, isDim) {
                final index = _lines.indexOf(row);
                if (index < 0) return const SizedBox.shrink();
                _ensurePurchaseLineControllers(index, row);

                return SizedBox(
                  height: isTablet ? 34 : 30,
                  child: TextFormField(
                    controller: _rateControllers[index],
                    textAlign: TextAlign.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    style: TextStyle(fontSize: isTablet ? 12 : 11),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        final rate = double.tryParse(value);
                        if (rate != null && rate != row.rate) {
                          setState(() {
                            row.rate = rate;
                          });
                          _onLineItemChanged();
                        }
                      }
                    },
                  ),
                );
              },
            ),
          )
          ..addColumn(
            'amount',
            TablePlusColumn<PurchaseLineDraft>(
              key: 'amount',
              label: 'Amount ($_currencySymbol)',
              order: 4,
              width: amountColumnWidth,
              sortable: false,
              alignment: Alignment.centerRight,
              textAlign: TextAlign.right,
              valueAccessor: (line) => line.qty * line.rate,
              statefulCellBuilder: (context, row, isSelected, isDim) {
                final amount = row.qty * row.rate;
                return Text(
                  amount.toStringAsFixed(2),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: isTablet ? 12 : 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                  ),
                );
              },
            ),
          )
          ..addColumn(
            'action',
            TablePlusColumn<PurchaseLineDraft>(
              key: 'action',
              label: '',
              order: 5,
              width: actionColumnWidth,
              sortable: false,
              alignment: Alignment.center,
              textAlign: TextAlign.center,
              valueAccessor: (line) => '',
              statefulCellBuilder: (context, row, isSelected, isDim) {
                final index = _lines.indexOf(row);
                return IconButton(
                  tooltip: 'Delete product',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(
                    width: isTablet ? 26 : 22,
                    height: isTablet ? 26 : 22,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      index < 0 ? null : () => _removePurchaseLineAt(index),
                  icon: Icon(
                    Icons.delete_outline,
                    size: isTablet ? 17 : 15,
                    color: Colors.red.shade500,
                  ),
                );
              },
            ),
          );

        final headerHeight = isTablet ? 40.0 : 36.0;
        final rowHeight = isTablet ? 42.0 : 38.0;
        final footerHeight = isTablet ? 34.0 : 30.0;
        final visibleRows = _lines.isEmpty ? 1 : _lines.length;
        final totalQty = _lines.fold<double>(0, (sum, line) => sum + line.qty);
        final totalAmount =
            _lines.fold<double>(0, (sum, line) => sum + (line.qty * line.rate));

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: const EdgeInsets.all(3),
          child: SizedBox(
            height: headerHeight + (visibleRows * rowHeight) + footerHeight,
            child: Column(
              children: [
                Expanded(
                  child: FlutterTablePlus<PurchaseLineDraft>(
                    columns: columns.build(),
                    data: _lines,
                    rowId: (line) =>
                        '${line.productId ?? 'line'}-${_lines.indexOf(line)}',
                    sortColumnKey: null,
                    sortDirection: SortDirection.none,
                    onSort: null,
                    resizable: false,
                    stretchLastColumn: false,
                    theme: TablePlusTheme(
                      scrollbarTheme:
                          const TablePlusScrollbarTheme(showHorizontal: false),
                      headerTheme: TablePlusHeaderTheme(
                        height: headerHeight,
                        padding: EdgeInsets.symmetric(
                            horizontal: horizontalCellPadding),
                        textStyle: TextStyle(
                          fontSize: isTablet ? 12 : 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF212121),
                        ),
                      ),
                      bodyTheme: TablePlusBodyTheme(
                        rowHeight: rowHeight,
                        padding: EdgeInsets.symmetric(
                            horizontal: horizontalCellPadding),
                        textStyle: TextStyle(
                          fontSize: isTablet ? 12 : 11,
                          color: const Color(0xFF212121),
                        ),
                      ),
                    ),
                    noDataWidget: Center(
                      child: Text(
                        'No items added yet. Use product dropdown below to add items.',
                        style: TextStyle(
                          fontSize: isTablet ? 12 : 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  height: footerHeight,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border:
                        Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: productColumnWidth,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: horizontalCellPadding),
                          child: Text(
                            'Total',
                            style: TextStyle(
                              fontSize: isTablet ? 12 : 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: qtyColumnWidth,
                        child: Text(
                          totalQty == totalQty.roundToDouble()
                              ? totalQty.toStringAsFixed(0)
                              : totalQty.toStringAsFixed(2),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isTablet ? 12 : 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ),
                      SizedBox(width: rateColumnWidth),
                      SizedBox(
                        width: amountColumnWidth,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: horizontalCellPadding),
                          child: Text(
                            totalAmount.toStringAsFixed(2),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: isTablet ? 12 : 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: actionColumnWidth),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductSelectorDropdown(bool isTablet, List<Product> products) {
    return SearchableDropdown<Product>(
      items: products,
      hintText: 'Search & Add Items (Name, SKU)...',
      maxHeight: isTablet ? 320 : 260,
      searchMatcher: (product) => '${product.name} ${product.sku}',
      onSelected: _addProductToPurchase,
      itemBuilder: (product) {
        final isAlreadyAdded =
            _lines.any((line) => line.productId == product.id);
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: isTablet ? 16 : 14,
            backgroundColor: Colors.blue.shade50,
            child: Icon(
              isAlreadyAdded ? Icons.check : Icons.add,
              size: isTablet ? 16 : 14,
              color:
                  isAlreadyAdded ? Colors.green.shade600 : Colors.blue.shade600,
            ),
          ),
          title: Text(
            product.name,
            style: TextStyle(
              fontSize: isTablet ? 14 : 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade900,
            ),
          ),
          subtitle: FutureBuilder<double>(
            future: _calculateCurrentStock(
              ref.read(isarServiceProvider).isar,
              ref.read(currentCompanyProvider)?.id ?? 0,
              product.id,
            ),
            builder: (context, snap) {
              final stock = snap.data ?? product.openingQty;
              final stockColor = stock <= 0
                  ? Colors.red.shade600
                  : stock < 5
                      ? Colors.orange.shade700
                      : Colors.green.shade700;
              final suggestedRate =
                  product.lastCost > 0 ? product.lastCost : product.salePrice;

              return Text(
                'Stock: ${stock.toStringAsFixed(1)} • Rate: $_currencySymbol ${suggestedRate.toStringAsFixed(2)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isTablet ? 11 : 10,
                  fontWeight: FontWeight.w500,
                  color: stockColor,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCashPaymentSection(bool isTablet) {
    final fontSize = isTablet ? 18.0 : 16.0;

    return Column(
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
              Text(
                'Cash',
                style: TextStyle(
                  fontSize: isTablet ? 15 : 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: isTablet ? 190 : 150,
                child: Row(
                  children: [
                    Text(
                      _currencySymbol,
                      style: TextStyle(
                        fontSize: isTablet ? 15 : 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    SizedBox(width: isTablet ? 6 : 4),
                    Expanded(
                      child: TextField(
                        controller: _cashAmountCtrl,
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade900,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter amount',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: isTablet ? 14 : 12,
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) {
                          final cashAmount = double.tryParse(value) ?? 0;
                          _updatePaidAmount(cashAmount);
                          if (_paymentLines.isNotEmpty) {
                            _paymentLines[0].amount = cashAmount;
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLineItem(
    BuildContext context,
    PurchaseLineDraft line,
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
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: EdgeInsets.all(isTablet ? 16 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.productName ?? 'Select product',
                      style: TextStyle(
                        fontSize: isTablet ? 18 : 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: isTablet ? 6 : 4),
                    Text(
                      '${line.qty == line.qty.roundToDouble() ? line.qty.toStringAsFixed(0) : line.qty.toStringAsFixed(2)} X ${line.rate.toStringAsFixed(2)} = $amount',
                      style: TextStyle(
                        fontSize: isTablet ? 15 : 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Quantity Field
                  SizedBox(
                    width: isTablet ? 90 : 70,
                    height: isTablet ? 40 : 32,
                    child: TextField(
                      controller: _qtyControllers[index],
                      textAlign: TextAlign.center,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(fontSize: isTablet ? 16 : 14),
                      decoration: InputDecoration(
                        hintText: 'Qty',
                        border: const OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: isTablet ? 8 : 6),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          final qty = double.tryParse(value);
                          if (qty != null && qty > 0) {
                            setState(() {
                              line.qty = qty;
                            });
                            _onLineItemChanged(); // Trigger recalculation
                          }
                        }
                      },
                    ),
                  ),
                  SizedBox(width: isTablet ? 12 : 8),
                  // Rate Field
                  SizedBox(
                    width: isTablet ? 90 : 70,
                    height: isTablet ? 40 : 32,
                    child: TextField(
                      controller: _rateControllers[index],
                      textAlign: TextAlign.center,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(fontSize: isTablet ? 16 : 14),
                      decoration: InputDecoration(
                        hintText: 'Rate',
                        border: const OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: isTablet ? 8 : 6),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          final rate = double.tryParse(value);
                          if (rate != null && rate >= 0) {
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
            ],
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
                color: Colors.blue.shade600,
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
                    color: Colors.blue.shade600,
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
                            final addedCount = _lines
                                .where((line) => line.productId == product.id)
                                .length;

                            return ListTile(
                              dense: true,
                              leading: Container(
                                width: isTablet ? 40 : 32,
                                height: isTablet ? 40 : 32,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: isAlreadyAdded
                                    ? Center(
                                        child: Text(
                                          addedCount.toString(),
                                          style: TextStyle(
                                            fontSize: isTablet ? 14 : 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade600,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.add,
                                        size: isTablet ? 20 : 16,
                                        color: Colors.blue.shade600,
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
                                  FutureBuilder<double>(
                                    future: _calculateCurrentStock(
                                      ref.read(isarServiceProvider).isar,
                                      ref.read(currentCompanyProvider)?.id ?? 0,
                                      product.id,
                                    ),
                                    builder: (context, snap) {
                                      final stock =
                                          snap.data ?? product.openingQty;
                                      final color = stock <= 0
                                          ? Colors.red.shade600
                                          : stock < 5
                                              ? Colors.orange.shade700
                                              : Colors.green.shade700;

                                      return Text(
                                        'Stock: ${stock.toStringAsFixed(1)}',
                                        style: TextStyle(
                                          fontSize: isTablet ? 10 : 9,
                                          fontWeight: FontWeight.w500,
                                          color: color,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                setState(() {
                                  _lines.add(PurchaseLineDraft(
                                    productId: product.id,
                                    productName: product.name,
                                    qty: 1,
                                    rate: product.lastCost > 0
                                        ? product.lastCost
                                        : product.salePrice,
                                  ));
                                  _itemSearchCtrl.clear();
                                });
                                _onLineItemChanged(); // Trigger recalculation

                                // Show success feedback
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '${product.name} added to purchase${isAlreadyAdded ? ' (${addedCount + 1} times total)' : ''}'),
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
    final totalPaid =
        _paymentLines.fold<double>(0, (sum, payment) => sum + payment.amount);
    final balanceAmount = _grandTotal - totalPaid;
    final totalQty = _lines.fold<double>(0, (sum, l) => sum + l.qty);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      child: Column(
        children: [
          _buildCalcRow('Total Quantity', totalQty,
              isTablet: isTablet, isQuantity: true),
          const Divider(),
          _buildCalcRow('Total', _grandTotal, isBold: true, isTablet: isTablet),
          const Divider(),
          _buildCalcRow('Paid Amount', totalPaid,
              isTablet: isTablet, color: Colors.green.shade700),
          const Divider(),
          _buildCalcRow('Balance Amount', balanceAmount,
              isBold: true,
              isTablet: isTablet,
              color: balanceAmount > 0
                  ? Colors.red.shade700
                  : Colors.green.shade700),
        ],
      ),
    );
  }

  Widget _buildCalcRow(String label, double value,
      {bool isBold = false,
      bool isTablet = false,
      Color? color,
      bool isQuantity = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isTablet ? 16 : 14,
            color: color,
          ),
        ),
        Text(
          isQuantity
              ? value.toStringAsFixed(0)
              : '$_currencySymbol ${value.toStringAsFixed(0)}',
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isTablet ? 16 : 14,
            color: color,
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
    // Only calculate balance due if paid amount is entered (> 0)
    final balanceDue = _paidAmount > 0 ? totalAmount - _paidAmount : 0.0;

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
                                    (line.qty * line.rate).toStringAsFixed(2),
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
                        child: Text(
                            totalQty == totalQty.roundToDouble()
                                ? totalQty.toStringAsFixed(0)
                                : totalQty.toStringAsFixed(2),
                            style: TextStyle(
                                fontSize: isTablet ? 14 : 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade900),
                            textAlign: TextAlign.center)),
                    const Expanded(child: SizedBox()),
                    Expanded(
                        child: Text(totalAmount.toStringAsFixed(2),
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

            Divider(height: 1, color: Colors.grey.shade200),

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
                      Text(_currencySymbol,
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

  Widget _buildAmountSummary() {
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Column(
      children: [
        // Balance Summary Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Purchase Summary',
                style: TextStyle(
                  fontSize: isTablet ? 18 : 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade900,
                ),
              ),
              SizedBox(height: isTablet ? 16 : 12),

              // Previous Balance - always show
              _buildSummaryRow(
                'Previous Balance',
                _previousBalance,
                color: _previousBalance > 0
                    ? Colors.orange.shade700
                    : Colors.grey.shade600,
                isTablet: isTablet,
              ),
              SizedBox(height: isTablet ? 12 : 8),

              // New Purchase Amount
              _buildSummaryRow(
                'New Purchase Amount',
                _grandTotal,
                color: Colors.blue.shade700,
                isTablet: isTablet,
              ),

              if (_previousBalance > 0) ...[
                SizedBox(height: isTablet ? 12 : 8),
                Divider(color: Colors.grey.shade300),
                SizedBox(height: isTablet ? 12 : 8),

                // Total Payable Amount
                _buildSummaryRow(
                  'Total Payable Amount',
                  _totalPayableAmount,
                  color: Colors.grey.shade900,
                  isTablet: isTablet,
                  isBold: true,
                  fontSize: isTablet ? 18 : 16,
                ),
              ],

              SizedBox(height: isTablet ? 12 : 8),
              Divider(color: Colors.grey.shade300),
              SizedBox(height: isTablet ? 12 : 8),

              // Paid Amount
              _buildSummaryRow(
                'Paid Amount',
                _paidAmount,
                color: Colors.green.shade700,
                isTablet: isTablet,
              ),

              SizedBox(height: isTablet ? 12 : 8),

              // Remaining Balance
              _buildSummaryRow(
                'Remaining Balance',
                _remainingBalance,
                color: _remainingBalance > 0
                    ? Colors.red.shade700
                    : Colors.green.shade700,
                isTablet: isTablet,
                isBold: true,
                backgroundColor: _remainingBalance > 0
                    ? Colors.red.shade50
                    : Colors.green.shade50,
              ),
            ],
          ),
        ),
      ],
    );
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
            '$_currencySymbol ${amount.toStringAsFixed(0)}',
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
            // Cash Amount Input Field
            Text(
              'Cash Payment',
              style: TextStyle(
                fontSize: isTablet ? 18 : 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: isTablet ? 12 : 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _cashAmountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                style: TextStyle(fontSize: isTablet ? 16 : 14),
                decoration: InputDecoration(
                  hintText: 'Enter cash amount',
                  prefixIcon: Icon(
                    Icons.payments,
                    size: isTablet ? 20 : 18,
                    color: Colors.green.shade600,
                  ),
                  prefixText: '$_currencySymbol ',
                  prefixStyle: TextStyle(
                    fontSize: isTablet ? 16 : 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Colors.green.shade600,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.green.shade50,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 16 : 12,
                    vertical: isTablet ? 14 : 12,
                  ),
                ),
                onChanged: (value) {
                  final cashAmount = double.tryParse(value) ?? 0;
                  _updatePaidAmount(cashAmount);
                  // Update the first cash payment line if it exists
                  if (_paymentLines.isNotEmpty) {
                    final cashLineIndex = _paymentLines.indexWhere(
                      (line) =>
                          line.accountName?.toLowerCase().contains('cash') ==
                          true,
                    );
                    if (cashLineIndex >= 0) {
                      _paymentLines[cashLineIndex].amount = cashAmount;
                    }
                  }
                },
              ),
            ),
            SizedBox(height: isTablet ? 16 : 12),
            if (_paymentLines.isEmpty)
              Container(
                padding: EdgeInsets.symmetric(vertical: isTablet ? 20 : 16),
                child: Center(
                  child: Text(
                    'No payment methods added',
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: isTablet ? 16 : 14),
                  ),
                ),
              )
            else
              ...List.generate(_paymentLines.length, (index) {
                return _buildPaymentLine(_paymentLines[index], accounts, index);
              }),
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
          horizontal: isTablet ? 8 : 4, vertical: isTablet ? 8 : 6),
      child: Row(
        children: [
          Text(
            line.accountIcon ?? '💰',
            style: TextStyle(fontSize: isTablet ? 28 : 22),
          ),
          SizedBox(width: isTablet ? 12 : 8),
          Expanded(
            child: Text(
              line.accountName ?? 'Unknown',
              style: TextStyle(
                fontSize: isTablet ? 16 : 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: Colors.red, size: isTablet ? 24 : 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() => _paymentLines.removeAt(index));
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
                prefixText: '$_currencySymbol ',
                prefixStyle: TextStyle(
                  fontSize: isTablet ? 16 : 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(
                    color: Colors.blue.shade600,
                    width: 2,
                  ),
                ),
                contentPadding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 12 : 8, vertical: isTablet ? 10 : 8),
              ),
              onChanged: (value) {
                try {
                  final newAmount = double.tryParse(value) ?? 0;
                  if (newAmount != line.amount) {
                    setState(() {
                      line.amount = newAmount;
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
    final isTablet = MediaQuery.of(context).size.width > 600;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(isTablet ? 20 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Payment Account',
                style: TextStyle(
                  fontSize: isTablet ? 20 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: isTablet ? 20 : 16),
              ...accounts.where((account) {
                final name = account.accountName.toLowerCase();
                return !name.contains('cheque') && !name.contains('check');
              }).map((account) {
                return ListTile(
                  leading: Text(
                    account.icon ?? '💰',
                    style: TextStyle(fontSize: isTablet ? 28 : 24),
                  ),
                  title: Text(
                    account.accountName,
                    style: TextStyle(fontSize: isTablet ? 16 : 15),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(vertical: isTablet ? 8 : 4),
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
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  // Save and share purchase invoice to WhatsApp
  Future<void> _saveAndShareToWhatsApp(
      PurchaseDao purchaseDao, Company company, User? user) async {
    // Prevent multiple simultaneous saves
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // First save the invoice
      await _savePurchaseInvoice(purchaseDao, company, user,
          showActions: false);

      // If save was successful and invoice ID is set, share to WhatsApp
      if (widget.invoiceId != null) {
        // Small delay to ensure UI state is updated
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          await _shareToWhatsApp(company);
        }
      }
    } catch (e) {
      print('Error in save and share: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving and sharing: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _shareAsImage(
      PurchaseDao purchaseDao, Company company, User? user) async {
    try {
      // First save the invoice if needed
      if (widget.invoiceId == null && _selectedSupplier != null) {
        await _savePurchaseInvoice(purchaseDao, company, user,
            showActions: false);
      }

      if (_selectedSupplier == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a supplier first'),
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
            content: Text('Please add at least one item to share'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get the invoice and transaction data
      final isarService = ref.read(isarServiceProvider);
      final isar = isarService.isar;

      // Find the most recent invoice for this supplier and date
      Invoice? invoice;
      if (widget.invoiceId != null) {
        invoice = await purchaseDao.getInvoiceById(widget.invoiceId!);
      } else {
        // For newly created invoice, find by date and supplier
        final allInvoices = await isar.invoices
            .filter()
            .companyIdEqualTo(company.id)
            .invoiceTypeEqualTo(InvoiceType.purchase)
            .findAll();

        invoice = allInvoices
            .where((i) =>
                i.invoiceDate.day == _date.day &&
                i.invoiceDate.month == _date.month &&
                i.invoiceDate.year == _date.year &&
                i.partyId == _selectedSupplier!.id)
            .lastOrNull;
      }

      if (invoice == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice not found. Please save first.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await PurchaseInvoiceGenerator.shareExistingAsImage(
        invoiceId: invoice.id,
        isar: isar,
        company: company,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase invoice image shared successfully'),
            backgroundColor: Colors.green,
          ),
        );
        await _showAfterShareOrPrintActions();
      }
    } catch (e) {
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

  Future<void> _shareAsPdf(
      PurchaseDao purchaseDao, Company company, User? user) async {
    try {
      // First save the invoice if needed
      if (widget.invoiceId == null && _selectedSupplier != null) {
        await _savePurchaseInvoice(purchaseDao, company, user,
            showActions: false);
      }

      if (_selectedSupplier == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a supplier first'),
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
            content: Text('Please add at least one item to share'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get the invoice and transaction data
      final isarService = ref.read(isarServiceProvider);
      final isar = isarService.isar;

      // Find the most recent invoice for this supplier and date
      Invoice? invoice;
      if (widget.invoiceId != null) {
        invoice = await purchaseDao.getInvoiceById(widget.invoiceId!);
      } else {
        // For newly created invoice, find by date and supplier
        final allInvoices = await isar.invoices
            .filter()
            .companyIdEqualTo(company.id)
            .invoiceTypeEqualTo(InvoiceType.purchase)
            .findAll();

        invoice = allInvoices
            .where((i) =>
                i.invoiceDate.day == _date.day &&
                i.invoiceDate.month == _date.month &&
                i.invoiceDate.year == _date.year &&
                i.partyId == _selectedSupplier!.id)
            .lastOrNull;
      }

      if (invoice == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice not found. Please save first.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final transaction =
          await purchaseDao.getTransactionForInvoice(invoice.id);
      if (transaction == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Prepare line items
      final lineItems = <Map<String, dynamic>>[];
      for (final line in validLines) {
        final product = line.productId != null
            ? await isar.products.get(line.productId!)
            : null;
        lineItems.add({
          'productName': product?.name ?? line.productName ?? 'Unknown Product',
          'qty': line.qty,
          'rate': line.rate,
        });
      }

      // Prepare payment lines
      final paymentDetails = <Map<String, dynamic>>[];
      final validPaymentLines = _paymentLines
          .where((p) => p.accountId != null && p.amount > 0)
          .toList();

      for (final payLine in validPaymentLines) {
        if (payLine.accountId != null) {
          final account = await isar.accounts.get(payLine.accountId!);
          paymentDetails.add({
            'accountName': account?.name ?? payLine.accountName ?? 'Unknown',
            'amount': payLine.amount,
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase invoice PDF shared successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
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

  /// Navigate to add new party form
  Future<void> _addNewParty() async {
    final result = await Navigator.of(context).push<Party>(
      MaterialPageRoute(
        builder: (context) => const PartyFormScreen(),
      ),
    );

    if (result != null) {
      // Refresh the parties list
      ref.invalidate(partyListProvider);

      // Select the newly added party
      setState(() {
        _selectedSupplier = result;
        _supplierSearchCtrl.text = result.name;
        _supplierSearchFocus.unfocus();
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Supplier "${result.name}" added successfully!'),
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
      ..partyType = PartyType.supplier
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
      ref.invalidate(partyListProvider);

      // Select the newly added party
      setState(() {
        _selectedSupplier = result;
        _supplierSearchCtrl.text = result.name;
        _supplierSearchFocus.unfocus();
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Supplier "${result.name}" added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _shareAsPDF(Company company) async {
    if (widget.invoiceId == null) return;

    try {
      if (widget.invoiceId == null) return;
      final isar = ref.read(isarServiceProvider).isar;
      final imageBytes = await PurchaseInvoiceGenerator.buildImageById(
        invoiceId: widget.invoiceId!,
        isar: isar,
        company: company,
      );

      final memoryImage = pw.MemoryImage(imageBytes);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          final doc = pw.Document();
          doc.addPage(
            pw.Page(
              pageFormat: format,
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Center(
                child: pw.Image(memoryImage, fit: pw.BoxFit.contain),
              ),
            ),
          );
          return doc.save();
        },
      );

      await _showAfterShareOrPrintActions();
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
              Text('Generating invoice and opening WhatsApp...'),
            ],
          ),
        ),
      );

      final isar = ref.read(isarServiceProvider).isar;
      final purchaseDao = ref.read(purchaseDaoProvider);

      // Get invoice details
      final invoice = await isar.invoices.get(widget.invoiceId!);
      if (invoice == null) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get supplier
      final supplier = await isar.partys.get(invoice.partyId);
      if (supplier == null) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Supplier not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get transaction
      final transaction = await isar.transactions.get(invoice.transactionId);
      if (transaction == null) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get transaction lines for detailed invoice
      final transactionLines =
          await purchaseDao.getTransactionLines(transaction.id);

      // Prepare line items with product names, quantities, rates, and amounts
      final lineItems = <Map<String, dynamic>>[];
      for (final txLine in transactionLines) {
        if (txLine.productId != null) {
          final product = await isar.products.get(txLine.productId!);
          lineItems.add({
            'productName': product?.name ?? 'Unknown Product',
            'qty': txLine.quantity,
            'rate': txLine.unitPrice,
            'amount': txLine.quantity * txLine.unitPrice,
          });
        }
      }

      // Get payment details
      final allAccountTransactions =
          await isar.accountTransactions.where().findAll();
      final payments = allAccountTransactions
          .where((p) =>
              p.companyId == company.id &&
              p.referenceId == widget.invoiceId &&
              p.transactionType ==
                  account_models.TransactionType.purchaseInvoice)
          .toList();

      final paymentAccounts =
          await ref.read(paymentDaoProvider).getPaymentAccounts(company.id);
      double totalPaidAmount = 0;
      List<Map<String, dynamic>>? paymentDetails;

      if (payments.isNotEmpty) {
        paymentDetails = [];
        for (final payment in payments) {
          final account = await isar.accounts.get(payment.accountId);
          if (account != null) {
            // Try to find matching payment account, but handle gracefully if not found
            final paymentAccount =
                paymentAccounts.where((pa) => pa.id == account.id).firstOrNull;

            double amount =
                payment.credit; // For purchases, we credit payment accounts
            totalPaidAmount += amount;

            paymentDetails.add({
              'accountName': paymentAccount?.accountName ?? account.name,
              'amount': amount,
            });
          }
        }
      }

      // Use balance snapshot saved on invoice
      final openingBalance = invoice.previousBalance;

      if (mounted) Navigator.pop(context); // Close loading dialog

      // Debug amounts before sharing
      print('=== PURCHASE AMOUNT DEBUG ===');
      print('Invoice ID: ${invoice.id}');
      print('Invoice grandTotal: ${invoice.grandTotal}');
      print('Transaction totalAmount: ${transaction.totalAmount}');
      print('Total paid from payments: $totalPaidAmount');
      print('Line items count: ${lineItems.length}');

      double debugLineTotal = 0;
      for (final item in lineItems) {
        final itemAmount = item['amount'] ?? (item['qty'] * item['rate']);
        debugLineTotal += itemAmount;
        print(
            'Item: ${item['productName']}, Qty: ${item['qty']}, Rate: ${item['rate']}, Amount: $itemAmount');
      }
      print('Debug calculated line total: $debugLineTotal');

      if (paymentDetails != null) {
        print('Payment details:');
        for (final payment in paymentDetails) {
          print('  ${payment['accountName']}: ${payment['amount']}');
        }
      }
      print('===========================');

      // Calculate accurate completion amounts from line items
      double calculatedTotal = 0;
      for (final item in lineItems) {
        calculatedTotal += item['amount'] ?? (item['qty'] * item['rate']);
      }

      // Use calculated total if it differs from database value
      final totalToUse =
          calculatedTotal > 0 ? calculatedTotal : invoice.grandTotal;

      print(
          'Final amounts - Database: ${invoice.grandTotal}, Calculated: $calculatedTotal, Using: $totalToUse');

      // Generate comprehensive invoice image with all details
      final imageBytes =
          await PurchaseInvoiceGenerator.generatePurchaseInvoiceImage(
        company: company,
        supplier: supplier,
        invoice: invoice,
        transaction: transaction,
        lineItems: lineItems,
        paymentLines: paymentDetails,
        supplierBalance: null,
        openingBalance: openingBalance,
        notes: invoice.notes,
        attachmentImagePath: invoice.attachmentPath,
      );

      // Save image to temporary directory
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'purchase_invoice_${transaction.referenceNo}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      // Use enhanced WhatsApp service
      final whatsappService = WhatsAppService();

      // Extract supplier phone number from various sources
      String? supplierPhone = supplier.phone;
      if (supplierPhone == null || supplierPhone.isEmpty) {
        supplierPhone = WhatsAppService.extractPhoneNumber(supplier.name) ??
            WhatsAppService.extractPhoneNumber(supplier.address);
      }

      print('Attempting WhatsApp share for supplier: ${supplier.name}');
      print('Phone number found: $supplierPhone');

      // Share comprehensive invoice with image attachment
      final success = await whatsappService.shareInvoice(
        invoiceNumber: transaction.referenceNo,
        amount: totalToUse,
        currency: _currencySymbol,
        customerName: supplier.name,
        customerPhone: supplierPhone,
        invoiceType: 'Purchase Invoice',
        additionalDetails: '''📄 Complete Invoice Details:
📅 Date: ${invoice.invoiceDate.toString().split(' ')[0]}
📦 Items: ${lineItems.length}
      💰 Total Amount: $_currencySymbol ${totalToUse.toStringAsFixed(2)}
      💳 Paid Amount: $_currencySymbol ${totalPaidAmount.toStringAsFixed(2)}
      ⚖️ Balance Amount: $_currencySymbol ${(totalToUse - totalPaidAmount).toStringAsFixed(2)}
            📊 Previous Balance: $_currencySymbol ${openingBalance.toStringAsFixed(2)}''',
      );

      // Also share the detailed invoice image
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '''🧾 Purchase Invoice - ${transaction.referenceNo}
🏭 Supplier: ${supplier.name}
📅 Date: ${invoice.invoiceDate.toString().split(' ')[0]}
      💰 Amount: $_currencySymbol ${totalToUse.toStringAsFixed(2)}
      💳 Paid: $_currencySymbol ${totalPaidAmount.toStringAsFixed(2)}
      ⚖️ Balance: $_currencySymbol ${(totalToUse - totalPaidAmount).toStringAsFixed(2)}

📱 Generated by Matrix Accounts''',
      );

      if (mounted) {
        if (success) {
          if (supplierPhone != null && supplierPhone.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    '✅ Purchase Invoice sent to ${supplier.name} via WhatsApp with complete details and image!'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 1),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    '📱 Purchase Invoice shared successfully!\n(No phone number found, please select contact manually)'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'OK',
                  textColor: Colors.white,
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  },
                ),
              ),
            );
          }

          await _showAfterShareOrPrintActions();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  '❌ Failed to share Purchase Invoice. Please ensure WhatsApp is installed.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  _shareToWhatsApp(company);
                },
              ),
            ),
          );
        }
      }

      // Clean up temporary file after some delay
      Future.delayed(const Duration(seconds: 30), () {
        try {
          if (file.existsSync()) {
            file.deleteSync();
            print('Temporary file cleaned up: ${file.path}');
          }
        } catch (e) {
          print('Warning: Could not cleanup temporary file: $e');
        }
      });
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog if open
        print('Error sharing purchase invoice: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error sharing Purchase Invoice: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                _shareToWhatsApp(company);
              },
            ),
          ),
        );
      }
      print('Error sharing to WhatsApp: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Notes & Attachment section
  // ---------------------------------------------------------------------------

  Widget _buildNotesAndAttachmentSection() {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final fontSize = isTablet ? 16.0 : 14.0;

    Widget buildAttachmentPreview(String path) {
      final normalizedPath = path.trim();
      final isRemote = normalizedPath.startsWith('http://') ||
          normalizedPath.startsWith('https://');

      if (isRemote) {
        return CachedNetworkImage(
          imageUrl: normalizedPath,
          width: double.infinity,
          height: isTablet ? 220 : 180,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: double.infinity,
            height: isTablet ? 220 : 180,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          ),
          errorWidget: (_, __, ___) => Container(
            width: double.infinity,
            height: isTablet ? 220 : 180,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      }

      final localFile = File(normalizedPath);
      if (localFile.existsSync()) {
        return Image.file(
          localFile,
          width: double.infinity,
          height: isTablet ? 220 : 180,
          fit: BoxFit.cover,
        );
      }

      return Container(
        width: double.infinity,
        height: isTablet ? 220 : 180,
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Notes ────────────────────────────────────────────────────────────
        Text(
          'Notes',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade900,
          ),
        ),
        SizedBox(height: isTablet ? 10 : 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey.shade50,
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextField(
            controller: _notesCtrl,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: TextStyle(
              fontSize: isTablet ? 15 : 13,
              color: Colors.grey.shade900,
            ),
            decoration: InputDecoration(
              hintText: 'Add notes or remarks for this invoice…',
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontSize: isTablet ? 14 : 12,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(isTablet ? 14 : 12),
            ),
          ),
        ),

        SizedBox(height: isTablet ? 20 : 16),

        // ── Attachment ───────────────────────────────────────────────────────
        Row(
          children: [
            Text(
              'Attachment',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(optional image)',
              style: TextStyle(
                fontSize: isTablet ? 12 : 10,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        SizedBox(height: isTablet ? 10 : 8),

        if (_attachmentPath != null && _attachmentPath!.trim().isNotEmpty) ...[
          // Preview of selected image
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: buildAttachmentPreview(_attachmentPath!),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => setState(() => _attachmentPath = null),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(6),
                    child:
                        const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: _pickAttachmentImage,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(6),
                    child:
                        const Icon(Icons.edit, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          // Pick-image button
          InkWell(
            onTap: _pickAttachmentImage,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              height: isTablet ? 120 : 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.shade200,
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
                color: Colors.blue.shade50,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: isTablet ? 36 : 30,
                    color: Colors.blue.shade400,
                  ),
                  SizedBox(height: isTablet ? 8 : 6),
                  Text(
                    'Tap to add image',
                    style: TextStyle(
                      fontSize: isTablet ? 13 : 11,
                      color: Colors.blue.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Camera or Gallery',
                    style: TextStyle(
                      fontSize: isTablet ? 11 : 9,
                      color: Colors.blue.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Opens a bottom-sheet to let the user pick an image from camera or gallery.
  Future<void> _pickAttachmentImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Select Image Source',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.orange),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.orange),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (picked != null && mounted) {
      setState(() => _attachmentPath = picked.path);
    }
  }
}
