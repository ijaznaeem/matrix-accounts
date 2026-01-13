import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/config/providers.dart';
import '../../../core/widgets/navigation_drawer_helper.dart';
import '../../../data/models/invoice_stock_models.dart';
import '../../../data/models/party_model.dart';
import '../services/purchase_invoice_service.dart';
import '../services/purchase_invoice_generator.dart';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _deleteInvoice(Invoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: Text(
          'Are you sure you want to delete this purchase invoice?\nAmount: ${_currencyFormat.format(invoice.grandTotal)}',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

    if (confirmed == true && mounted) {
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
          setState(() {}); // Refresh list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting invoice: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _printInvoice(Invoice invoice) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating PDF for printing...')),
      );

      final isar = ref.read(isarServiceProvider).isar;
      final service = PurchaseInvoiceService(isar);
      final company = ref.read(currentCompanyProvider);

      if (company == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No company selected')),
        );
        return;
      }

      // Get required data
      final supplier = await service.getPartyForInvoice(invoice.partyId);
      final transaction = await service.getTransactionForInvoice(invoice.id);

      if (supplier == null || transaction == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load invoice data')),
        );
        return;
      }

      // Get transaction lines
      final transactionLines =
          await service.getTransactionLines(transaction.id);
      final lineItems = transactionLines
          .map((line) => {
                'productName': line.description ?? 'Unknown Product',
                'quantity': line.quantity,
                'rate': line.unitPrice,
                'amount': line.quantity * line.unitPrice,
              })
          .toList();

      // Generate PDF
      final pdfBytes =
          await PurchaseInvoiceGenerator.generatePurchaseInvoicePdf(
        company: company,
        supplier: supplier,
        invoice: invoice,
        transaction: transaction,
        lineItems: lineItems,
      );

      // Print PDF
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: 'purchase_invoice_${transaction.referenceNo}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error printing invoice: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareInvoice(Invoice invoice) async {
    try {
      final isar = ref.read(isarServiceProvider).isar;
      final service = PurchaseInvoiceService(isar);
      final company = ref.read(currentCompanyProvider);

      if (company == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No company selected')),
        );
        return;
      }

      // Get required data
      final supplier = await service.getPartyForInvoice(invoice.partyId);
      final transaction = await service.getTransactionForInvoice(invoice.id);

      if (supplier == null || transaction == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load invoice data')),
        );
        return;
      }

      // Get transaction lines
      final transactionLines =
          await service.getTransactionLines(transaction.id);
      final lineItems = transactionLines
          .map((line) => {
                'productName': line.description ?? 'Unknown Product',
                'quantity': line.quantity,
                'rate': line.unitPrice,
                'amount': line.quantity * line.unitPrice,
              })
          .toList();

      // Show share options
      await PurchaseInvoiceGenerator.sharePurchaseInvoice(
        context: context,
        company: company,
        supplier: supplier,
        invoice: invoice,
        transaction: transaction,
        lineItems: lineItems,
      );
    } catch (e) {
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
        backgroundColor: Colors.blueAccent,
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
                                setState(() => _searchQuery = '');
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
                      setState(() => _searchQuery = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Total Purchase Amount - Half Width
                Expanded(
                  flex: 1,
                  child: FutureBuilder<List<Invoice>>(
                    future: service.getAllPurchaseInvoices(company.id),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final totalAmount = snapshot.data!.fold<double>(
                            0.0, (sum, invoice) => sum + invoice.grandTotal);
                        return Card(
                          color: Colors.blue.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Purchase',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Rs ${NumberFormat('#,##0.0').format(totalAmount)}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.blue.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total Purchase',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Loading...',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.blue.shade800,
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
              future: _searchQuery.isEmpty
                  ? service.getAllPurchaseInvoices(company.id)
                  : service.searchPurchaseInvoices(company.id, _searchQuery),
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
            setState(() {}); // Refresh list
          }
        },
        backgroundColor: Colors.blueAccent,
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
        direction: DismissDirection.startToEnd,
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
              setState(() {}); // Refresh list
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error deleting invoice: $e'),
                  backgroundColor: Colors.red,
                ),
              );
              setState(() {}); // Refresh list to restore the item
            }
          }
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.delete,
                color: Colors.white,
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        child: Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
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
                setState(() {}); // Refresh list
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Supplier Name (left) + Date (right)
                  Row(
                    children: [
                      Expanded(
                        child: FutureBuilder<Party?>(
                          future: service.getPartyForInvoice(invoice.partyId),
                          builder: (context, snapshot) {
                            final partyName =
                                snapshot.data?.name ?? 'Loading...';
                            return Text(
                              partyName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      ),
                      Text(
                        DateFormat('dd MMM yy').format(invoice.invoiceDate),
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Row 2: Amount (left) + Status Badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Rs ${NumberFormat('#,##0').format(invoice.grandTotal)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'UNPAID',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Row 3: Due Balance (left) + Overdue Status (right)
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet,
                        size: 12,
                        color: Colors.red.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Due: Rs ${NumberFormat('#,##0').format(invoice.grandTotal)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.red.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Overdue',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ));
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'overdue':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }
}
