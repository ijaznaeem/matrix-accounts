// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/config/providers.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../data/models/account_models.dart';
import '../../../data/models/party_model.dart';

class PartyLedgerScreen extends ConsumerStatefulWidget {
  final Party party;

  const PartyLedgerScreen({super.key, required this.party});

  @override
  ConsumerState<PartyLedgerScreen> createState() => _PartyLedgerScreenState();
}

class _PartyLedgerScreenState extends ConsumerState<PartyLedgerScreen> {
  String _selectedFilter = 'All Time';
  DateTime? _startDate;
  DateTime? _endDate;
  final _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    _setDateRange('All Time');
  }

  void _setDateRange(String filter) {
    final now = DateTime.now();

    switch (filter) {
      case 'Today':
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'Weekly':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'Monthly':
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        break;
      case 'Day to Day':
        _showDateRangePicker();
        return;
      default:
        _startDate = null;
        _endDate = null;
    }

    setState(() {
      _selectedFilter = filter;
    });
  }

  void _showDateRangePicker() async {
    final now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange:
          _startDate != null && _endDate != null && !_endDate!.isAfter(now)
              ? DateTimeRange(start: _startDate!, end: _endDate!)
              : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
        _selectedFilter = 'Day to Day';
      });
    }
  }

  List<AccountTransaction> _filterTransactions(
      List<AccountTransaction> transactions) {
    if (_startDate == null || _endDate == null) {
      return transactions;
    }

    return transactions.where((txn) {
      return txn.transactionDate
              .isAfter(_startDate!.subtract(const Duration(days: 1))) &&
          txn.transactionDate.isBefore(_endDate!.add(const Duration(days: 1)));
    }).toList();
  }

  Future<List<AccountTransaction>> _getPartyLedgerTransactions(
      int companyId) async {
    final isar = ref.read(isarServiceProvider).isar;

    final accountCode = (widget.party.partyType == PartyType.customer ||
            widget.party.partyType == PartyType.both)
        ? '1200'
        : '2000';

    final account = await isar.accounts
        .filter()
        .companyIdEqualTo(companyId)
        .codeEqualTo(accountCode)
        .findFirst();

    if (account == null) return [];

    return isar.accountTransactions
        .filter()
        .companyIdEqualTo(companyId)
        .accountIdEqualTo(account.id)
        .partyIdEqualTo(widget.party.id)
        .sortByTransactionDateDesc()
        .findAll();
  }

  double _calculatePartyBalance(List<AccountTransaction> transactions) {
    return transactions.fold<double>(
      0,
      (sum, txn) => sum + txn.debit - txn.credit,
    );
  }

  Map<int, double> _buildPartyRunningBalanceMap(
      List<AccountTransaction> allTransactionsDesc) {
    final balancesByTxnId = <int, double>{};
    var runningBalance = _calculatePartyBalance(allTransactionsDesc);

    for (final txn in allTransactionsDesc) {
      balancesByTxnId[txn.id] = runningBalance;
      runningBalance -= (txn.debit - txn.credit);
    }

    return balancesByTxnId;
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

  Future<void> _exportToPDF({
    required List<AccountTransaction> transactions,
    required List<AccountTransaction> allTransactions,
    required double currentBalance,
  }) async {
    try {
      _showSnackBar('Generating PDF...');

      final company = ref.read(currentCompanyProvider);
      final settings = ref.read(settingsProvider);
      final currencySymbol =
          SettingsConstants.currencySymbols[settings.defaultCurrency] ??
              settings.defaultCurrency;

      final party = widget.party;
      final partyTypeLabel = party.partyType == PartyType.customer
          ? 'Customer'
          : party.partyType == PartyType.supplier
              ? 'Supplier'
              : 'Customer / Supplier';

      // Sort filtered transactions oldest → newest for ledger display
      final sortedTxns = [...transactions]
        ..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));

      // Opening balance = sum of all transactions strictly before the filter start
      double openingBalance = 0;
      if (_startDate != null) {
        final beforePeriod = allTransactions
            .where((t) => t.transactionDate.isBefore(_startDate!))
            .toList();
        openingBalance =
            beforePeriod.fold(0.0, (s, t) => s + t.debit - t.credit);
      }

      // Build per-row running balance starting from openingBalance
      double runBalance = openingBalance;
      final runningBalanceMap = <int, double>{};
      for (final txn in sortedTxns) {
        runBalance += txn.debit - txn.credit;
        runningBalanceMap[txn.id] = runBalance;
      }

      // Period label
      String periodText = _selectedFilter;
      if (_startDate != null && _endDate != null) {
        periodText +=
            ' (${_dateFormat.format(_startDate!)} – ${_dateFormat.format(_endDate!)})';
      }

      // Number helpers
      final numFmt = NumberFormat('#,##0.00');
      String fmt(double v) => numFmt.format(v);
      String fmtC(double v) => '$currencySymbol ${fmt(v)}';

      // Colour palette
      const headerBg = PdfColor(0.102, 0.137, 0.494); // indigo 900
      const subHeaderBg = PdfColor(0.910, 0.918, 0.965); // indigo 50
      const altRowBg = PdfColor(0.980, 0.980, 0.980); // grey 50
      const borderColor = PdfColor(0.741, 0.741, 0.741); // grey 400
      const debitGreen = PdfColor(0.106, 0.369, 0.125); // green 900
      const creditRed = PdfColor(0.718, 0.110, 0.110); // red 900
      const balanceRedBg = PdfColor(1.0, 0.922, 0.933);
      const balanceGreenBg = PdfColor(0.910, 0.969, 0.914);

      // Column proportions: Date | Description | Debit | Credit | Balance
      const colWidths = {
        0: pw.FlexColumnWidth(1.6),
        1: pw.FlexColumnWidth(3.2),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(1.5),
        4: pw.FlexColumnWidth(1.8),
      };

      pw.Widget hdr(String t, {pw.TextAlign a = pw.TextAlign.left}) =>
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: pw.Text(
              t,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
              ),
              textAlign: a,
            ),
          );

      pw.Widget cell(String t,
              {pw.TextAlign a = pw.TextAlign.left,
              pw.TextStyle? style,
              double fs = 9}) =>
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: pw.Text(
              t,
              style:
                  style ?? pw.TextStyle(fontSize: fs, color: PdfColors.black),
              textAlign: a,
            ),
          );

      // Sub-totals for footer row
      final totalDebit = sortedTxns.fold(0.0, (s, t) => s + t.debit);
      final totalCredit = sortedTxns.fold(0.0, (s, t) => s + t.credit);

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          header: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // ── Top bar: title + company ──────────────────────────────
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: const pw.BoxDecoration(
                    color: headerBg,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'PARTY LEDGER',
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            company?.name ?? '',
                            style: const pw.TextStyle(
                                color: PdfColors.grey300, fontSize: 10),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Period: $periodText',
                            style: const pw.TextStyle(
                                color: PdfColors.grey300, fontSize: 9),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Generated: ${_dateFormat.format(DateTime.now())}',
                            style: const pw.TextStyle(
                                color: PdfColors.grey300, fontSize: 9),
                          ),
                          if (ctx.pageNumber > 1)
                            pw.Text(
                              'Page ${ctx.pageNumber}',
                              style: const pw.TextStyle(
                                  color: PdfColors.grey300, fontSize: 9),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),
                // ── Party details card ────────────────────────────────────
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: borderColor),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(4)),
                    color: subHeaderBg,
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Left: party info
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              party.name,
                              style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              partyTypeLabel,
                              style: const pw.TextStyle(
                                  fontSize: 9, color: PdfColors.grey700),
                            ),
                            if (party.phone != null &&
                                party.phone!.isNotEmpty) ...[
                              pw.SizedBox(height: 2),
                              pw.Text('Phone: ${party.phone}',
                                  style: const pw.TextStyle(fontSize: 9)),
                            ],
                            if (party.email != null &&
                                party.email!.isNotEmpty) ...[
                              pw.SizedBox(height: 2),
                              pw.Text('Email: ${party.email}',
                                  style: const pw.TextStyle(fontSize: 9)),
                            ],
                            if (party.address != null &&
                                party.address!.isNotEmpty) ...[
                              pw.SizedBox(height: 2),
                              pw.Text('Address: ${party.address}',
                                  style: const pw.TextStyle(fontSize: 9)),
                            ],
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 16),
                      // Right: balance box
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: pw.BoxDecoration(
                          color: currentBalance > 0
                              ? balanceRedBg
                              : currentBalance < 0
                                  ? balanceGreenBg
                                  : altRowBg,
                          border: pw.Border.all(
                            color: currentBalance > 0
                                ? const PdfColor(0.937, 0.604, 0.604)
                                : currentBalance < 0
                                    ? const PdfColor(0.647, 0.839, 0.655)
                                    : borderColor,
                          ),
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              'Current Balance',
                              style: const pw.TextStyle(
                                  fontSize: 8, color: PdfColors.grey700),
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              fmtC(currentBalance.abs()),
                              style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold,
                                color: currentBalance > 0
                                    ? creditRed
                                    : currentBalance < 0
                                        ? debitGreen
                                        : PdfColors.grey700,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              currentBalance > 0
                                  ? 'RECEIVABLE'
                                  : currentBalance < 0
                                      ? 'CREDIT'
                                      : 'CLEARED',
                              style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                                color: currentBalance > 0
                                    ? creditRed
                                    : currentBalance < 0
                                        ? debitGreen
                                        : PdfColors.grey700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
              ],
            );
          },
          build: (pw.Context ctx) {
            if (sortedTxns.isEmpty) {
              return [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(24),
                  child: pw.Text(
                    'No transactions found for the selected period.',
                    style: const pw.TextStyle(color: PdfColors.grey600),
                  ),
                ),
              ];
            }

            return [
              pw.Table(
                border: pw.TableBorder.all(color: borderColor, width: 0.5),
                columnWidths: colWidths,
                children: [
                  // ── Column header row ─────────────────────────────────
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: headerBg),
                    children: [
                      hdr('Date'),
                      hdr('Description'),
                      hdr('Debit', a: pw.TextAlign.right),
                      hdr('Credit', a: pw.TextAlign.right),
                      hdr('Balance', a: pw.TextAlign.right),
                    ],
                  ),
                  // ── Opening balance row (only when period is filtered) ─
                  if (_startDate != null)
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: subHeaderBg),
                      children: [
                        cell(''),
                        cell('Opening Balance',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 9)),
                        cell('', a: pw.TextAlign.right),
                        cell('', a: pw.TextAlign.right),
                        cell(fmtC(openingBalance),
                            a: pw.TextAlign.right,
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ],
                    ),
                  // ── Data rows ─────────────────────────────────────────
                  ...sortedTxns.asMap().entries.map((entry) {
                    final i = entry.key;
                    final txn = entry.value;
                    final balance = runningBalanceMap[txn.id] ?? 0;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                          color: i % 2 == 1 ? altRowBg : PdfColors.white),
                      children: [
                        cell(_dateFormat.format(txn.transactionDate)),
                        cell(_buildLedgerDescription(txn)),
                        cell(
                          txn.debit > 0 ? fmt(txn.debit) : '',
                          a: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: 9, color: debitGreen),
                        ),
                        cell(
                          txn.credit > 0 ? fmt(txn.credit) : '',
                          a: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: 9, color: creditRed),
                        ),
                        cell(
                          fmtC(balance),
                          a: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: balance > 0
                                ? creditRed
                                : balance < 0
                                    ? debitGreen
                                    : PdfColors.grey700,
                          ),
                        ),
                      ],
                    );
                  }),
                  // ── Totals row ────────────────────────────────────────
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: subHeaderBg),
                    children: [
                      cell(''),
                      cell('TOTAL',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      cell(fmt(totalDebit),
                          a: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                              color: debitGreen)),
                      cell(fmt(totalCredit),
                          a: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                              color: creditRed)),
                      cell(fmtC(runBalance),
                          a: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                              color: runBalance > 0
                                  ? creditRed
                                  : runBalance < 0
                                      ? debitGreen
                                      : PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
            ];
          },
        ),
      );

      final tempDir = await getTemporaryDirectory();
      final file =
          File('${tempDir.path}/ledger_${party.name.replaceAll(' ', '_')}.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles([XFile(file.path)],
          subject: '${party.name} - Ledger Report');
      _showSnackBar('Ledger exported successfully');
    } catch (e) {
      _showSnackBar('Error exporting ledger: $e', isError: true);
    }
  }

  String _buildLedgerDescription(AccountTransaction txn) {
    final parts = <String>[];
    if (txn.description != null && txn.description!.isNotEmpty) {
      parts.add(txn.description!);
    } else {
      parts.add(_getTransactionTypeLabel(txn.transactionType));
    }
    if (txn.referenceNo != null && txn.referenceNo!.isNotEmpty) {
      parts.add('Ref: ${txn.referenceNo}');
    }
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(currentCompanyProvider);
    final settings = ref.watch(settingsProvider);
    final currencySymbol =
        SettingsConstants.currencySymbols[settings.defaultCurrency] ??
            settings.defaultCurrency;

    if (company == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Party Ledger')),
        body: const Center(child: Text('No company selected')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.party.name} - Ledger'),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: _setDateRange,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'All Time', child: Text('All Time')),
              const PopupMenuItem(value: 'Today', child: Text('Today')),
              const PopupMenuItem(value: 'Weekly', child: Text('This Week')),
              const PopupMenuItem(value: 'Monthly', child: Text('This Month')),
              const PopupMenuItem(
                  value: 'Day to Day', child: Text('Custom Range')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<AccountTransaction>>(
        future: _getPartyLedgerTransactions(company.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final allTransactions = snapshot.data ?? [];
          final filteredTransactions = _filterTransactions(allTransactions);
          final balancesByTxnId = _buildPartyRunningBalanceMap(allTransactions);

          if (allTransactions.isEmpty) {
            return _buildEmptyState();
          }

          final totalBalance = _calculatePartyBalance(allTransactions);

          return Column(
            children: [
              _buildFilterHeader(),
              _buildBalanceCard(totalBalance, currencySymbol),
              if (filteredTransactions.isEmpty && _selectedFilter != 'All Time')
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.filter_list_off,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No transactions found for $_selectedFilter',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredTransactions.length,
                    itemBuilder: (context, index) {
                      final txn = filteredTransactions[index];
                      return _buildTransactionCard(
                        txn,
                        currencySymbol,
                        balancesByTxnId[txn.id] ?? 0,
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Filter: $_selectedFilter${_selectedFilter == 'Day to Day' && _startDate != null ? ' (${_dateFormat.format(_startDate!)} - ${_dateFormat.format(_endDate!)})' : ''}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final company = ref.read(currentCompanyProvider);
              if (company != null) {
                final allTransactions =
                    await _getPartyLedgerTransactions(company.id);
                final filteredTransactions =
                    _filterTransactions(allTransactions);
                final currentBalance = _calculatePartyBalance(allTransactions);

                await _exportToPDF(
                  transactions: filteredTransactions,
                  allTransactions: allTransactions,
                  currentBalance: currentBalance,
                );
              }
            },
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(double balance, String currencySymbol) {
    final isReceivable = balance > 0;
    final isPayable = balance < 0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isReceivable
              ? [Colors.red.shade600, Colors.red.shade700]
              : isPayable
                  ? [Colors.green.shade600, Colors.green.shade700]
                  : [Colors.grey.shade600, Colors.grey.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isReceivable
                    ? Colors.red
                    : isPayable
                        ? Colors.green
                        : Colors.grey)
                .withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Current Balance',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              Icon(
                isReceivable
                    ? Icons.trending_up
                    : isPayable
                        ? Icons.trending_down
                        : Icons.trending_flat,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$currencySymbol${balance.abs().toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isReceivable
                ? 'RECEIVABLE'
                : isPayable
                    ? 'CREDIT'
                    : 'CLEARED',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(
    AccountTransaction txn,
    String currencySymbol,
    double runningBalance,
  ) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final isDebit = txn.debit > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        txn.description ?? '',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getTransactionTypeLabel(txn.transactionType),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isDebit ? '+' : '-'}$currencySymbol${(isDebit ? txn.debit : txn.credit).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDebit
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Balance: $currencySymbol${runningBalance.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  dateFormat.format(txn.transactionDate),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 16),
                if (txn.referenceNo != null && txn.referenceNo!.isNotEmpty) ...[
                  Icon(Icons.receipt, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    txn.referenceNo!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getTransactionTypeLabel(TransactionType type) {
    switch (type) {
      case TransactionType.saleInvoice:
        return 'Sale Invoice';
      case TransactionType.saleReturn:
        return 'Sale Return';
      case TransactionType.paymentIn:
        return 'Payment Received';
      case TransactionType.purchaseInvoice:
        return 'Purchase Invoice';
      case TransactionType.purchaseReturn:
        return 'Purchase Return';
      case TransactionType.paymentOut:
        return 'Payment Made';
      case TransactionType.journalEntry:
        return 'Journal Entry';
      case TransactionType.expense:
        return 'Expense';
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No Transactions Yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Transaction history will appear here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
