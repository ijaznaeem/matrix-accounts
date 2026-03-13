import 'dart:convert';

import 'package:isar/isar.dart';

import '../../../data/models/account_models.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/sync_change_model.dart';

class PartyDao {
  final Isar isar;

  PartyDao(this.isar);

  Future<void> _recordSyncChange({
    required int companyId,
    required String table,
    required ChangeOperation operation,
    required int recordId,
    required Map<String, dynamic> data,
  }) async {
    final change = SyncChange()
      ..companyId = companyId
      ..table = table
      ..operation = operation
      ..recordId = recordId
      ..data = jsonEncode(data)
      ..createdAt = DateTime.now()
      ..synced = false;

    await isar.syncChanges.put(change);
  }

  Future<void> _syncPartyUpdate(Party party) async {
    await _recordSyncChange(
      companyId: party.companyId,
      table: 'parties',
      operation: ChangeOperation.update,
      recordId: party.id,
      data: _partyToMap(party),
    );
  }

  Future<void> _syncAccountUpdate(Account account) async {
    await _recordSyncChange(
      companyId: account.companyId,
      table: 'accounts',
      operation: ChangeOperation.update,
      recordId: account.id,
      data: {
        'id': account.id,
        'company_id': account.companyId,
        'name': account.name,
        'code': account.code,
        'account_type': account.accountType.name,
        'parent_account_id': account.parentAccountId,
        'description': account.description,
        'is_system': account.isSystem,
        'opening_balance': account.openingBalance,
        'current_balance': account.currentBalance,
        'is_active': account.isActive,
        'created_at': account.createdAt.toIso8601String(),
      },
    );
  }

  Future<void> _syncAccountTransactionCreate(
      AccountTransaction transaction) async {
    await _recordSyncChange(
      companyId: transaction.companyId,
      table: 'account_transactions',
      operation: ChangeOperation.create,
      recordId: transaction.id,
      data: {
        'id': transaction.id,
        'company_id': transaction.companyId,
        'account_id': transaction.accountId,
        'transaction_type': transaction.transactionType.name,
        'reference_id': transaction.referenceId,
        'transaction_date': transaction.transactionDate.toIso8601String(),
        'description': transaction.description,
        'debit': transaction.debit,
        'credit': transaction.credit,
        'running_balance': transaction.runningBalance,
        'reference_no': transaction.referenceNo,
        'party_id': transaction.partyId,
        'created_at': transaction.createdAt.toIso8601String(),
      },
    );
  }

  Future<void> _syncAccountTransactionDelete(
      AccountTransaction transaction) async {
    await _recordSyncChange(
      companyId: transaction.companyId,
      table: 'account_transactions',
      operation: ChangeOperation.delete,
      recordId: transaction.id,
      data: {'id': transaction.id},
    );
  }

  Future<void> saveParty(Party party) async {
    await isar.writeTxn(() async {
      final isNew = party.id == Isar.autoIncrement;
      await isar.partys.put(party);
      await _recordSyncChange(
        companyId: party.companyId,
        table: 'parties',
        operation: isNew ? ChangeOperation.create : ChangeOperation.update,
        recordId: party.id,
        data: _partyToMap(party),
      );
    });
  }

  Map<String, dynamic> _partyToMap(Party p) => {
        'id': p.id,
        'company_id': p.companyId,
        'name': p.name,
        'party_type': p.partyType.name,
        'phone': p.phone,
        'email': p.email,
        'address': p.address,
        'opening_balance': p.openingBalance,
        'credit_limit': p.creditLimit,
        'payment_terms_days': p.paymentTermsDays,
        'is_active': p.isActive,
      };

  Future<void> ensureOpeningBalanceLedgerEntries(int companyId) async {
    await isar.writeTxn(() async {
      final receivableAccount = await isar.accounts
          .filter()
          .companyIdEqualTo(companyId)
          .codeEqualTo('1200')
          .findFirst();
      final payableAccount = await isar.accounts
          .filter()
          .companyIdEqualTo(companyId)
          .codeEqualTo('2000')
          .findFirst();

      final parties =
          await isar.partys.filter().companyIdEqualTo(companyId).findAll();

      for (final party in parties) {
        if (party.openingBalance == 0) {
          continue;
        }

        final account = (party.partyType == PartyType.customer ||
                party.partyType == PartyType.both)
            ? receivableAccount
            : payableAccount;
        if (account == null) {
          continue;
        }

        final existingEntry = await isar.accountTransactions
            .filter()
            .companyIdEqualTo(companyId)
            .accountIdEqualTo(account.id)
            .partyIdEqualTo(party.id)
            .transactionTypeEqualTo(TransactionType.journalEntry)
            .descriptionContains('Opening Balance')
            .findFirst();
        if (existingEntry != null) {
          continue;
        }

        final transaction = AccountTransaction()
          ..companyId = companyId
          ..accountId = account.id
          ..transactionType = TransactionType.journalEntry
          ..referenceId = 0
          ..transactionDate = party.createdAt
          ..description = 'Opening Balance - ${party.name}'
          ..referenceNo = 'OB-${party.name}'
          ..partyId = party.id;

        if (account.code == '1200') {
          if (party.openingBalance > 0) {
            transaction.debit = party.openingBalance;
            transaction.credit = 0;
          } else {
            transaction.debit = 0;
            transaction.credit = party.openingBalance.abs();
          }
        } else {
          if (party.openingBalance > 0) {
            transaction.debit = 0;
            transaction.credit = party.openingBalance;
          } else {
            transaction.debit = party.openingBalance.abs();
            transaction.credit = 0;
          }
        }

        account.currentBalance += transaction.debit - transaction.credit;
        transaction.runningBalance = account.currentBalance;

        await isar.accountTransactions.put(transaction);
        await isar.accounts.put(account);
      }
    });
  }

  Future<List<Party>> getAllByCompany(int companyId) async {
    return isar.partys.filter().companyIdEqualTo(companyId).findAll();
  }

  Future<void> deleteParty(int id) async {
    await isar.writeTxn(() async {
      final party = await isar.partys.get(id);
      await isar.partys.delete(id);
      if (party != null) {
        await _recordSyncChange(
          companyId: party.companyId,
          table: 'parties',
          operation: ChangeOperation.delete,
          recordId: id,
          data: {'id': id},
        );
      }
    });
  }

  /// Update party opening balance and record in AR/AP account
  /// For customers: positive balance = customer owes us (debit AR)
  /// For suppliers: positive balance = we owe them (credit AP)
  Future<void> updatePartyOpeningBalance({
    required int partyId,
    required int companyId,
    required double openingBalance,
    DateTime? asOfDate,
  }) async {
    await isar.writeTxn(() async {
      final party = await isar.partys.get(partyId);
      if (party == null) {
        throw Exception('Party not found');
      }

      // Calculate the difference to adjust accounting
      final difference = openingBalance - party.openingBalance;

      if (difference != 0) {
        // Determine which account to update based on party type
        String accountCode;
        if (party.partyType == PartyType.customer ||
            party.partyType == PartyType.both) {
          accountCode = '1200'; // Accounts Receivable
        } else {
          accountCode = '2000'; // Accounts Payable
        }

        // Get the account
        final account = await isar.accounts
            .filter()
            .companyIdEqualTo(companyId)
            .codeEqualTo(accountCode)
            .findFirst();

        if (account != null) {
          // Update account balance
          if (accountCode == '1200') {
            // AR increases with debit (customer owes us)
            account.currentBalance += difference;
          } else {
            // AP increases with credit (we owe supplier)
            account.currentBalance += difference;
          }

          await isar.accounts.put(account);

          // Create/update opening balance transaction for this party
          final existingOB = await isar.accountTransactions
              .filter()
              .companyIdEqualTo(companyId)
              .accountIdEqualTo(account.id)
              .partyIdEqualTo(partyId)
              .transactionTypeEqualTo(TransactionType.journalEntry)
              .descriptionContains('Opening Balance')
              .findFirst();

          if (existingOB != null) {
            // Delete old opening balance entry
            // Reverse its effect
            account.currentBalance -= (existingOB.debit - existingOB.credit);
            await isar.accountTransactions.delete(existingOB.id);
            await _syncAccountTransactionDelete(existingOB);
          }

          if (openingBalance != 0) {
            // Create new opening balance transaction
            final transaction = AccountTransaction()
              ..companyId = companyId
              ..accountId = account.id
              ..transactionType = TransactionType.journalEntry
              ..referenceId = 0
              ..transactionDate = asOfDate ?? DateTime.now()
              ..description = 'Opening Balance - ${party.name}'
              ..referenceNo = 'OB-${party.name}'
              ..partyId = partyId;

            // For AR (Asset): Debit increases, Credit decreases
            // For AP (Liability): Credit increases, Debit decreases
            if (accountCode == '1200') {
              // Accounts Receivable
              if (openingBalance > 0) {
                transaction.debit = openingBalance;
                transaction.credit = 0;
              } else {
                transaction.debit = 0;
                transaction.credit = openingBalance.abs();
              }
            } else {
              // Accounts Payable
              if (openingBalance > 0) {
                transaction.debit = 0;
                transaction.credit = openingBalance;
              } else {
                transaction.debit = openingBalance.abs();
                transaction.credit = 0;
              }
            }

            // Update account balance with new opening balance
            account.currentBalance += (transaction.debit - transaction.credit);
            transaction.runningBalance = account.currentBalance;

            await isar.accountTransactions.put(transaction);
            await _syncAccountTransactionCreate(transaction);
            await isar.accounts.put(account);
          }

          await _syncAccountUpdate(account);
        }
      }

      // Update party record
      party.openingBalance = openingBalance;
      await isar.partys.put(party);
      await _syncPartyUpdate(party);
    });
  }

  /// Get party balance from ledger (AR or AP account)
  Future<double> getPartyBalance({
    required int partyId,
    required int companyId,
  }) async {
    final party = await isar.partys.get(partyId);
    if (party == null) return 0;

    // Determine which ledger account to use for this party type
    final String accountCode;
    if (party.partyType == PartyType.customer ||
        party.partyType == PartyType.both) {
      accountCode = '1200'; // Accounts Receivable
    } else {
      accountCode = '2000'; // Accounts Payable
    }

    final account = await isar.accounts
        .filter()
        .companyIdEqualTo(companyId)
        .codeEqualTo(accountCode)
        .findFirst();

    if (account == null) return 0;

    // Sum debits and credits for THIS party on this account.
    // runningBalance is the whole-account cumulative total and MUST NOT be
    // used here — it reflects all parties combined.
    final transactions = await isar.accountTransactions
        .filter()
        .companyIdEqualTo(companyId)
        .accountIdEqualTo(account.id)
        .partyIdEqualTo(partyId)
        .findAll();

    double totalDebit = 0;
    double totalCredit = 0;
    for (final t in transactions) {
      totalDebit += t.debit;
      totalCredit += t.credit;
    }

    // For AR (1200): debit = amount owed by customer, credit = amount paid
    // Net positive = customer still owes money
    return totalDebit - totalCredit;
  }
}
