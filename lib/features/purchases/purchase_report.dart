// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/config/providers.dart';
import '../../data/models/company_model.dart';
import '../../data/models/invoice_stock_models.dart';
import '../../data/models/party_model.dart';
import 'services/purchase_invoice_service.dart';

class PurchaseReportScreen extends ConsumerStatefulWidget {
  const PurchaseReportScreen({super.key});

  @override
  ConsumerState<PurchaseReportScreen> createState() =>
      _PurchaseReportScreenState();
}

class _PurchaseReportScreenState extends ConsumerState<PurchaseReportScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;
  Party? _selectedSupplier;
  String _reportType = 'summary'; // summary, detailed, supplier
  final _dateFormat = DateFormat('dd MMM yyyy');
  final _currencyFormat = NumberFormat.currency(symbol: 'PKR ');

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(currentCompanyProvider);
    final isar = ref.watch(isarServiceProvider).isar;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (company == null) {
      return const Scaffold(
        body: Center(child: Text('No company selected')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Reports'),
        backgroundColor: Colors.orange,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () => _generatePDF(company, isar),
            tooltip: 'Generate PDF',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltersSection(colorScheme, isar),
          Expanded(
            child: _buildReportContent(company, isar),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersSection(ColorScheme colorScheme, Isar isar) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
        ),
      ),
      child: Column(
        children: [
          // Report Type Selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report Type',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildReportTypeChip(
                          'summary', 'Summary', Icons.bar_chart),
                      _buildReportTypeChip('detailed', 'Detailed', Icons.list),
                      _buildReportTypeChip(
                          'supplier', 'By Supplier', Icons.people),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Date Range and Supplier Selection
          Row(
            children: [
              // Date Range
              Expanded(
                flex: 2,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Date Range',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => _selectDate(context, true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    border:
                                        Border.all(color: colorScheme.outline),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _fromDate != null
                                        ? _dateFormat.format(_fromDate!)
                                        : 'From Date',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _fromDate != null
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurface
                                              .withOpacity(0.6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                onTap: () => _selectDate(context, false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    border:
                                        Border.all(color: colorScheme.outline),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _toDate != null
                                        ? _dateFormat.format(_toDate!)
                                        : 'To Date',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _toDate != null
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurface
                                              .withOpacity(0.6),
                                    ),
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
              ),
              const SizedBox(width: 12),

              // Supplier Filter
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Supplier',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _selectSupplier(isar),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: colorScheme.outline),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _selectedSupplier?.name ?? 'All Suppliers',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Clear Filters Button
          if (_fromDate != null || _toDate != null || _selectedSupplier != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear, size: 16),
                label:
                    const Text('Clear Filters', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReportTypeChip(String value, String label, IconData icon) {
    final isSelected = _reportType == value;
    return FilterChip(
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _reportType = value;
        });
      },
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : Colors.orange,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isSelected ? Colors.white : Colors.orange,
        ),
      ),
      backgroundColor: Colors.orange.withOpacity(0.1),
      selectedColor: Colors.orange,
      checkmarkColor: Colors.white,
    );
  }

  Widget _buildReportContent(Company company, Isar isar) {
    return FutureBuilder<_PurchaseReportData>(
      future: _loadReportData(company.id, isar),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 48, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
              ],
            ),
          );
        }

        final data = snapshot.data!;

        if (data.invoices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_bag_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No purchase data found',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try adjusting your filters or date range',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        switch (_reportType) {
          case 'summary':
            return _buildSummaryReport(data);
          case 'detailed':
            return _buildDetailedReport(data);
          case 'supplier':
            return _buildSupplierReport(data);
          default:
            return _buildSummaryReport(data);
        }
      },
    );
  }

  Widget _buildSummaryReport(_PurchaseReportData data) {
    final totalAmount =
        data.invoices.fold(0.0, (sum, inv) => sum + inv.grandTotal);
    final avgAmount =
        data.invoices.isNotEmpty ? totalAmount / data.invoices.length : 0.0;

    final supplierCount =
        data.invoices.map((inv) => inv.partyId).toSet().length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary Cards
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _buildSummaryCard(
              'Total Purchases',
              _currencyFormat.format(totalAmount),
              Icons.attach_money,
              Colors.green,
            ),
            _buildSummaryCard(
              'Total Invoices',
              data.invoices.length.toString(),
              Icons.receipt,
              Colors.blue,
            ),
            _buildSummaryCard(
              'Avg Invoice Value',
              _currencyFormat.format(avgAmount),
              Icons.trending_up,
              Colors.orange,
            ),
            _buildSummaryCard(
              'Unique Suppliers',
              supplierCount.toString(),
              Icons.people,
              Colors.purple,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Monthly Breakdown
        _buildMonthlyBreakdown(data),
        const SizedBox(height: 24),

        // Top Suppliers
        _buildTopSuppliers(data),
      ],
    );
  }

  Widget _buildSummaryCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyBreakdown(_PurchaseReportData data) {
    final monthlyData = <String, double>{};

    for (final invoice in data.invoices) {
      final monthKey = DateFormat('MMM yyyy').format(invoice.invoiceDate);
      monthlyData[monthKey] = (monthlyData[monthKey] ?? 0) + invoice.grandTotal;
    }

    final sortedEntries = monthlyData.entries.toList()
      ..sort((a, b) => DateFormat('MMM yyyy')
          .parse(a.key)
          .compareTo(DateFormat('MMM yyyy').parse(b.key)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Purchases',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            ...sortedEntries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: LinearProgressIndicator(
                          value: entry.value / sortedEntries.first.value,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.orange),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currencyFormat.format(entry.value),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSuppliers(_PurchaseReportData data) {
    final supplierTotals = <int, double>{};

    for (final invoice in data.invoices) {
      supplierTotals[invoice.partyId] =
          (supplierTotals[invoice.partyId] ?? 0) + invoice.grandTotal;
    }

    final sortedSuppliers = supplierTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topSuppliers = sortedSuppliers.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top 5 Suppliers',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            ...topSuppliers.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final supplierEntry = entry.value;
              final supplier = data.suppliers[supplierEntry.key];

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.orange.withOpacity(0.2),
                      child: Text(
                        '$rank',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            supplier?.name ?? 'Unknown Supplier',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${data.invoices.where((inv) => inv.partyId == supplierEntry.key).length} invoices',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _currencyFormat.format(supplierEntry.value),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedReport(_PurchaseReportData data) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: data.invoices.length,
      itemBuilder: (context, index) {
        final invoice = data.invoices[index];
        final supplier = data.suppliers[invoice.partyId];

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange.withOpacity(0.2),
              child: const Icon(Icons.shopping_bag,
                  color: Colors.orange, size: 20),
            ),
            title: Text(
              'Purchase #${invoice.id}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(supplier?.name ?? 'Unknown Supplier'),
                Text(
                  _dateFormat.format(invoice.invoiceDate),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _currencyFormat.format(invoice.grandTotal),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(invoice.status ?? 'Unknown')
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    invoice.status ?? 'Unknown',
                    style: TextStyle(
                      fontSize: 10,
                      color: _getStatusColor(invoice.status ?? 'Unknown'),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSupplierReport(_PurchaseReportData data) {
    final supplierData = <int, List<Invoice>>{};

    for (final invoice in data.invoices) {
      supplierData.putIfAbsent(invoice.partyId, () => []).add(invoice);
    }

    final sortedSuppliers = supplierData.entries.toList()
      ..sort((a, b) {
        final aTotal = a.value.fold(0.0, (sum, inv) => sum + inv.grandTotal);
        final bTotal = b.value.fold(0.0, (sum, inv) => sum + inv.grandTotal);
        return bTotal.compareTo(aTotal);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedSuppliers.length,
      itemBuilder: (context, index) {
        final supplierEntry = sortedSuppliers[index];
        final supplier = data.suppliers[supplierEntry.key];
        final invoices = supplierEntry.value;
        final total = invoices.fold(0.0, (sum, inv) => sum + inv.grandTotal);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange.withOpacity(0.2),
              child: const Icon(Icons.person, color: Colors.orange),
            ),
            title: Text(
              supplier?.name ?? 'Unknown Supplier',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text('${invoices.length} invoices'),
            trailing: Text(
              _currencyFormat.format(total),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            children: invoices
                .map((invoice) => ListTile(
                      dense: true,
                      title: Text(
                        'Purchase #${invoice.id}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        _dateFormat.format(invoice.invoiceDate),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(
                        _currencyFormat.format(invoice.grandTotal),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  Future<void> _selectDate(BuildContext context, bool isFromDate) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = date;
        } else {
          _toDate = date;
        }
      });
    }
  }

  Future<void> _selectSupplier(Isar isar) async {
    final suppliers = await isar.partys
        .filter()
        .partyTypeEqualTo(PartyType.supplier)
        .findAll();

    if (!mounted) return;

    final selected = await showDialog<Party?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Supplier'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: suppliers.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  title: const Text('All Suppliers'),
                  onTap: () => Navigator.pop(context, null),
                );
              }

              final supplier = suppliers[index - 1];
              return ListTile(
                title: Text(supplier.name),
                onTap: () => Navigator.pop(context, supplier),
              );
            },
          ),
        ),
      ),
    );

    if (selected != _selectedSupplier) {
      setState(() {
        _selectedSupplier = selected;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _selectedSupplier = null;
    });
  }

  Future<_PurchaseReportData> _loadReportData(int companyId, Isar isar) async {
    final service = PurchaseInvoiceService(isar);
    var invoices = await service.getAllPurchaseInvoices(companyId);

    // Apply date filters
    if (_fromDate != null) {
      invoices = invoices
          .where((inv) =>
              inv.invoiceDate.isAfter(_fromDate!) ||
              inv.invoiceDate.isAtSameMomentAs(_fromDate!))
          .toList();
    }

    if (_toDate != null) {
      invoices = invoices
          .where((inv) =>
              inv.invoiceDate.isBefore(_toDate!) ||
              inv.invoiceDate.isAtSameMomentAs(_toDate!))
          .toList();
    }

    // Apply supplier filter
    if (_selectedSupplier != null) {
      invoices = invoices
          .where((inv) => inv.partyId == _selectedSupplier!.id)
          .toList();
    }

    // Load suppliers
    final supplierIds = invoices.map((inv) => inv.partyId).toSet();
    final suppliers = <int, Party>{};

    for (final id in supplierIds) {
      final supplier = await isar.partys.get(id);
      if (supplier != null) {
        suppliers[id] = supplier;
      }
    }

    return _PurchaseReportData(
      invoices: invoices,
      suppliers: suppliers,
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _generatePDF(Company company, Isar isar) async {
    final data = await _loadReportData(company.id, isar);

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Header(
                level: 0,
                child: pw.Text(
                  'Purchase Report - ${company.name}',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 20),

              // Date Range
              if (_fromDate != null || _toDate != null)
                pw.Text(
                  'Period: ${_fromDate != null ? _dateFormat.format(_fromDate!) : 'Beginning'} to ${_toDate != null ? _dateFormat.format(_toDate!) : 'Now'}',
                  style: const pw.TextStyle(fontSize: 12),
                ),

              if (_selectedSupplier != null)
                pw.Text(
                  'Supplier: ${_selectedSupplier!.name}',
                  style: const pw.TextStyle(fontSize: 12),
                ),

              pw.SizedBox(height: 20),

              // Summary
              pw.Text(
                'Summary',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),

              pw.Text('Total Invoices: ${data.invoices.length}'),
              pw.Text(
                  'Total Amount: ${_currencyFormat.format(data.invoices.fold(0.0, (sum, inv) => sum + inv.grandTotal))}'),

              pw.SizedBox(height: 20),

              // Details Table
              pw.Text(
                'Invoice Details',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),

              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Invoice #',
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Date',
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Supplier',
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Amount',
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  ...data.invoices.take(20).map((invoice) => pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('#${invoice.id}'),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                                _dateFormat.format(invoice.invoiceDate)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                                data.suppliers[invoice.partyId]?.name ??
                                    'Unknown'),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                                _currencyFormat.format(invoice.grandTotal)),
                          ),
                        ],
                      )),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }
}

class _PurchaseReportData {
  final List<Invoice> invoices;
  final Map<int, Party> suppliers;

  _PurchaseReportData({
    required this.invoices,
    required this.suppliers,
  });
}
