// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_table_plus/flutter_table_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';

import '../../../core/config/providers.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/widgets/navigation_drawer_helper.dart';
import '../../../data/models/inventory_models.dart';
import '../../../data/models/invoice_stock_models.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/transaction_model.dart';
import '../../../presentation/widgets/searchable_list.dart';

class PurchaseReturnFormScreen extends ConsumerStatefulWidget {
  const PurchaseReturnFormScreen({super.key});

  @override
  ConsumerState<PurchaseReturnFormScreen> createState() =>
      _PurchaseReturnFormScreenState();
}

class _PurchaseReturnFormScreenState
    extends ConsumerState<PurchaseReturnFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _returnNoController = TextEditingController();
  final _notesController = TextEditingController();
  final _currencyFormat = NumberFormat.currency(symbol: 'PKR ');
  final _dateFormat = DateFormat('dd MMM yyyy');
  final Map<int, TextEditingController> _returnQtyControllers = {};

  Party? _selectedSupplier;
  Invoice? _selectedOriginalInvoice;
  DateTime _returnDate = DateTime.now();
  final List<_ReturnLineItem> _returnItems = [];
  double _totalReturnAmount = 0.0;
  bool _isLoading = false;

  String get _currencySymbol {
    final settings = ref.read(settingsProvider);
    return SettingsConstants.currencySymbols[settings.defaultCurrency] ??
        settings.defaultCurrency;
  }

  @override
  void initState() {
    super.initState();
    _generateReturnNumber();
  }

  @override
  void dispose() {
    _returnNoController.dispose();
    _notesController.dispose();
    for (final controller in _returnQtyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _generateReturnNumber() {
    final now = DateTime.now();
    _returnNoController.text =
        'PR${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.millisecond.toString().padLeft(3, '0')}';
  }

  Future<List<Party>> _loadSuppliers() async {
    final company = ref.read(currentCompanyProvider);
    if (company == null) return [];

    final isar = ref.read(isarServiceProvider).isar;
    return await isar
        .collection<Party>()
        .filter()
        .companyIdEqualTo(company.id)
        .and()
        .partyTypeEqualTo(PartyType.supplier)
        .findAll();
  }

  Future<List<Invoice>> _loadPurchaseInvoices() async {
    if (_selectedSupplier == null) return [];

    final company = ref.read(currentCompanyProvider);
    if (company == null) return [];

    final isar = ref.read(isarServiceProvider).isar;
    return await isar
        .collection<Invoice>()
        .filter()
        .companyIdEqualTo(company.id)
        .and()
        .invoiceTypeEqualTo(InvoiceType.purchase)
        .and()
        .partyIdEqualTo(_selectedSupplier!.id)
        .and()
        .not()
        .statusEqualTo('Return')
        .sortByInvoiceDateDesc()
        .findAll();
  }

  Future<void> _loadOriginalInvoiceItems() async {
    if (_selectedOriginalInvoice == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final isar = ref.read(isarServiceProvider).isar;
      final transactionLines = await isar
          .collection<TransactionLine>()
          .filter()
          .transactionIdEqualTo(_selectedOriginalInvoice!.transactionId)
          .findAll();

      _returnItems.clear();
      for (final controller in _returnQtyControllers.values) {
        controller.dispose();
      }
      _returnQtyControllers.clear();
      for (final line in transactionLines) {
        if (line.productId != null) {
          final product = await isar.collection<Product>().get(line.productId!);
          if (product != null) {
            _returnItems.add(_ReturnLineItem(
              productId: product.id,
              productName: product.name,
              originalQuantity: line.quantity,
              originalUnitPrice: line.unitPrice,
              returnQuantity: 0.0,
              returnUnitPrice: line.unitPrice,
            ));
          }
        }
      }

      _calculateTotal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading invoice items: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _ensureReturnQtyController(int index, _ReturnLineItem item) {
    if (!_returnQtyControllers.containsKey(index)) {
      _returnQtyControllers[index] = TextEditingController(
        text: item.returnQuantity > 0
            ? (item.returnQuantity == item.returnQuantity.roundToDouble()
                ? item.returnQuantity.toStringAsFixed(0)
                : item.returnQuantity.toStringAsFixed(2))
            : '',
      );
    }
  }

  void _calculateTotal() {
    _totalReturnAmount = _returnItems.fold(
        0.0, (sum, item) => sum + (item.returnQuantity * item.returnUnitPrice));
    setState(() {});
  }

  Widget _buildReturnItemsTable(bool isTablet) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = isTablet ? 24.0 : 16.0;
    final cardPadding = isTablet ? 20.0 : 16.0;
    final availableWidth = width - (horizontalPadding * 2) - (cardPadding * 2);

    const productPct = 0.34;
    const originalQtyPct = 0.13;
    const returnQtyPct = 0.16;
    const ratePct = 0.15;
    const amountPct = 0.16;
    const actionPct = 0.06;

    final outerHorizontalPadding = isTablet ? 8.0 : 6.0;
    final tableInnerWidth = availableWidth - (outerHorizontalPadding * 2);

    double productWidth = tableInnerWidth * productPct;
    double originalQtyWidth = tableInnerWidth * originalQtyPct;
    double returnQtyWidth = tableInnerWidth * returnQtyPct;
    double rateWidth = tableInnerWidth * ratePct;
    double amountWidth = tableInnerWidth * amountPct;
    double actionWidth = tableInnerWidth * actionPct;

    const minProduct = 120.0;
    const minOriginalQty = 80.0;
    const minReturnQty = 100.0;
    const minRate = 90.0;
    const minAmount = 90.0;
    const minAction = 52.0;

    productWidth = productWidth < minProduct ? minProduct : productWidth;
    originalQtyWidth =
        originalQtyWidth < minOriginalQty ? minOriginalQty : originalQtyWidth;
    returnQtyWidth =
        returnQtyWidth < minReturnQty ? minReturnQty : returnQtyWidth;
    rateWidth = rateWidth < minRate ? minRate : rateWidth;
    amountWidth = amountWidth < minAmount ? minAmount : amountWidth;
    actionWidth = actionWidth < minAction ? minAction : actionWidth;

    final totalWidth = productWidth +
        originalQtyWidth +
        returnQtyWidth +
        rateWidth +
        amountWidth +
        actionWidth;
    if (totalWidth > tableInnerWidth && tableInnerWidth > 0) {
      var overflow = totalWidth - tableInnerWidth;
      final adjustable = productWidth - minProduct;
      if (adjustable > 0) {
        final reduced = overflow > adjustable ? adjustable : overflow;
        productWidth -= reduced;
        overflow -= reduced;
      }
      final reducibleReturnQty = returnQtyWidth - minReturnQty;
      if (reducibleReturnQty > 0 && overflow > 0) {
        final reduced =
            overflow > reducibleReturnQty ? reducibleReturnQty : overflow;
        returnQtyWidth -= reduced;
        overflow -= reduced;
      }
      final reducibleRate = rateWidth - minRate;
      if (reducibleRate > 0 && overflow > 0) {
        final reduced = overflow > reducibleRate ? reducibleRate : overflow;
        rateWidth -= reduced;
        overflow -= reduced;
      }
      final reducibleAmount = amountWidth - minAmount;
      if (reducibleAmount > 0 && overflow > 0) {
        final reduced = overflow > reducibleAmount ? reducibleAmount : overflow;
        amountWidth -= reduced;
        overflow -= reduced;
      }
    }

    final columns = TableColumnsBuilder<_ReturnLineItem>()
      ..addColumn(
        'product',
        TablePlusColumn<_ReturnLineItem>(
          key: 'product',
          label: 'Product',
          order: 1,
          width: productWidth,
          sortable: false,
          valueAccessor: (item) => item.productName,
          statefulCellBuilder: (context, row, isSelected, isDim) {
            return Text(
              row.productName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: isTablet ? 13 : 12,
              ),
            );
          },
        ),
      )
      ..addColumn(
        'originalQty',
        TablePlusColumn<_ReturnLineItem>(
          key: 'originalQty',
          label: 'Orig Qty',
          order: 2,
          width: originalQtyWidth,
          sortable: false,
          alignment: Alignment.center,
          textAlign: TextAlign.center,
          valueAccessor: (item) => item.originalQuantity,
          statefulCellBuilder: (context, row, isSelected, isDim) => Text(
            row.originalQuantity.toStringAsFixed(2),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isTablet ? 12 : 11,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      )
      ..addColumn(
        'returnQty',
        TablePlusColumn<_ReturnLineItem>(
          key: 'returnQty',
          label: 'Return Qty',
          order: 3,
          width: returnQtyWidth,
          sortable: false,
          alignment: Alignment.center,
          textAlign: TextAlign.center,
          valueAccessor: (item) => item.returnQuantity,
          statefulCellBuilder: (context, row, isSelected, isDim) {
            final index = _returnItems.indexOf(row);
            if (index < 0) return const SizedBox.shrink();
            _ensureReturnQtyController(index, row);
            final controller = _returnQtyControllers[index]!;

            return SizedBox(
              height: isTablet ? 34 : 30,
              child: TextFormField(
                controller: controller,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                  final qty = double.tryParse(value) ?? 0.0;
                  final normalized =
                      qty > row.originalQuantity ? row.originalQuantity : qty;
                  if (normalized != qty) {
                    controller.text = normalized.toStringAsFixed(2);
                    controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: controller.text.length),
                    );
                  }
                  if (row.returnQuantity != normalized) {
                    row.returnQuantity = normalized;
                    _calculateTotal();
                  }
                },
                validator: (value) {
                  final qty = double.tryParse(value ?? '') ?? 0.0;
                  if (qty < 0) {
                    return 'Invalid';
                  }
                  if (qty > row.originalQuantity) {
                    return 'Max ${row.originalQuantity.toStringAsFixed(2)}';
                  }
                  return null;
                },
              ),
            );
          },
        ),
      )
      ..addColumn(
        'rate',
        TablePlusColumn<_ReturnLineItem>(
          key: 'rate',
          label: 'Rate',
          order: 4,
          width: rateWidth,
          sortable: false,
          alignment: Alignment.centerRight,
          textAlign: TextAlign.right,
          valueAccessor: (item) => item.returnUnitPrice,
          statefulCellBuilder: (context, row, isSelected, isDim) => Text(
            _currencyFormat.format(row.returnUnitPrice),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: isTablet ? 12 : 11),
          ),
        ),
      )
      ..addColumn(
        'amount',
        TablePlusColumn<_ReturnLineItem>(
          key: 'amount',
          label: 'Amount ($_currencySymbol)',
          order: 5,
          width: amountWidth,
          sortable: false,
          alignment: Alignment.centerRight,
          textAlign: TextAlign.right,
          valueAccessor: (item) => item.returnQuantity * item.returnUnitPrice,
          statefulCellBuilder: (context, row, isSelected, isDim) => Text(
            _currencyFormat.format(row.returnQuantity * row.returnUnitPrice),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 12 : 11,
            ),
          ),
        ),
      )
      ..addColumn(
        'action',
        TablePlusColumn<_ReturnLineItem>(
          key: 'action',
          label: 'Action',
          order: 6,
          width: actionWidth,
          sortable: false,
          alignment: Alignment.center,
          textAlign: TextAlign.center,
          valueAccessor: (item) => '',
          statefulCellBuilder: (context, row, isSelected, isDim) => IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            iconSize: isTablet ? 20 : 18,
            splashRadius: isTablet ? 18 : 16,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
            onPressed: () {
              final removeIndex = _returnItems.indexOf(row);
              if (removeIndex == -1) return;
              setState(() {
                _returnQtyControllers[removeIndex]?.dispose();
                _returnQtyControllers.remove(removeIndex);

                final keysToShift = _returnQtyControllers.keys
                    .where((key) => key > removeIndex)
                    .toList()
                  ..sort();
                for (final key in keysToShift) {
                  final ctrl = _returnQtyControllers.remove(key);
                  if (ctrl != null) {
                    _returnQtyControllers[key - 1] = ctrl;
                  }
                }

                _returnItems.removeAt(removeIndex);
                _calculateTotal();
              });
            },
          ),
        ),
      );

    final horizontalCellPadding = isTablet ? 5.0 : 4.0;
    final headerHeight = isTablet ? 40.0 : 36.0;
    final rowHeight = isTablet ? 42.0 : 38.0;
    final footerHeight = isTablet ? 34.0 : 30.0;
    final visibleRows = _returnItems.isEmpty ? 1 : _returnItems.length;
    final tableHeight = headerHeight + (visibleRows * rowHeight) + footerHeight;
    final totalQty =
        _returnItems.fold<double>(0, (sum, item) => sum + item.returnQuantity);

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: EdgeInsets.symmetric(
              horizontal: outerHorizontalPadding, vertical: 3),
          child: SizedBox(
            height: tableHeight,
            child: Column(
              children: [
                Expanded(
                  child: FlutterTablePlus<_ReturnLineItem>(
                    columns: columns.build(),
                    data: _returnItems,
                    rowId: (item) =>
                        '${item.productId}-${_returnItems.indexOf(item)}',
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
                          horizontal: horizontalCellPadding,
                        ),
                        textStyle: TextStyle(
                          fontSize: isTablet ? 12 : 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF212121),
                        ),
                      ),
                      bodyTheme: TablePlusBodyTheme(
                        rowHeight: rowHeight,
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalCellPadding,
                        ),
                        textStyle: TextStyle(
                          fontSize: isTablet ? 12 : 11,
                          color: const Color(0xFF212121),
                        ),
                      ),
                    ),
                    noDataWidget: Center(
                      child: Text(
                        'No return items loaded.',
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
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: productWidth,
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
                        width: originalQtyWidth,
                      ),
                      SizedBox(
                        width: returnQtyWidth,
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
                      SizedBox(width: rateWidth),
                      SizedBox(
                        width: amountWidth,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalCellPadding,
                          ),
                          child: Text(
                            _totalReturnAmount.toStringAsFixed(2),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: isTablet ? 12 : 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: actionWidth),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Text(
                'Total Return Amount:',
                style: TextStyle(
                  fontSize: isTablet ? 14 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _currencyFormat.format(_totalReturnAmount),
                style: TextStyle(
                  fontSize: isTablet ? 16 : 14,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _saveReturn() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSupplier == null) {
      _showError('Please select a supplier');
      return;
    }
    if (_selectedOriginalInvoice == null) {
      _showError('Please select original purchase invoice');
      return;
    }
    if (_returnItems.where((item) => item.returnQuantity > 0).isEmpty) {
      _showError('Please add at least one item to return');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final company = ref.read(currentCompanyProvider);
      if (company == null) throw Exception('No company selected');

      final isar = ref.read(isarServiceProvider).isar;

      // Create return transaction
      final transaction = Transaction()
        ..companyId = company.id
        ..type = TransactionType.purchaseReturn
        ..date = _returnDate
        ..referenceNo = _returnNoController.text
        ..partyId = _selectedSupplier!.id
        ..totalAmount = _totalReturnAmount
        ..isPosted = true
        ..createdAt = DateTime.now();

      // Save transaction
      await isar.writeTxn(() async {
        final transactionId =
            await isar.collection<Transaction>().put(transaction);

        // Create transaction lines for returned items
        for (final item in _returnItems) {
          if (item.returnQuantity > 0) {
            final transactionLine = TransactionLine()
              ..transactionId = transactionId
              ..productId = item.productId
              ..quantity = item.returnQuantity
              ..unitPrice = item.returnUnitPrice
              ..lineAmount = item.returnQuantity * item.returnUnitPrice;

            await isar.collection<TransactionLine>().put(transactionLine);
          }
        }

        // Create return invoice
        final returnInvoice = Invoice()
          ..companyId = company.id
          ..transactionId = transactionId
          ..invoiceType = InvoiceType.purchase
          ..partyId = _selectedSupplier!.id
          ..invoiceDate = _returnDate
          ..grandTotal = _totalReturnAmount
          ..status = 'Return';

        await isar.collection<Invoice>().put(returnInvoice);

        // Update stock ledger for returned items
        for (final item in _returnItems) {
          if (item.returnQuantity > 0) {
            final stockLedger = StockLedger()
              ..companyId = company.id
              ..productId = item.productId
              ..date = _returnDate
              ..movementType = StockMovementType
                  .outAdjustment // Returning items reduces stock
              ..quantityDelta =
                  -item.returnQuantity // Negative because it's going out
              ..unitCost = item.returnUnitPrice
              ..totalCost = item.returnQuantity * item.returnUnitPrice
              ..transactionId = transactionId;

            await isar.collection<StockLedger>().put(stockLedger);
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase return created successfully'),
            backgroundColor: Colors.green,
          ),
        );
        await _showPostSaveActions();
      }
    } catch (e) {
      if (mounted) {
        _showError('Error creating purchase return: $e');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _showPostSaveActions() async {
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
                'Purchase Return Saved',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading:
                    const Icon(Icons.add_circle_outline, color: Colors.orange),
                title: const Text('New Purchase Return'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    this.context,
                    MaterialPageRoute(
                      builder: (_) => const PurchaseReturnFormScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.list_alt, color: Colors.blueGrey),
                title: const Text('Back to Return List'),
                onTap: () {
                  Navigator.pop(context);
                  this.context.go('/purchase/return');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final company = ref.watch(currentCompanyProvider);
    final isTablet = MediaQuery.of(context).size.width > 600;

    if (company == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New Purchase Return')),
        body: const Center(
          child: Text('Please select a company first'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'New Purchase Return',
          style: TextStyle(fontSize: isTablet ? 24 : 20),
        ),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
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
      drawer: NavigationDrawerHelper.buildNavigationDrawer(
        context,
        ref: ref,
        selectedItem: 'purchase-returns',
      ),
      body: Form(
        key: _formKey,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              isTablet ? 24 : 16,
              isTablet ? 20 : 16,
              isTablet ? 24 : 16,
              (isTablet ? 20 : 16) + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Return Details Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Return Details',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Return Number and Date
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _returnNoController,
                                decoration: const InputDecoration(
                                  labelText: 'Return Number',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter return number';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _returnDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (date != null) {
                                    setState(() {
                                      _returnDate = date;
                                    });
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Return Date',
                                    border: OutlineInputBorder(),
                                    suffixIcon: Icon(Icons.calendar_today),
                                  ),
                                  child: Text(_dateFormat.format(_returnDate)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Supplier Selection
                        FutureBuilder<List<Party>>(
                          future: _loadSuppliers(),
                          builder: (context, snapshot) {
                            final suppliers = snapshot.data ?? [];

                            return SearchableDropdown<Party>(
                              items: suppliers,
                              hintText:
                                  _selectedSupplier?.name ?? 'Search Supplier',
                              maxHeight: 300,
                              searchMatcher: (supplier) => supplier.name,
                              onSelected: (supplier) {
                                setState(() {
                                  _selectedSupplier = supplier;
                                  _selectedOriginalInvoice = null;
                                  _returnItems.clear();
                                  _totalReturnAmount = 0.0;
                                });
                              },
                              isSelected: _selectedSupplier != null,
                              onClear: _selectedSupplier != null
                                  ? () {
                                      setState(() {
                                        _selectedSupplier = null;
                                        _selectedOriginalInvoice = null;
                                        _returnItems.clear();
                                        _totalReturnAmount = 0.0;
                                      });
                                    }
                                  : null,
                              itemBuilder: (supplier) => ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: isTablet ? 16 : 14,
                                  backgroundColor: Colors.orange.shade100,
                                  child: Text(
                                    supplier.name.isNotEmpty
                                        ? supplier.name[0].toUpperCase()
                                        : 'S',
                                    style: TextStyle(
                                      fontSize: isTablet ? 14 : 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  supplier.name,
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
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // Original Purchase Invoice Selection
                        if (_selectedSupplier != null)
                          FutureBuilder<List<Invoice>>(
                            future: _loadPurchaseInvoices(),
                            builder: (context, snapshot) {
                              final invoices = snapshot.data ?? [];

                              return SearchableDropdown<Invoice>(
                                items: invoices,
                                hintText: _selectedOriginalInvoice != null
                                    ? 'Invoice ${_selectedOriginalInvoice!.id} • ${_currencyFormat.format(_selectedOriginalInvoice!.grandTotal)} • ${_dateFormat.format(_selectedOriginalInvoice!.invoiceDate)}'
                                    : 'Search Original Purchase Invoice',
                                maxHeight: 320,
                                searchMatcher: (invoice) =>
                                    'Invoice ${invoice.id} ${invoice.grandTotal} ${_dateFormat.format(invoice.invoiceDate)}',
                                onSelected: (invoice) {
                                  setState(() {
                                    _selectedOriginalInvoice = invoice;
                                  });
                                  _loadOriginalInvoiceItems();
                                },
                                isSelected: _selectedOriginalInvoice != null,
                                onClear: _selectedOriginalInvoice != null
                                    ? () {
                                        setState(() {
                                          _selectedOriginalInvoice = null;
                                          _returnItems.clear();
                                          _totalReturnAmount = 0.0;
                                          for (final controller
                                              in _returnQtyControllers.values) {
                                            controller.dispose();
                                          }
                                          _returnQtyControllers.clear();
                                        });
                                      }
                                    : null,
                                itemBuilder: (invoice) => ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: isTablet ? 16 : 14,
                                    backgroundColor: Colors.blue.shade100,
                                    child: Icon(
                                      Icons.receipt_long,
                                      size: isTablet ? 16 : 14,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  title: Text(
                                    'Invoice ${invoice.id}',
                                    style: TextStyle(
                                      fontSize: isTablet ? 14 : 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${_currencyFormat.format(invoice.grandTotal)} • ${_dateFormat.format(invoice.invoiceDate)}',
                                    style: TextStyle(
                                      fontSize: isTablet ? 12 : 11,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  trailing: Icon(
                                    Icons.arrow_forward_ios,
                                    size: isTablet ? 14 : 12,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 16),

                        // Notes
                        TextFormField(
                          controller: _notesController,
                          decoration: const InputDecoration(
                            labelText: 'Notes (Optional)',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Return Items Card
                if (_returnItems.isNotEmpty) ...[
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Return Items',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Total: ${_currencyFormat.format(_totalReturnAmount)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildReturnItemsTable(isTablet),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
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
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: isTablet ? 18 : 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isTablet ? 12 : 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _saveReturn,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save, color: Colors.white),
                          label: Text(
                            _isLoading ? 'Saving...' : 'Save',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isTablet ? 18 : 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            padding: EdgeInsets.symmetric(
                                vertical: isTablet ? 16 : 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReturnLineItem {
  final int productId;
  final String productName;
  final double originalQuantity;
  final double originalUnitPrice;
  double returnQuantity;
  final double returnUnitPrice;

  _ReturnLineItem({
    required this.productId,
    required this.productName,
    required this.originalQuantity,
    required this.originalUnitPrice,
    required this.returnQuantity,
    required this.returnUnitPrice,
  });
}
