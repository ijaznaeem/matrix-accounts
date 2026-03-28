// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/config/providers.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/payment_models.dart';
import '../../../presentation/widgets/searchable_list.dart';
import '../../parties/logic/party_provider.dart';
import '../logic/payment_providers.dart';
import '../services/payment_out_receipt_generator.dart';

class PaymentOutListScreen extends ConsumerStatefulWidget {
  const PaymentOutListScreen({super.key});

  @override
  ConsumerState<PaymentOutListScreen> createState() =>
      _PaymentOutListScreenState();
}

class _PaymentOutListScreenState extends ConsumerState<PaymentOutListScreen> {
  String _searchQuery = '';
  Party? _selectedSupplier;
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    // Set default date range to current month
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate =
        DateTime(now.year, now.month + 1, 0); // Last day of current month
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(currentCompanyProvider);
    final paymentsAsync = ref.watch(paymentOutsProvider);
    final partiesAsync = ref.watch(partyListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Out'),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                company?.name ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter section to match modern design
          Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: partiesAsync.when(
                        loading: () => Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        error: (_, __) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _selectedSupplier?.name ?? 'All Suppliers',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        data: (parties) {
                          return SearchableDropdown<Party>(
                            items: parties,
                            hintText:
                                _selectedSupplier?.name ?? 'All Suppliers',
                            isSelected: _selectedSupplier != null,
                            onClear: () {
                              setState(() => _selectedSupplier = null);
                            },
                            onSelected: (party) {
                              setState(() => _selectedSupplier = party);
                            },
                            searchMatcher: (party) => party.name,
                            itemBuilder: (party) => ListTile(
                              dense: true,
                              title: Text(
                                party.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            maxHeight: 280,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _selectDateRange(),
                  child: Row(
                    children: [
                      Text(
                        'Custom Range',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_drop_down,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.red.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'to',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_endDate.day.toString().padLeft(2, '0')}/${_endDate.month.toString().padLeft(2, '0')}/${_endDate.year}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Payment-Out',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_drop_down,
                            color: Colors.grey.shade600,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Enhanced Search field
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText:
                    'Search by supplier name, voucher number, or amount...',
                hintStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.grey.shade600,
                  size: 22,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: Colors.grey.shade600,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.grey.shade200,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.grey.shade200,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.red.shade400,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
              ),
              onChanged: (value) {
                try {
                  if (mounted) {
                    setState(() => _searchQuery = value.toLowerCase());
                  }
                } catch (e) {
                  print('Error updating payment out search: $e');
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: paymentsAsync.when(
              data: (payments) {
                if (payments.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No payment vouchers yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Create your first payment voucher',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return _PaymentOutList(
                  payments: payments,
                  searchQuery: _searchQuery,
                  selectedSupplier: _selectedSupplier,
                  startDate: _startDate,
                  endDate: _endDate,
                  onPaymentDeleted: () {
                    ref.invalidate(paymentOutsProvider);
                  },
                );
              },
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Loading payments...',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading payments',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.red.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: FloatingActionButton.extended(
          onPressed: () async {
            final result = await context.push('/payments/out/form');
            if (result == true && mounted) {
              ref.invalidate(paymentOutsProvider);
            }
          },
          backgroundColor: Colors.blueAccent,
          elevation: 4,
          icon: const Icon(
            Icons.add,
            color: Colors.white,
          ),
          label: const Text(
            'Add Payment Out',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(
        start: _startDate,
        end: _endDate,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.red,
              brightness: Brightness.light,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }
}

class _PaymentOutList extends ConsumerWidget {
  final List<PaymentOut> payments;
  final String searchQuery;
  final Party? selectedSupplier;
  final DateTime startDate;
  final DateTime endDate;
  final VoidCallback onPaymentDeleted;

  const _PaymentOutList({
    required this.payments,
    required this.searchQuery,
    required this.selectedSupplier,
    required this.startDate,
    required this.endDate,
    required this.onPaymentDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getPaymentsWithSuppliers(ref),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Loading payments...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading payments',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final paymentsWithSuppliers = snapshot.data ?? [];
        final filtered = paymentsWithSuppliers.where((item) {
          final payment = item['payment'] as PaymentOut;
          final supplier = item['supplier'] as Party?;

          // Date range filter
          final paymentDate = DateTime(
            payment.voucherDate.year,
            payment.voucherDate.month,
            payment.voucherDate.day,
          );
          final isInDateRange = paymentDate
                  .isAfter(startDate.subtract(const Duration(days: 1))) &&
              paymentDate.isBefore(endDate.add(const Duration(days: 1)));

          if (!isInDateRange) return false;

          // Supplier filter
          if (selectedSupplier != null) {
            if (supplier?.id != selectedSupplier!.id) return false;
          }

          // Search query filter
          if (searchQuery.isNotEmpty) {
            final matchesSearch =
                (supplier?.name.toLowerCase().contains(searchQuery) ?? false) ||
                    payment.voucherNo.toLowerCase().contains(searchQuery) ||
                    payment.totalAmount.toString().contains(searchQuery);
            if (!matchesSearch) return false;
          }

          return true;
        }).toList()
          ..sort((a, b) {
            final paymentA = a['payment'] as PaymentOut;
            final paymentB = b['payment'] as PaymentOut;
            return paymentB.voucherDate.compareTo(paymentA.voucherDate);
          });

        if (filtered.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  'No payment vouchers found',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Try adjusting your search terms',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final payment = filtered[index]['payment'] as PaymentOut;
            return _PaymentOutCard(
              payment: payment,
              onDeleted: onPaymentDeleted,
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getPaymentsWithSuppliers(
      WidgetRef ref) async {
    final isarService = ref.read(isarServiceProvider);
    final isar = isarService.isar;

    final paymentsWithSuppliers = <Map<String, dynamic>>[];
    for (final payment in payments) {
      final supplier = await isar.partys.get(payment.partyId);
      paymentsWithSuppliers.add({
        'payment': payment,
        'supplier': supplier,
      });
    }

    return paymentsWithSuppliers;
  }
}

class _PaymentOutCard extends ConsumerWidget {
  final PaymentOut payment;
  final VoidCallback onDeleted;

  const _PaymentOutCard({
    required this.payment,
    required this.onDeleted,
  });

  void _showSnackBar(BuildContext context, String message,
      {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _sharePaymentReceipt(
    BuildContext context,
    WidgetRef ref,
    Party supplier,
    List<PaymentOutLine> lines,
  ) async {
    final company = ref.read(currentCompanyProvider);
    if (company == null) {
      _showSnackBar(context, 'No company selected', isError: true);
      return;
    }

    await PaymentOutReceiptGenerator.shareReceipt(
      context: context,
      company: company,
      supplier: supplier,
      payment: payment,
      lines: lines,
      totalAmount: payment.totalAmount,
      imagePath: payment.attachmentPath,
    );
  }

  Future<void> _printPaymentReceipt(
    BuildContext context,
    WidgetRef ref,
    Party supplier,
    List<PaymentOutLine> lines,
  ) async {
    final company = ref.read(currentCompanyProvider);
    if (company == null) {
      _showSnackBar(context, 'No company selected', isError: true);
      return;
    }

    try {
      final Uint8List pdfBytes =
          await PaymentOutReceiptGenerator.generateReceiptPdf(
        company: company,
        supplier: supplier,
        payment: payment,
        lines: lines,
        totalAmount: payment.totalAmount,
        imagePath: payment.attachmentPath,
      );

      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } catch (e) {
      _showSnackBar(context, 'Error printing payment: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final currencySymbol =
        SettingsConstants.currencySymbols[settings.defaultCurrency] ??
            settings.defaultCurrency;
    final isarService = ref.read(isarServiceProvider);
    final paymentDao = ref.read(paymentDaoProvider);

    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([
        isarService.isar.partys.get(payment.partyId),
        paymentDao.getPaymentOutLines(payment.id),
      ]),
      builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
        final supplier = snapshot.data?[0] as Party?;
        final lines = (snapshot.data?[1] as List<PaymentOutLine>?) ?? [];

        return Dismissible(
          key: Key('payment_out_${payment.id}'),
          direction: DismissDirection.startToEnd,
          background: Container(
            decoration: BoxDecoration(
              color: Colors.red.shade400,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            margin: const EdgeInsets.only(bottom: 12),
            child: const Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  color: Colors.white,
                  size: 28,
                ),
                SizedBox(width: 12),
                Text(
                  'Delete',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Payment'),
                content: Text(
                    'Are you sure you want to delete payment voucher #${payment.voucherNo}?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'Delete',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );
          },
          onDismissed: (direction) async {
            try {
              await paymentDao.deletePaymentOut(payment.id);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('Payment voucher #${payment.voucherNo} deleted'),
                    backgroundColor: Colors.green,
                    action: SnackBarAction(
                      label: 'UNDO',
                      textColor: Colors.white,
                      onPressed: onDeleted,
                    ),
                  ),
                );
                onDeleted();
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error deleting payment: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
                onDeleted();
              }
            }
          },
          child: Card(
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () async {
                final result =
                    await context.push('/payments/out/form?id=${payment.id}');
                if (result == true && context.mounted) {
                  onDeleted();
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${payment.voucherNo} • ${DateFormat('dd MMM yy').format(payment.voucherDate)}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                supplier?.name ?? 'Unknown Supplier',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.red.shade200,
                            ),
                          ),
                          child: Text(
                            'Payment-Out',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$currencySymbol ${payment.totalAmount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.red,
                                ),
                              ),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: (supplier == null)
                                        ? null
                                        : () => _sharePaymentReceipt(
                                            context, ref, supplier, lines),
                                    icon: Icon(
                                      Icons.share,
                                      size: 16,
                                      color: Colors.blue.shade700,
                                    ),
                                    label: Text(
                                      'Share',
                                      style: TextStyle(
                                          color: Colors.blue.shade700),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Colors.blue.shade50,
                                      side: BorderSide(
                                          color: Colors.blue.shade200),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: (supplier == null)
                                        ? null
                                        : () => _printPaymentReceipt(
                                            context, ref, supplier, lines),
                                    icon: Icon(
                                      Icons.print,
                                      size: 16,
                                      color: Colors.deepPurple.shade700,
                                    ),
                                    label: Text(
                                      'Print',
                                      style: TextStyle(
                                          color: Colors.deepPurple.shade700),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor:
                                          Colors.deepPurple.shade50,
                                      side: BorderSide(
                                          color: Colors.deepPurple.shade200),
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
