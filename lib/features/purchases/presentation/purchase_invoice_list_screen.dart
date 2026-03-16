// ignore_for_file: unused_field, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/providers.dart';
import '../../../core/widgets/navigation_drawer_helper.dart';
import '../../../data/models/invoice_stock_models.dart';
import '../../../data/models/party_model.dart';
import '../services/purchase_invoice_generator.dart';
import '../services/purchase_invoice_service.dart';
import 'purchase_invoice_form_screen.dart';

class PurchaseInvoiceListScreen extends ConsumerStatefulWidget {
  const PurchaseInvoiceListScreen({super.key});

  @override
  ConsumerState<PurchaseInvoiceListScreen> createState() =>
      _PurchaseInvoiceListScreenState();
}

class _PurchaseInvoiceListScreenState
    extends ConsumerState<PurchaseInvoiceListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final _currencyFormat = NumberFormat.currency(symbol: 'PKR ');
  final _dateFormat = DateFormat('dd MMM yyyy');
  final _cardMargin = const EdgeInsets.symmetric(vertical: 8);
  final _cardBorderRadius = 12.0;

  // Cache the futures to prevent rebuilding
  Future<List<Invoice>>? _invoicesFuture;
  Future<List<Invoice>>? _totalInvoicesFuture;

  @override
  void initState() {
    super.initState();
    _initializeFutures();
  }

  void _initializeFutures() {
    final company = ref.read(currentCompanyProvider);
    if (company != null) {
      final isar = ref.read(isarServiceProvider).isar;
      final service = PurchaseInvoiceService(isar);
      _invoicesFuture = service.getAllPurchaseInvoices(company.id);
      _totalInvoicesFuture = service.getAllPurchaseInvoices(company.id);
    }
  }

  void _refreshInvoices() {
    final company = ref.read(currentCompanyProvider);
    if (company != null) {
      final isar = ref.read(isarServiceProvider).isar;
      final service = PurchaseInvoiceService(isar);
      setState(() {
        if (_searchQuery.isEmpty) {
          _invoicesFuture = service.getAllPurchaseInvoices(company.id);
        } else {
          _invoicesFuture =
              service.searchPurchaseInvoices(company.id, _searchQuery);
        }
        _totalInvoicesFuture = service.getAllPurchaseInvoices(company.id);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _shareInvoiceImage(Invoice invoice) async {
    try {
      _showSnackBar('Preparing invoice image...');
      final company = ref.read(currentCompanyProvider);
      if (company == null) {
        _showSnackBar('No company selected', isError: true);
        return;
      }
      final isar = ref.read(isarServiceProvider).isar;
      await PurchaseInvoiceGenerator.shareExistingAsImage(
        invoiceId: invoice.id,
        isar: isar,
        company: company,
      );
    } catch (e) {
      _showSnackBar('Error sharing invoice image: $e', isError: true);
    }
  }

  Future<void> _printInvoicePdf(Invoice invoice) async {
    try {
      _showSnackBar('Preparing invoice PDF...');
      final company = ref.read(currentCompanyProvider);
      if (company == null) {
        _showSnackBar('No company selected', isError: true);
        return;
      }
      final isar = ref.read(isarServiceProvider).isar;
      final imageBytes = await PurchaseInvoiceGenerator.buildImageById(
        invoiceId: invoice.id,
        isar: isar,
        company: company,
      );
      final memoryImage = pw.MemoryImage(imageBytes);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          final document = pw.Document();
          document.addPage(
            pw.Page(
              pageFormat: format,
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Center(
                child: pw.Image(memoryImage, fit: pw.BoxFit.contain),
              ),
            ),
          );
          return document.save();
        },
      );
    } catch (e) {
      _showSnackBar('Error printing invoice: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final company = ref.watch(currentCompanyProvider);

    if (company == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Purchase Invoices')),
        body: const Center(
          child: Text('Please select a company first'),
        ),
      );
    }

    final isar = ref.watch(isarServiceProvider).isar;
    final service = PurchaseInvoiceService(isar);

    return Scaffold(
      drawer: NavigationDrawerHelper.buildNavigationDrawer(
        context,
        ref: ref,
        selectedItem: 'purchases',
      ),
      appBar: AppBar(
        title: const Text('Purchase List'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search Bar and Total Purchase Amount (Side by Side)
          Container(
            padding: const EdgeInsets.all(16),
            color: colorScheme.surface,
            child: Row(
              children: [
                // Search Bar - Half Width
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search invoices...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _refreshInvoices();
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: colorScheme.surface,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _refreshInvoices();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Total Purchase Amount - Half Width
                Expanded(
                  flex: 1,
                  child: FutureBuilder<List<Invoice>>(
                    future: _totalInvoicesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final totalAmount = snapshot.data!.fold<double>(
                            0.0, (sum, invoice) => sum + invoice.grandTotal);
                        return Card(
                          color: colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Purchase',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Rs ${NumberFormat('#,##0.0').format(totalAmount)}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return Card(
                        color: colorScheme.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total Purchase',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Loading...',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Invoice List
          Expanded(
            child: FutureBuilder<List<Invoice>>(
              key: ValueKey('invoices_${_searchQuery}_${company.id}'),
              future: _invoicesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 64, color: colorScheme.error),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading invoices',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final invoices = snapshot.data ?? [];

                if (invoices.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_bag,
                          size: 64,
                          color: colorScheme.onSurfaceVariant.withAlpha(128),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No Purchase Invoices Found'
                              : 'No matching invoices',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isEmpty
                              ? 'Tap + to create your first purchase invoice'
                              : 'Try a different search term',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: invoices.length,
                  itemBuilder: (context, index) {
                    final invoice = invoices[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildInvoiceCard(invoice, colorScheme, service),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PurchaseInvoiceFormScreen(),
            ),
          );
          if (result == true && mounted) {
            _refreshInvoices(); // Use refresh method instead of setState
          }
        },
        backgroundColor: colorScheme.primary,
        tooltip: 'Add Purchase Invoice',
        icon: const Icon(Icons.add, color: Colors.white),
        label:
            const Text('Add Purchase', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildInvoiceCard(
    Invoice invoice,
    ColorScheme colorScheme,
    PurchaseInvoiceService service,
  ) {
    return Dismissible(
        key: Key('invoice_${invoice.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (direction) async {
          return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete Invoice'),
              content: Text(
                'Are you sure you want to delete this purchase invoice?\nAmount: ${_currencyFormat.format(invoice.grandTotal)}',
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
        },
        onDismissed: (direction) async {
          try {
            final isar = ref.read(isarServiceProvider).isar;
            final service = PurchaseInvoiceService(isar);
            await service.deletePurchaseInvoice(invoice.id);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Purchase invoice deleted successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              _refreshInvoices(); // Use refresh method
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error deleting invoice: $e'),
                  backgroundColor: Colors.red,
                ),
              );
              _refreshInvoices(); // Refresh to restore the item
            }
          }
        },
        background: Container(
          alignment: Alignment.centerRight,
          margin: _cardMargin,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(_cardBorderRadius),
          ),
          child: const Icon(
            Icons.delete,
            color: Colors.white,
            size: 32,
          ),
        ),
        child: Card(
          margin: _cardMargin,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PurchaseInvoiceFormScreen(invoiceId: invoice.id),
                ),
              );
              if (result == true && mounted) {
                _refreshInvoices(); // Use refresh method instead of setState
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(invoice.invoiceNumber != null && invoice.invoiceNumber!.trim().isNotEmpty) ? invoice.invoiceNumber!.trim() : '#${invoice.id}'} • ${DateFormat('dd MMM yy').format(invoice.invoiceDate)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Main Row: Supplier and Amount
                  FutureBuilder<Party?>(
                    future: service.getPartyForInvoice(invoice.partyId),
                    builder: (context, snapshot) {
                      final party = snapshot.data;
                      final partyName = party?.name ?? 'Loading...';

                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      partyName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Rs ${NumberFormat('#,##0').format(invoice.grandTotal)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade700,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _shareInvoiceImage(invoice),
                                icon: Icon(
                                  Icons.share,
                                  size: 16,
                                  color: Colors.blue.shade700,
                                ),
                                label: Text(
                                  'Share',
                                  style: TextStyle(color: Colors.blue.shade700),
                                ),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: Colors.blue.shade50,
                                  side: BorderSide(color: Colors.blue.shade200),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () => _printInvoicePdf(invoice),
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
                                  backgroundColor: Colors.deepPurple.shade50,
                                  side: BorderSide(
                                      color: Colors.deepPurple.shade200),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ));
  }
}
