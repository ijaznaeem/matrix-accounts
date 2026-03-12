import 'dart:convert';

import 'package:isar/isar.dart';

import '../../../data/models/payment_models.dart';
import '../../../data/models/sync_change_model.dart';
import '../../../data/models/transaction_model.dart';
import 'account_dao.dart';

class ExpenseDao {
  final Isar isar;
  late final AccountDao _accountDao;

  ExpenseDao(this.isar) {
    _accountDao = AccountDao(isar);
  }

  Future<List<Transaction>> getExpenses(int companyId) async {
    return await isar.transactions
        .filter()
        .companyIdEqualTo(companyId)
        .typeEqualTo(TransactionType.expense)
        .sortByDateDesc()
        .findAll();
  }

  Future<Transaction?> getExpenseById(int expenseId) async {
    return await isar.transactions.get(expenseId);
  }

  Future<List<TransactionLine>> getExpenseLines(int expenseId) async {
    return await isar.transactionLines
        .filter()
        .transactionIdEqualTo(expenseId)
        .findAll();
  }

  Future<void> createExpense({
    required int companyId,
    required DateTime date,
    required String referenceNo,
    required int expenseAccountId,
    required String expenseAccountName,
    required List<ExpenseLineInput> lines,
    required List<PaymentLineInput> paymentLines,
    int? userId,
  }) async {
    final totalAmount = lines.fold(0.0, (sum, l) => sum + l.amount);

    await isar.writeTxn(() async {
      // Create expense transaction
      final transaction = Transaction()
        ..companyId = companyId
        ..type = TransactionType.expense
        ..date = date
        ..referenceNo = referenceNo
        ..totalAmount = totalAmount
        ..createdByUserId = userId;

      final expenseId = await isar.transactions.put(transaction);
      await isar.syncChanges.put(SyncChange()
        ..companyId = companyId
        ..table = 'transactions'
        ..operation = ChangeOperation.create
        ..recordId = expenseId
        ..data = jsonEncode({
          'id': expenseId,
          'company_id': companyId,
          'type': TransactionType.expense.name,
          'date': date.toIso8601String(),
          'reference_no': referenceNo,
          'party_id': null,
          'total_amount': totalAmount,
          'is_posted': false,
        })
        ..createdAt = DateTime.now()
        ..synced = false);

      // Create transaction lines
      for (final line in lines) {
        final transactionLine = TransactionLine()
          ..transactionId = expenseId
          ..expenseCategoryId = expenseAccountId
          ..description = line.description
          ..quantity = line.quantity
          ..unitPrice = line.rate
          ..lineAmount = line.amount;

        final lineId = await isar.transactionLines.put(transactionLine);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'transaction_lines'
          ..operation = ChangeOperation.create
          ..recordId = lineId
          ..data = jsonEncode({
            'id': lineId,
            'transaction_id': expenseId,
            'product_id': null,
            'expense_category_id': expenseAccountId,
            'description': line.description,
            'quantity': line.quantity,
            'unit_price': line.rate,
            'line_amount': line.amount,
          })
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Record accounting entries for each payment account
      for (final paymentLine in paymentLines) {
        if (paymentLine.amount <= 0) continue;

        // Determine account code based on payment account ID
        final paymentAccount =
            await isar.paymentAccounts.get(paymentLine.accountId);
        if (paymentAccount == null) continue;

        String accountCode;
        switch (paymentAccount.accountType) {
          case PaymentAccountType.cash:
            accountCode = '1000';
          case PaymentAccountType.bank:
            accountCode = '1100';
        }

        await _accountDao.recordExpenseInternal(
          companyId: companyId,
          expenseId: expenseId,
          expenseAccountId: expenseAccountId,
          expenseAccountName: expenseAccountName,
          expenseDate: date,
          referenceNo: referenceNo,
          amount: paymentLine.amount,
          paymentAccountCode: accountCode,
        );
      }
    });
  }

  Future<void> updateExpense({
    required int expenseId,
    required int companyId,
    required DateTime date,
    required String referenceNo,
    required int expenseAccountId,
    required String expenseAccountName,
    required List<ExpenseLineInput> lines,
    required List<PaymentLineInput> paymentLines,
    int? userId,
  }) async {
    final totalAmount = lines.fold(0.0, (sum, l) => sum + l.amount);

    await isar.writeTxn(() async {
      // Update expense transaction
      final transaction = await isar.transactions.get(expenseId);
      if (transaction != null) {
        transaction.date = date;
        transaction.referenceNo = referenceNo;
        transaction.totalAmount = totalAmount;
        await isar.transactions.put(transaction);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'transactions'
          ..operation = ChangeOperation.update
          ..recordId = expenseId
          ..data = jsonEncode({
            'id': expenseId,
            'company_id': companyId,
            'type': TransactionType.expense.name,
            'date': date.toIso8601String(),
            'reference_no': referenceNo,
            'party_id': null,
            'total_amount': totalAmount,
            'is_posted': false,
          })
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Delete old transaction lines
      final oldLines = await isar.transactionLines
          .filter()
          .transactionIdEqualTo(expenseId)
          .findAll();
      for (final line in oldLines) {
        await isar.transactionLines.delete(line.id);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'transaction_lines'
          ..operation = ChangeOperation.delete
          ..recordId = line.id
          ..data = jsonEncode({'id': line.id})
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Create new transaction lines
      for (final line in lines) {
        final transactionLine = TransactionLine()
          ..transactionId = expenseId
          ..expenseCategoryId = expenseAccountId
          ..description = line.description
          ..quantity = line.quantity
          ..unitPrice = line.rate
          ..lineAmount = line.amount;

        final lineId = await isar.transactionLines.put(transactionLine);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'transaction_lines'
          ..operation = ChangeOperation.create
          ..recordId = lineId
          ..data = jsonEncode({
            'id': lineId,
            'transaction_id': expenseId,
            'product_id': null,
            'expense_category_id': expenseAccountId,
            'description': line.description,
            'quantity': line.quantity,
            'unit_price': line.rate,
            'line_amount': line.amount,
          })
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Delete old accounting entries
      await _accountDao.deleteExpenseTransactionsInternal(expenseId);

      // Create new accounting entries
      for (final paymentLine in paymentLines) {
        if (paymentLine.amount <= 0) continue;

        final paymentAccount =
            await isar.paymentAccounts.get(paymentLine.accountId);
        if (paymentAccount == null) continue;

        String accountCode;
        switch (paymentAccount.accountType) {
          case PaymentAccountType.cash:
            accountCode = '1000';
          case PaymentAccountType.bank:
            accountCode = '1100';
        }

        await _accountDao.recordExpenseInternal(
          companyId: companyId,
          expenseId: expenseId,
          expenseAccountId: expenseAccountId,
          expenseAccountName: expenseAccountName,
          expenseDate: date,
          referenceNo: referenceNo,
          amount: paymentLine.amount,
          paymentAccountCode: accountCode,
        );
      }
    });
  }

  Future<void> deleteExpense(int expenseId) async {
    await isar.writeTxn(() async {
      final expenseRecord = await isar.transactions.get(expenseId);
      final companyId = expenseRecord?.companyId ?? 0;

      // Delete transaction lines
      final lines = await isar.transactionLines
          .filter()
          .transactionIdEqualTo(expenseId)
          .findAll();
      for (final line in lines) {
        await isar.transactionLines.delete(line.id);
        await isar.syncChanges.put(SyncChange()
          ..companyId = companyId
          ..table = 'transaction_lines'
          ..operation = ChangeOperation.delete
          ..recordId = line.id
          ..data = jsonEncode({'id': line.id})
          ..createdAt = DateTime.now()
          ..synced = false);
      }

      // Delete accounting transactions
      await _accountDao.deleteExpenseTransactionsInternal(expenseId);

      // Delete expense record
      await isar.transactions.delete(expenseId);
      await isar.syncChanges.put(SyncChange()
        ..companyId = companyId
        ..table = 'transactions'
        ..operation = ChangeOperation.delete
        ..recordId = expenseId
        ..data = jsonEncode({'id': expenseId})
        ..createdAt = DateTime.now()
        ..synced = false);
    });
  }
}

class ExpenseLineInput {
  final String description;
  final double quantity;
  final double rate;
  final double amount;

  ExpenseLineInput({
    required this.description,
    required this.quantity,
    required this.rate,
    required this.amount,
  });
}

class PaymentLineInput {
  final int accountId;
  final double amount;

  PaymentLineInput({
    required this.accountId,
    required this.amount,
  });
}
