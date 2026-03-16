import 'dart:convert';

import 'package:isar/isar.dart';

import '../../../data/models/invoice_stock_models.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/payment_models.dart';
import '../../../data/models/sync_change_model.dart';
import '../../../data/models/transaction_model.dart';
import 'account_dao.dart';
import 'sales_dao.dart' as sales; // For PaymentLineInput

class PurchaseDao {
  final Isar isar;
  final AccountDao _accountDao;

  PurchaseDao(this.isar) : _accountDao = AccountDao(isar);

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

  Future<String> _ensureUniqueReferenceNo({
    required int companyId,
    required TransactionType type,
    required String referenceNo,
    int? excludeTransactionId,
  }) async {
    final trimmedReference = referenceNo.trim();
    final baseReference = trimmedReference.isEmpty
        ? 'PUR-$companyId-${DateTime.now().millisecondsSinceEpoch}'
        : trimmedReference;

    final existingTransactions = await isar.transactions
        .filter()
        .companyIdEqualTo(companyId)
        .typeEqualTo(type)
        .findAll();

    final existingReferences = existingTransactions
        .where((transaction) => transaction.id != excludeTransactionId)
        .map((transaction) => transaction.referenceNo.trim().toLowerCase())
        .toSet();

    if (!existingReferences.contains(baseReference.toLowerCase())) {
      return baseReference;
    }

    final serialPattern = RegExp(r'^(.*?)-(\d+)$');
    final match = serialPattern.firstMatch(baseReference);

    if (match != null) {
      final prefix = match.group(1)!;
      final serialText = match.group(2)!;
      var serial = int.tryParse(serialText) ?? 0;
      final width = serialText.length;

      while (true) {
        serial += 1;
        final candidate = '$prefix-${serial.toString().padLeft(width, '0')}';
        if (!existingReferences.contains(candidate.toLowerCase())) {
          return candidate;
        }
      }
    }

    var suffix = 2;
    while (true) {
      final candidate = '$baseReference-$suffix';
      if (!existingReferences.contains(candidate.toLowerCase())) {
        return candidate;
      }
      suffix += 1;
    }
  }

  Future<void> createPurchaseInvoice({
    required int companyId,
    required Party supplier,
    required DateTime date,
    required String referenceNo,
    required List<PurchaseLineInput> lines,
    List<sales.PaymentLineInput>? paymentLines,
    int? userId,
    String? notes,
    String? attachmentPath,
  }) async {
    final uniqueReferenceNo = await _ensureUniqueReferenceNo(
      companyId: companyId,
      type: TransactionType.purchase,
      referenceNo: referenceNo,
    );

    final totalAmount = lines.fold(0.0, (sum, l) => sum + (l.qty * l.rate));

    // Debug the amount calculation
    print('=== PURCHASE DAO AMOUNT DEBUG ===');
    print('Lines count: ${lines.length}');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      print(
          'Line $i: Qty=${line.qty}, Rate=${line.rate}, Amount=${line.qty * line.rate}');
    }
    print('Calculated totalAmount: $totalAmount');
    print('Payment lines count: ${paymentLines?.length ?? 0}');
    if (paymentLines != null) {
      for (int i = 0; i < paymentLines.length; i++) {
        print('Payment $i: Amount=${paymentLines[i].amount}');
      }
    }
    print('===============================');

    final transaction = Transaction()
      ..companyId = companyId
      ..type = TransactionType.purchase
      ..date = date
      ..referenceNo = uniqueReferenceNo
      ..partyId = supplier.id
      ..totalAmount = totalAmount
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
          'type': 'purchase',
          'date': date.toIso8601String(),
          'reference_no': uniqueReferenceNo,
          'party_id': supplier.id,
          'total_amount': totalAmount,
          'is_posted': false,
        })
        ..createdAt = DateTime.now()
        ..synced = false);

      // Calculate previous balance for this supplier
      final previousInvoices = await isar.invoices
          .filter()
          .companyIdEqualTo(companyId)
          .partyIdEqualTo(supplier.id)
          .invoiceTypeEqualTo(InvoiceType.purchase)
          .invoiceDateLessThan(date)
          .findAll();

      double previousBalance = 0;
      for (final prevInvoice in previousInvoices) {
        previousBalance += prevInvoice.remainingBalance;
      }

      // Calculate total paid amount from payment lines
      double totalPaid = 0;
      if (paymentLines != null) {
        totalPaid = paymentLines.fold(0.0, (sum, p) => sum + p.amount);
      }

      final invoice = Invoice()
        ..companyId = companyId
        ..transactionId = txnId
        ..invoiceType = InvoiceType.purchase
        ..partyId = supplier.id
        ..invoiceDate = date
        ..grandTotal = transaction.totalAmount
        ..invoiceNumber = uniqueReferenceNo
        ..previousBalance = previousBalance
        ..paidAmount = totalPaid
        ..remainingBalance =
            previousBalance + transaction.totalAmount - totalPaid
        ..status = 'Pending'
        ..notes = notes
        ..attachmentPath = attachmentPath;

      final invoiceId = await isar.invoices.put(invoice);

      // Record sync change for created invoice
      await isar.syncChanges.put(SyncChange()
        ..companyId = companyId
        ..table = 'invoices'
        ..operation = ChangeOperation.create
        ..recordId = invoiceId
        ..data = jsonEncode({
          'id': invoiceId,
          'company_id': companyId,
          'transaction_id': txnId,
          'invoice_type': 'purchase',
          'party_id': supplier.id,
          'invoice_date': date.toIso8601String(),
          'grand_total': invoice.grandTotal,
          'invoice_number': invoice.invoiceNumber,
          'status': invoice.status,
          'previous_balance': invoice.previousBalance,
          'paid_amount': invoice.paidAmount,
          'remaining_balance': invoice.remainingBalance,
          'notes': invoice.notes,
          'attachment_path': invoice.attachmentPath,
        })
        ..createdAt = DateTime.now()
        ..synced = false);

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

        // Calculate unit cost for this purchase
        final unitCost = l.rate;
        final totalCost = l.qty * unitCost;

        final stock = StockLedger()
          ..companyId = companyId
          ..productId = l.productId
          ..date = date
          ..movementType = StockMovementType.inPurchase
          ..quantityDelta = l.qty // Positive for purchase
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
            'movement_type': 'inPurchase',
            'quantity_delta': l.qty,
            'unit_cost': unitCost,
            'total_cost': totalCost,
            'transaction_id': txnId,
            'invoice_id': invoiceId,
          })
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Record accounting transaction - invoice amount
      await _accountDao.recordPurchaseInvoiceInternal(
        companyId: companyId,
        invoiceId: invoiceId,
        supplierId: supplier.id,
        supplierName: supplier.name,
        invoiceDate: date,
        invoiceNo: uniqueReferenceNo,
        totalAmount: transaction.totalAmount,
      );

      // Record payment if provided
      if (paymentLines != null && paymentLines.isNotEmpty) {
        int microsecondsDelay = 0;
        for (final paymentLine in paymentLines) {
          final paymentAccount =
              await isar.paymentAccounts.get(paymentLine.paymentAccountId);
          if (paymentAccount == null) continue;

          // Determine account code based on account type
          String accountCode;
          if (paymentAccount.accountType == PaymentAccountType.cash) {
            accountCode = '1000';
          } else {
            accountCode = '1100'; // bank
          }

          // Add microsecond delay for unique timestamps
          await Future.delayed(Duration(microseconds: microsecondsDelay));
          microsecondsDelay += 1000;

          final paymentDate =
              date.add(Duration(microseconds: microsecondsDelay));

          await _accountDao.recordPurchaseInvoicePaymentInternal(
            companyId: companyId,
            invoiceId: invoiceId,
            supplierId: supplier.id,
            supplierName: supplier.name,
            paymentDate: paymentDate,
            invoiceNo: uniqueReferenceNo,
            amount: paymentLine.amount,
            accountCode: accountCode,
          );
        }
      }
    });
  }

  Future<void> updatePurchaseInvoice({
    required int invoiceId,
    required int companyId,
    required Party supplier,
    required DateTime date,
    required String referenceNo,
    required List<PurchaseLineInput> lines,
    List<sales.PaymentLineInput>? paymentLines,
    int? userId,
    String? notes,
    String? attachmentPath,
  }) async {
    final invoice = await isar.invoices.get(invoiceId);
    if (invoice == null) throw Exception('Invoice not found');

    final transactionId = invoice.transactionId;
    final uniqueReferenceNo = await _ensureUniqueReferenceNo(
      companyId: companyId,
      type: TransactionType.purchase,
      referenceNo: referenceNo,
      excludeTransactionId: transactionId,
    );

    await isar.writeTxn(() async {
      // Update transaction
      final transaction = await isar.transactions.get(transactionId);
      if (transaction != null) {
        transaction.date = date;
        transaction.referenceNo = uniqueReferenceNo;
        transaction.partyId = supplier.id;
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
            'type': 'purchase',
            'date': date.toIso8601String(),
            'reference_no': uniqueReferenceNo,
            'party_id': supplier.id,
            'total_amount': transaction.totalAmount,
            'is_posted': transaction.isPosted,
          })
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Update invoice
      invoice.partyId = supplier.id;
      invoice.invoiceDate = date;
      invoice.grandTotal = lines.fold(0.0, (sum, l) => sum + (l.qty * l.rate));
      invoice.invoiceNumber = uniqueReferenceNo;
      invoice.notes = notes;
      invoice.attachmentPath = attachmentPath;
      await isar.invoices.put(invoice);
      await isar.syncChanges.put(SyncChange()
        ..companyId = companyId
        ..table = 'invoices'
        ..operation = ChangeOperation.update
        ..recordId = invoiceId
        ..data = jsonEncode({
          'id': invoiceId,
          'company_id': companyId,
          'transaction_id': transactionId,
          'invoice_type': 'purchase',
          'party_id': supplier.id,
          'invoice_date': date.toIso8601String(),
          'grand_total': invoice.grandTotal,
          'invoice_number': invoice.invoiceNumber,
          'status': invoice.status,
          'previous_balance': invoice.previousBalance,
          'paid_amount': invoice.paidAmount,
          'remaining_balance': invoice.remainingBalance,
          'notes': invoice.notes,
          'attachment_path': invoice.attachmentPath,
        })
        ..createdAt = DateTime.now()
        ..synced = false);

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

        // Calculate unit cost for this purchase
        final unitCost = l.rate;
        final totalCost = l.qty * unitCost;

        final stock = StockLedger()
          ..companyId = companyId
          ..productId = l.productId
          ..date = date
          ..movementType = StockMovementType.inPurchase
          ..quantityDelta = l.qty // Positive for purchase
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
            'movement_type': 'inPurchase',
            'quantity_delta': l.qty,
            'unit_cost': unitCost,
            'total_cost': totalCost,
            'transaction_id': transactionId,
            'invoice_id': invoiceId,
          })
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Delete ALL old accounting transactions related to this invoice
      await _accountDao.deletePurchaseInvoiceTransactionsInternal(invoiceId);

      // Record new invoice accounting
      final newTotal = lines.fold(0.0, (sum, l) => sum + (l.qty * l.rate));

      await _accountDao.recordPurchaseInvoiceInternal(
        companyId: companyId,
        invoiceId: invoiceId,
        supplierId: supplier.id,
        supplierName: supplier.name,
        invoiceDate: date,
        invoiceNo: uniqueReferenceNo,
        totalAmount: newTotal,
      );

      // Record new payment accounting if provided
      if (paymentLines != null && paymentLines.isNotEmpty) {
        int microsecondsDelay = 0;
        for (final paymentLine in paymentLines) {
          final paymentAccount =
              await isar.paymentAccounts.get(paymentLine.paymentAccountId);
          if (paymentAccount == null) continue;

          // Determine account code based on account type
          String accountCode;
          if (paymentAccount.accountType == PaymentAccountType.cash) {
            accountCode = '1000';
          } else {
            accountCode = '1100'; // bank
          }

          // Add microsecond delay for unique timestamps
          await Future.delayed(Duration(microseconds: microsecondsDelay));
          microsecondsDelay += 1000;

          final paymentDate =
              date.add(Duration(microseconds: microsecondsDelay));

          await _accountDao.recordPurchaseInvoicePaymentInternal(
            companyId: companyId,
            invoiceId: invoiceId,
            supplierId: supplier.id,
            supplierName: supplier.name,
            paymentDate: paymentDate,
            invoiceNo: uniqueReferenceNo,
            amount: paymentLine.amount,
            accountCode: accountCode,
          );
        }
      }

      // Update invoice grand total
      invoice.grandTotal = newTotal;
      await isar.invoices.put(invoice);
    });
  }

  Future<void> deletePurchaseInvoice(int invoiceId) async {
    await isar.writeTxn(() async {
      final invoice = await isar.invoices.get(invoiceId);
      if (invoice == null) return;

      // Delete accounting transactions
      await _accountDao.deletePurchaseInvoiceTransactionsInternal(invoiceId);

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

  // ========== PURCHASE RETURN METHODS ==========

  /// Create a purchase return transaction
  /// This reverses the accounting and stock for returned items
  Future<int> createPurchaseReturn({
    required int companyId,
    required int originalInvoiceId,
    required Party supplier,
    required DateTime returnDate,
    required String returnNo,
    required List<PurchaseReturnLineInput> returnLines,
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
        ..type = TransactionType.purchaseReturn
        ..date = returnDate
        ..referenceNo = returnNo
        ..partyId = supplier.id
        ..totalAmount = totalAmount
        ..createdByUserId = userId;

      final returnTxnId = await isar.transactions.put(returnTransaction);
      await isar.syncChanges.put(SyncChange()
        ..companyId = companyId
        ..table = 'transactions'
        ..operation = ChangeOperation.create
        ..recordId = returnTxnId
        ..data = jsonEncode({
          'id': returnTxnId,
          'company_id': companyId,
          'type': TransactionType.purchaseReturn.name,
          'date': returnDate.toIso8601String(),
          'reference_no': returnNo,
          'party_id': supplier.id,
          'total_amount': totalAmount,
          'is_posted': false,
        })
        ..createdAt = DateTime.now()
        ..synced = false);

      // Create return invoice
      final returnInvoice = Invoice()
        ..companyId = companyId
        ..transactionId = returnTxnId
        ..invoiceType = InvoiceType.purchase
        ..partyId = supplier.id
        ..invoiceDate = returnDate
        ..grandTotal = totalAmount
        ..status = 'Return';

      returnInvoiceId = await isar.invoices.put(returnInvoice);
      await isar.syncChanges.put(SyncChange()
        ..companyId = companyId
        ..table = 'invoices'
        ..operation = ChangeOperation.create
        ..recordId = returnInvoiceId
        ..data = jsonEncode({
          'id': returnInvoiceId,
          'company_id': companyId,
          'transaction_id': returnTxnId,
          'invoice_type': InvoiceType.purchase.name,
          'party_id': supplier.id,
          'invoice_date': returnDate.toIso8601String(),
          'grand_total': totalAmount,
          'status': 'Return',
          'previous_balance': 0,
          'paid_amount': 0,
          'remaining_balance': 0,
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
            'expense_category_id': null,
            'description': null,
            'quantity': -returnLine.qty,
            'unit_price': returnLine.rate,
            'line_amount': -(returnLine.qty * returnLine.rate),
          })
          ..createdAt = DateTime.now()
          ..synced = false);

        // Create negative stock entry (goods out of inventory)
        final stock = StockLedger()
          ..companyId = companyId
          ..productId = returnLine.productId
          ..date = returnDate
          ..movementType =
              StockMovementType.outAdjustment // Using adjustment for returns
          ..quantityDelta = -returnLine.qty // Negative for return
          ..unitCost = returnLine.rate
          ..totalCost = returnLine.qty * returnLine.rate
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
            'movement_type': StockMovementType.outAdjustment.name,
            'quantity_delta': -returnLine.qty,
            'unit_cost': returnLine.rate,
            'total_cost': returnLine.qty * returnLine.rate,
            'transaction_id': returnTxnId,
            'invoice_id': returnInvoiceId,
          })
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Record purchase return accounting (reverses AP and Inventory)
      await _accountDao.recordPurchaseReturnInternal(
        companyId: companyId,
        returnInvoiceId: returnInvoiceId,
        supplierId: supplier.id,
        supplierName: supplier.name,
        returnDate: returnDate,
        returnNo: returnNo,
        returnAmount: totalAmount,
      );
    });

    return returnInvoiceId;
  }

  /// Delete a purchase return
  Future<void> deletePurchaseReturn(int returnInvoiceId) async {
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
        await isar.syncChanges.put(SyncChange()
          ..companyId = returnInvoice.companyId
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
          .transactionIdEqualTo(returnInvoice.transactionId)
          .findAll();

      for (final line in lines) {
        await isar.transactionLines.delete(line.id);
        await isar.syncChanges.put(SyncChange()
          ..companyId = returnInvoice.companyId
          ..table = 'transaction_lines'
          ..operation = ChangeOperation.delete
          ..recordId = line.id
          ..data = jsonEncode({'id': line.id})
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Delete accounting entries
      await _accountDao
          .deletePurchaseReturnTransactionsInternal(returnInvoiceId);

      // Delete transaction and invoice
      await isar.transactions.delete(returnInvoice.transactionId);
      await isar.syncChanges.put(SyncChange()
        ..companyId = returnInvoice.companyId
        ..table = 'transactions'
        ..operation = ChangeOperation.delete
        ..recordId = returnInvoice.transactionId
        ..data = jsonEncode({'id': returnInvoice.transactionId})
        ..createdAt = DateTime.now()
        ..synced = false);

      await isar.invoices.delete(returnInvoiceId);
      await isar.syncChanges.put(SyncChange()
        ..companyId = returnInvoice.companyId
        ..table = 'invoices'
        ..operation = ChangeOperation.delete
        ..recordId = returnInvoiceId
        ..data = jsonEncode({'id': returnInvoiceId})
        ..createdAt = DateTime.now()
        ..synced = false);
    });
  }
}

class PurchaseLineInput {
  final int productId;
  final double qty;
  final double rate;

  PurchaseLineInput({
    required this.productId,
    required this.qty,
    required this.rate,
  });
}

class PurchaseReturnLineInput {
  final int productId;
  final double qty;
  final double rate;

  PurchaseReturnLineInput({
    required this.productId,
    required this.qty,
    required this.rate,
  });
}
