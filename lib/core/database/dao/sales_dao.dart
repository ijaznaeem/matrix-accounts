import 'dart:convert';

import 'package:isar/isar.dart';

import '../../../data/models/invoice_stock_models.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/payment_models.dart';
import '../../../data/models/sync_change_model.dart';
import '../../../data/models/transaction_model.dart';
import 'account_dao.dart';
import 'party_dao.dart';
import 'payment_dao.dart';

class SalesDao {
  final Isar isar;
  late final AccountDao _accountDao;
  late final PaymentDao _paymentDao;
  late final PartyDao _partyDao;

  SalesDao(this.isar) {
    _accountDao = AccountDao(isar);
    _paymentDao = PaymentDao(isar);
    _partyDao = PartyDao(isar);
  }

  Future<Invoice?> getInvoiceById(int invoiceId) async {
    return await isar.invoices.get(invoiceId);
  }

  Future<Transaction?> getTransactionForInvoice(int invoiceId) async {
    final invoice = await isar.invoices.get(invoiceId);
    if (invoice == null) return null;
    return await isar.transactions.get(invoice.transactionId);
  }

  Future<List<TransactionLine>> getTransactionLines(int transactionId) async {
    return await isar.transactionLines
        .filter()
        .transactionIdEqualTo(transactionId)
        .findAll();
  }

  Future<void> createSaleInvoice({
    required int companyId,
    required Party customer,
    required DateTime date,
    required String referenceNo,
    required List<SaleLineInput> lines,
    List<PaymentLineInput>? paymentLines, // NEW: payment lines
    int? userId,
  }) async {
    final transaction = Transaction()
      ..companyId = companyId
      ..type = TransactionType.sale
      ..date = date
      ..referenceNo = referenceNo
      ..partyId = customer.id
      ..totalAmount = lines.fold(0.0, (sum, l) => sum + (l.qty * l.rate))
      ..createdByUserId = userId;

    await isar.writeTxn(() async {
      final txnId = await isar.transactions.put(transaction);

      // Record sync change for created transaction
      await isar.syncChanges.put(SyncChange()
        ..companyId = companyId
        ..table = 'transactions'
        ..operation = ChangeOperation.create
        ..recordId = txnId
        ..data = jsonEncode({
          'id': txnId,
          'company_id': companyId,
          'type': 'sale',
          'date': date.toIso8601String(),
          'reference_no': referenceNo,
          'party_id': customer.id,
          'total_amount': transaction.totalAmount,
          'is_posted': false,
        })
        ..createdAt = DateTime.now()
        ..synced = false);

      // Calculate customer's current balance (opening balance for this invoice)
      final currentBalance = await _partyDao.getPartyBalance(
        partyId: customer.id,
        companyId: companyId,
      );

      // Calculate total payment amount
      final totalPayment =
          paymentLines?.fold(0.0, (sum, p) => sum + p.amount) ?? 0.0;

      final invoice = Invoice()
        ..companyId = companyId
        ..transactionId = txnId
        ..invoiceType = InvoiceType.sale
        ..partyId = customer.id
        ..invoiceDate = date
        ..grandTotal = transaction.totalAmount
        ..status = 'Pending'
        ..previousBalance = currentBalance // Opening balance
        ..paidAmount = totalPayment // Payment on this invoice
        ..remainingBalance = currentBalance +
            transaction.totalAmount -
            totalPayment; // Closing balance

      final invoiceId = await isar.invoices.put(invoice);

      // Record sync change for created invoice
      final _createData = jsonEncode({
        'id': invoiceId,
        'company_id': companyId,
        'transaction_id': txnId,
        'invoice_type': 'sale',
        'party_id': customer.id,
        'invoice_date': date.toIso8601String(),
        'grand_total': invoice.grandTotal,
        'status': invoice.status,
        'previous_balance': invoice.previousBalance,
        'paid_amount': invoice.paidAmount,
        'remaining_balance': invoice.remainingBalance,
      });
      final _createChange = SyncChange()
        ..companyId = companyId
        ..table = 'invoices'
        ..operation = ChangeOperation.create
        ..recordId = invoiceId
        ..data = _createData
        ..createdAt = DateTime.now()
        ..synced = false;
      await isar.syncChanges.put(_createChange);

      for (final l in lines) {
        final line = TransactionLine()
          ..transactionId = txnId
          ..productId = l.productId
          ..quantity = l.qty
          ..unitPrice = l.rate
          ..lineAmount = l.qty * l.rate;

        final lineId = await isar.transactionLines.put(line);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'transaction_lines'
          ..operation = ChangeOperation.create
          ..recordId = lineId
          ..data = jsonEncode({
            'id': lineId,
            'transaction_id': txnId,
            'product_id': l.productId,
            'quantity': l.qty,
            'unit_price': l.rate,
            'line_amount': l.qty * l.rate,
          })
          ..createdAt = DateTime.now()
          ..synced = false);

        // Calculate COGS using weighted average cost
        final avgCost = await _calculateAverageCost(companyId, l.productId);
        final unitCost = avgCost;
        final totalCost = l.qty * unitCost;

        final stock = StockLedger()
          ..companyId = companyId
          ..productId = l.productId
          ..date = date
          ..movementType = StockMovementType.outSale
          ..quantityDelta = -l.qty
          ..unitCost = unitCost
          ..totalCost = totalCost
          ..transactionId = txnId
          ..invoiceId = invoiceId;

        final stockId = await isar.stockLedgers.put(stock);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'stock_ledgers'
          ..operation = ChangeOperation.create
          ..recordId = stockId
          ..data = jsonEncode({
            'id': stockId,
            'company_id': companyId,
            'product_id': l.productId,
            'date': date.toIso8601String(),
            'movement_type': 'outSale',
            'quantity_delta': -l.qty,
            'unit_cost': unitCost,
            'total_cost': totalCost,
            'transaction_id': txnId,
            'invoice_id': invoiceId,
          })
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Calculate total COGS for this sale
      double totalCOGS = 0;
      for (final l in lines) {
        final avgCost = await _calculateAverageCost(companyId, l.productId);
        totalCOGS += l.qty * avgCost;
      }

      // Record accounting transaction - invoice amount
      await _accountDao.recordSaleInvoiceInternal(
        companyId: companyId,
        invoiceId: invoiceId,
        customerId: customer.id,
        customerName: customer.name,
        invoiceDate: date,
        invoiceNo: referenceNo,
        totalAmount: transaction.totalAmount,
      );

      // Record COGS accounting
      if (totalCOGS > 0) {
        await _accountDao.recordCOGSInternal(
          companyId: companyId,
          invoiceId: invoiceId,
          saleDate: date,
          invoiceNo: referenceNo,
          cogsAmount: totalCOGS,
        );
      }

      // Record payment if provided
      if (paymentLines != null && paymentLines.isNotEmpty) {
        int microsecondsDelay = 0;
        for (final paymentLine in paymentLines) {
          if (paymentLine.amount <= 0) continue;

          // Get payment account to determine type
          final paymentAccount = await _paymentDao
              .getPaymentAccountById(paymentLine.paymentAccountId);
          if (paymentAccount == null) {
            throw Exception(
              'Payment account (ID: ${paymentLine.paymentAccountId}) not found. '
              'Please verify your Cash/Bank account is set up under Settings.',
            );
          }

          // Determine account code based on account type
          final String accountCode;
          switch (paymentAccount.accountType) {
            case PaymentAccountType.cash:
              accountCode = '1000';
            case PaymentAccountType.bank:
              accountCode = '1100';
          }

          // Add microsecond delay for unique timestamps
          await Future.delayed(Duration(microseconds: microsecondsDelay));
          microsecondsDelay += 1000;

          final paymentDate =
              date.add(Duration(microseconds: microsecondsDelay));

          await _accountDao.recordSaleInvoicePaymentInternal(
            companyId: companyId,
            invoiceId: invoiceId,
            customerId: customer.id,
            customerName: customer.name,
            paymentDate: paymentDate,
            invoiceNo: referenceNo,
            amount: paymentLine.amount,
            accountCode: accountCode,
          );
        }
      }
    });
  }

  Future<void> updateSaleInvoice({
    required int invoiceId,
    required int companyId,
    required Party customer,
    required DateTime date,
    required String referenceNo,
    required List<SaleLineInput> lines,
    List<PaymentLineInput>? paymentLines, // NEW: payment lines
    int? userId,
  }) async {
    final invoice = await isar.invoices.get(invoiceId);
    if (invoice == null) throw Exception('Invoice not found');

    final transactionId = invoice.transactionId;

    await isar.writeTxn(() async {
      // Update transaction
      final transaction = await isar.transactions.get(transactionId);
      if (transaction != null) {
        transaction.date = date;
        transaction.referenceNo = referenceNo;
        transaction.partyId = customer.id;
        transaction.totalAmount =
            lines.fold(0.0, (sum, l) => sum + (l.qty * l.rate));
        await isar.transactions.put(transaction);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'transactions'
          ..operation = ChangeOperation.update
          ..recordId = transactionId
          ..data = jsonEncode({
            'id': transactionId,
            'company_id': companyId,
            'type': 'sale',
            'date': date.toIso8601String(),
            'reference_no': referenceNo,
            'party_id': customer.id,
            'total_amount': transaction.totalAmount,
            'is_posted': transaction.isPosted,
          })
          ..createdAt = DateTime.now()
          ..synced = false);
      }
      // We need to exclude this invoice's effect and recalculate
      final currentBalance = await _partyDao.getPartyBalance(
        partyId: customer.id,
        companyId: companyId,
      );

      // Adjust for the old invoice effect to get the balance before this invoice
      final oldOpeningBalance = currentBalance -
          invoice.grandTotal +
          invoice.paidAmount -
          invoice.previousBalance;

      // Calculate total payment amount
      final totalPayment =
          paymentLines?.fold(0.0, (sum, p) => sum + p.amount) ?? 0.0;
      final newTotal = lines.fold(0.0, (sum, l) => sum + (l.qty * l.rate));

      // Update invoice with balance tracking
      invoice.partyId = customer.id;
      invoice.invoiceDate = date;
      invoice.grandTotal = newTotal;
      invoice.previousBalance =
          oldOpeningBalance; // Opening balance before invoice
      invoice.paidAmount = totalPayment; // Payment on this invoice
      invoice.remainingBalance =
          oldOpeningBalance + newTotal - totalPayment; // Closing balance
      await isar.invoices.put(invoice);

      // Record sync change for updated invoice
      final _updateData = jsonEncode({
        'id': invoiceId,
        'company_id': companyId,
        'transaction_id': invoice.transactionId,
        'invoice_type': 'sale',
        'party_id': customer.id,
        'invoice_date': date.toIso8601String(),
        'grand_total': invoice.grandTotal,
        'status': invoice.status,
        'previous_balance': invoice.previousBalance,
        'paid_amount': invoice.paidAmount,
        'remaining_balance': invoice.remainingBalance,
      });
      final _updateChange = SyncChange()
        ..companyId = companyId
        ..table = 'invoices'
        ..operation = ChangeOperation.update
        ..recordId = invoiceId
        ..data = _updateData
        ..createdAt = DateTime.now()
        ..synced = false;
      await isar.syncChanges.put(_updateChange);

      // Delete old transaction lines and stock ledger entries
      final oldLines = await isar.transactionLines
          .filter()
          .transactionIdEqualTo(transactionId)
          .findAll();

      for (final oldLine in oldLines) {
        await isar.transactionLines.delete(oldLine.id);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'transaction_lines'
          ..operation = ChangeOperation.delete
          ..recordId = oldLine.id
          ..data = jsonEncode({'id': oldLine.id})
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      final oldStocks = await isar.stockLedgers
          .filter()
          .invoiceIdEqualTo(invoiceId)
          .findAll();

      for (final oldStock in oldStocks) {
        await isar.stockLedgers.delete(oldStock.id);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'stock_ledgers'
          ..operation = ChangeOperation.delete
          ..recordId = oldStock.id
          ..data = jsonEncode({'id': oldStock.id})
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Create new transaction lines and stock ledger entries
      for (final l in lines) {
        final line = TransactionLine()
          ..transactionId = transactionId
          ..productId = l.productId
          ..quantity = l.qty
          ..unitPrice = l.rate
          ..lineAmount = l.qty * l.rate;

        final lineId = await isar.transactionLines.put(line);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'transaction_lines'
          ..operation = ChangeOperation.create
          ..recordId = lineId
          ..data = jsonEncode({
            'id': lineId,
            'transaction_id': transactionId,
            'product_id': l.productId,
            'quantity': l.qty,
            'unit_price': l.rate,
            'line_amount': l.qty * l.rate,
          })
          ..createdAt = DateTime.now()
          ..synced = false);

        // Calculate COGS using weighted average cost
        final avgCost = await _calculateAverageCost(companyId, l.productId);
        final unitCost = avgCost;
        final totalCost = l.qty * unitCost;

        final stock = StockLedger()
          ..companyId = companyId
          ..productId = l.productId
          ..date = date
          ..movementType = StockMovementType.outSale
          ..quantityDelta = -l.qty
          ..unitCost = unitCost
          ..totalCost = totalCost
          ..transactionId = transactionId
          ..invoiceId = invoiceId;

        final stockId = await isar.stockLedgers.put(stock);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'stock_ledgers'
          ..operation = ChangeOperation.create
          ..recordId = stockId
          ..data = jsonEncode({
            'id': stockId,
            'company_id': companyId,
            'product_id': l.productId,
            'date': date.toIso8601String(),
            'movement_type': 'outSale',
            'quantity_delta': -l.qty,
            'unit_cost': unitCost,
            'total_cost': totalCost,
            'transaction_id': transactionId,
            'invoice_id': invoiceId,
          })
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Delete ALL old accounting transactions related to this invoice
      await _accountDao.deleteSaleInvoiceTransactionsInternal(invoiceId);

      // Record new invoice accounting (DR AR, CR Sales)
      // newTotal is already calculated above

      await _accountDao.recordSaleInvoiceInternal(
        companyId: companyId,
        invoiceId: invoiceId,
        customerId: customer.id,
        customerName: customer.name,
        invoiceDate: date,
        invoiceNo: referenceNo,
        totalAmount: newTotal,
      );

      // Calculate and record COGS
      double totalCOGS = 0;
      for (final l in lines) {
        final avgCost = await _calculateAverageCost(companyId, l.productId);
        totalCOGS += l.qty * avgCost;
      }

      if (totalCOGS > 0) {
        await _accountDao.recordCOGSInternal(
          companyId: companyId,
          invoiceId: invoiceId,
          saleDate: date,
          invoiceNo: referenceNo,
          cogsAmount: totalCOGS,
        );
      }

      // Record new payment accounting if provided
      if (paymentLines != null && paymentLines.isNotEmpty) {
        int microsecondsDelay = 0;
        for (final paymentLine in paymentLines) {
          if (paymentLine.amount <= 0) continue;

          // Get payment account to determine type
          final paymentAccount = await _paymentDao
              .getPaymentAccountById(paymentLine.paymentAccountId);
          if (paymentAccount == null) {
            throw Exception(
              'Payment account (ID: ${paymentLine.paymentAccountId}) not found. '
              'Please verify your Cash/Bank account is set up under Settings.',
            );
          }

          // Determine account code based on account type
          final String accountCode;
          switch (paymentAccount.accountType) {
            case PaymentAccountType.cash:
              accountCode = '1000';
            case PaymentAccountType.bank:
              accountCode = '1100';
          }

          // Add microsecond delay for unique timestamps
          await Future.delayed(Duration(microseconds: microsecondsDelay));
          microsecondsDelay += 1000;

          final paymentDate =
              date.add(Duration(microseconds: microsecondsDelay));

          await _accountDao.recordSaleInvoicePaymentInternal(
            companyId: companyId,
            invoiceId: invoiceId,
            customerId: customer.id,
            customerName: customer.name,
            paymentDate: paymentDate,
            invoiceNo: referenceNo,
            amount: paymentLine.amount,
            accountCode: accountCode,
          );
        }
      }

      // Invoice balances are already updated above, no need to update again
    });
  }

  Future<void> deleteSaleInvoice(int invoiceId) async {
    await isar.writeTxn(() async {
      final invoice = await isar.invoices.get(invoiceId);
      if (invoice == null) return;

      // Delete accounting transactions
      await _accountDao.deleteSaleInvoiceTransactions(invoiceId);

      // Delete stock ledger entries
      final stocks = await isar.stockLedgers
          .filter()
          .invoiceIdEqualTo(invoiceId)
          .findAll();

      for (final stock in stocks) {
        await isar.stockLedgers.delete(stock.id);
        await isar.syncChanges.put(SyncChange()
          ..companyId = invoice.companyId
          ..table = 'stock_ledgers'
          ..operation = ChangeOperation.delete
          ..recordId = stock.id
          ..data = jsonEncode({'id': stock.id})
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Delete transaction lines
      final lines = await isar.transactionLines
          .filter()
          .transactionIdEqualTo(invoice.transactionId)
          .findAll();

      for (final line in lines) {
        await isar.transactionLines.delete(line.id);
        await isar.syncChanges.put(SyncChange()
          ..companyId = invoice.companyId
          ..table = 'transaction_lines'
          ..operation = ChangeOperation.delete
          ..recordId = line.id
          ..data = jsonEncode({'id': line.id})
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Delete transaction
      await isar.transactions.delete(invoice.transactionId);
      await isar.syncChanges.put(SyncChange()
        ..companyId = invoice.companyId
        ..table = 'transactions'
        ..operation = ChangeOperation.delete
        ..recordId = invoice.transactionId
        ..data = jsonEncode({'id': invoice.transactionId})
        ..createdAt = DateTime.now()
        ..synced = false);

      // Delete invoice
      await isar.invoices.delete(invoiceId);

      // Record sync change for deleted invoice
      await isar.syncChanges.put(SyncChange()
        ..companyId = invoice.companyId
        ..table = 'invoices'
        ..operation = ChangeOperation.delete
        ..recordId = invoiceId
        ..data = jsonEncode({'id': invoiceId})
        ..createdAt = DateTime.now()
        ..synced = false);
    });
  }

  /// Calculate weighted average cost for a product based on purchase history
  Future<double> _calculateAverageCost(int companyId, int productId) async {
    // Get all purchase stock movements for this product
    final purchases = await isar.stockLedgers
        .filter()
        .companyIdEqualTo(companyId)
        .productIdEqualTo(productId)
        .movementTypeEqualTo(StockMovementType.inPurchase)
        .findAll();

    if (purchases.isEmpty) {
      return 0.0; // No purchase history, cost is 0
    }

    // Calculate weighted average cost
    double totalCost = 0;
    double totalQuantity = 0;

    for (final purchase in purchases) {
      totalCost += purchase.totalCost;
      totalQuantity += purchase.quantityDelta;
    }

    if (totalQuantity == 0) {
      return 0.0;
    }

    return totalCost / totalQuantity;
  }

  // ========== SALE RETURN METHODS ==========

  /// Create a sale return transaction
  /// This reverses the accounting and stock for returned items
  Future<int> createSaleReturn({
    required int companyId,
    required int originalInvoiceId,
    required Party customer,
    required DateTime returnDate,
    required String returnNo,
    required List<SaleReturnLineInput> returnLines,
    int? userId,
  }) async {
    int returnInvoiceId = 0;

    await isar.writeTxn(() async {
      // Get original invoice to verify
      final originalInvoice = await isar.invoices.get(originalInvoiceId);
      if (originalInvoice == null) {
        throw Exception('Original invoice not found');
      }

      // Calculate total return amount
      final totalAmount =
          returnLines.fold(0.0, (sum, l) => sum + (l.qty * l.rate));

      // Create return transaction
      final returnTransaction = Transaction()
        ..companyId = companyId
        ..type = TransactionType.saleReturn
        ..date = returnDate
        ..referenceNo = returnNo
        ..partyId = customer.id
        ..totalAmount = totalAmount
        ..createdByUserId = userId;

      final returnTxnId = await isar.transactions.put(returnTransaction);

      // Record sync change for return transaction
      await isar.syncChanges.put(SyncChange()
        ..companyId = companyId
        ..table = 'transactions'
        ..operation = ChangeOperation.create
        ..recordId = returnTxnId
        ..data = jsonEncode({
          'id': returnTxnId,
          'company_id': companyId,
          'type': 'saleReturn',
          'date': returnDate.toIso8601String(),
          'reference_no': returnNo,
          'party_id': customer.id,
          'total_amount': totalAmount,
          'is_posted': false,
        })
        ..createdAt = DateTime.now()
        ..synced = false);

      // Create return invoice
      final returnInvoice = Invoice()
        ..companyId = companyId
        ..transactionId = returnTxnId
        ..invoiceType = InvoiceType.sale
        ..partyId = customer.id
        ..invoiceDate = returnDate
        ..grandTotal = totalAmount
        ..status = 'Return';

      returnInvoiceId = await isar.invoices.put(returnInvoice);

      // Record sync change for return invoice
      await isar.syncChanges.put(SyncChange()
        ..companyId = companyId
        ..table = 'invoices'
        ..operation = ChangeOperation.create
        ..recordId = returnInvoiceId
        ..data = jsonEncode({
          'id': returnInvoiceId,
          'company_id': companyId,
          'transaction_id': returnTxnId,
          'invoice_type': 'sale',
          'party_id': customer.id,
          'invoice_date': returnDate.toIso8601String(),
          'grand_total': totalAmount,
          'status': 'Return',
          'previous_balance': 0.0,
          'paid_amount': 0.0,
          'remaining_balance': totalAmount,
        })
        ..createdAt = DateTime.now()
        ..synced = false);

      // Create return lines
      for (final returnLine in returnLines) {
        final line = TransactionLine()
          ..transactionId = returnTxnId
          ..productId = returnLine.productId
          ..quantity = -returnLine.qty // Negative quantity for return
          ..unitPrice = returnLine.rate
          ..lineAmount = -(returnLine.qty * returnLine.rate);

        final lineId = await isar.transactionLines.put(line);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'transaction_lines'
          ..operation = ChangeOperation.create
          ..recordId = lineId
          ..data = jsonEncode({
            'id': lineId,
            'transaction_id': returnTxnId,
            'product_id': returnLine.productId,
            'quantity': -returnLine.qty,
            'unit_price': returnLine.rate,
            'line_amount': -(returnLine.qty * returnLine.rate),
          })
          ..createdAt = DateTime.now()
          ..synced = false);

        // Get average cost for COGS reversal
        final avgCost =
            await _calculateAverageCost(companyId, returnLine.productId);
        final unitCost = avgCost;
        final totalCost = returnLine.qty * unitCost;

        // Create positive stock entry (goods back in inventory)
        final stock = StockLedger()
          ..companyId = companyId
          ..productId = returnLine.productId
          ..date = returnDate
          ..movementType =
              StockMovementType.inAdjustment // Using adjustment for returns
          ..quantityDelta = returnLine.qty // Positive for return
          ..unitCost = unitCost
          ..totalCost = totalCost
          ..transactionId = returnTxnId
          ..invoiceId = returnInvoiceId;

        final stockId = await isar.stockLedgers.put(stock);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'stock_ledgers'
          ..operation = ChangeOperation.create
          ..recordId = stockId
          ..data = jsonEncode({
            'id': stockId,
            'company_id': companyId,
            'product_id': returnLine.productId,
            'date': returnDate.toIso8601String(),
            'movement_type': 'inAdjustment',
            'quantity_delta': returnLine.qty,
            'unit_cost': unitCost,
            'total_cost': totalCost,
            'transaction_id': returnTxnId,
            'invoice_id': returnInvoiceId,
          })
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Calculate total COGS to reverse
      double totalCOGS = 0;
      for (final returnLine in returnLines) {
        final avgCost =
            await _calculateAverageCost(companyId, returnLine.productId);
        totalCOGS += returnLine.qty * avgCost;
      }

      // Record sale return accounting (reverses AR and Revenue)
      await _accountDao.recordSaleReturnInternal(
        companyId: companyId,
        returnInvoiceId: returnInvoiceId,
        customerId: customer.id,
        customerName: customer.name,
        returnDate: returnDate,
        returnNo: returnNo,
        returnAmount: totalAmount,
      );

      // Record COGS reversal (reverses COGS and increases Inventory)
      if (totalCOGS > 0) {
        await _accountDao.recordCOGSReversalInternal(
          companyId: companyId,
          returnInvoiceId: returnInvoiceId,
          returnDate: returnDate,
          returnNo: returnNo,
          cogsReversalAmount: totalCOGS,
        );
      }
    });

    return returnInvoiceId;
  }

  /// Delete a sale return
  Future<void> deleteSaleReturn(int returnInvoiceId) async {
    await isar.writeTxn(() async {
      final returnInvoice = await isar.invoices.get(returnInvoiceId);
      if (returnInvoice == null) return;

      // Delete stock ledger entries
      final stocks = await isar.stockLedgers
          .filter()
          .invoiceIdEqualTo(returnInvoiceId)
          .findAll();

      for (final stock in stocks) {
        await isar.stockLedgers.delete(stock.id);
      }

      // Delete transaction lines
      final lines = await isar.transactionLines
          .filter()
          .transactionIdEqualTo(returnInvoice.transactionId)
          .findAll();

      for (final line in lines) {
        await isar.transactionLines.delete(line.id);
      }

      // Delete accounting entries
      await _accountDao.deleteSaleReturnTransactionsInternal(returnInvoiceId);

      // Delete transaction and invoice
      await isar.transactions.delete(returnInvoice.transactionId);
      await isar.invoices.delete(returnInvoiceId);
    });
  }
}

class SaleLineInput {
  final int productId;
  final double qty;
  final double rate;

  SaleLineInput({
    required this.productId,
    required this.qty,
    required this.rate,
  });
}

class SaleReturnLineInput {
  final int productId;
  final double qty;
  final double rate;

  SaleReturnLineInput({
    required this.productId,
    required this.qty,
    required this.rate,
  });
}

class PaymentLineInput {
  final int paymentAccountId;
  final double amount;
  final String? referenceNo;

  PaymentLineInput({
    required this.paymentAccountId,
    required this.amount,
    this.referenceNo,
  });
}
