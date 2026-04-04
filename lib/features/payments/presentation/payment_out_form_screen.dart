// ignore_for_file: use_build_context_synchronously, avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/providers.dart';
import '../../../core/database/dao/payment_dao.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../data/models/company_model.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/payment_models.dart';
import '../../../data/models/user_model.dart';
import '../../../presentation/widgets/searchable_list.dart';
import '../../parties/logic/party_provider.dart';
import '../logic/payment_providers.dart';
import '../services/payment_out_receipt_generator.dart';

class PaymentLineDraft {
  int? accountId;
  String? accountName;
  String? accountIcon;
  double amount;
  String? referenceNo;

  PaymentLineDraft({
    this.accountId,
    this.accountName,
    this.accountIcon,
    this.amount = 0,
    this.referenceNo,
  });
}

class PaymentOutFormScreen extends ConsumerStatefulWidget {
  final int? paymentOutId;

  const PaymentOutFormScreen({super.key, this.paymentOutId});

  @override
  ConsumerState<PaymentOutFormScreen> createState() =>
      _PaymentOutFormScreenState();
}

class _PaymentOutFormScreenState extends ConsumerState<PaymentOutFormScreen> {
  Party? _selectedSupplier;
  DateTime _date = DateTime.now();
  final _voucherNoCtrl = TextEditingController();
  final List<PaymentLineDraft> _paymentLines = [];
  final _descriptionCtrl = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  double _livePartyBalance = 0;
  double _previousBalance = 0;
  String? _selectedImagePath;
  final ImagePicker _imagePicker = ImagePicker();

  String get _currencySymbol {
    final settings = ref.read(settingsProvider);
    return SettingsConstants.currencySymbols[settings.defaultCurrency] ??
        settings.defaultCurrency;
  }

  @override
  void initState() {
    super.initState();
    if (widget.paymentOutId != null) {
      _loadPaymentOut();
    } else {
      _generateSerialVoucherNo();
      _addDefaultCashPayment();
      _isLoading = false;
    }
  }

  Future<void> _generateSerialVoucherNo() async {
    final paymentDao = ref.read(paymentDaoProvider);
    final company = ref.read(currentCompanyProvider);
    if (company != null) {
      final payments = await paymentDao.getPaymentOuts(company.id);
      final nextNumber = payments.length + 1;
      _voucherNoCtrl.text = nextNumber.toString();
    }
  }

  void _addDefaultCashPayment() {
    setState(() {
      _paymentLines.add(PaymentLineDraft(
        accountName: 'Cash',
        accountIcon: '💵',
        amount: 0,
      ));
    });
  }

  Future<void> _loadPaymentOut() async {
    try {
      final paymentDao = ref.read(paymentDaoProvider);
      final isarService = ref.read(isarServiceProvider);
      final isar = isarService.isar;

      final payment = await paymentDao.getPaymentOutById(widget.paymentOutId!);
      if (payment == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment not found')),
          );
          Navigator.pop(context);
        }
        return;
      }

      final lines = await paymentDao.getPaymentOutLines(widget.paymentOutId!);
      final supplier = await isar.partys.get(payment.partyId);
      final liveBalance = await paymentDao.getPartyLiveBalance(
        payment.partyId,
        payment.companyId,
      );
      final previousBalance = payment.previousBalance == 0
          ? (liveBalance + payment.totalAmount)
          : payment.previousBalance;

      setState(() {
        _selectedSupplier = supplier;
        _date = payment.voucherDate;
        _voucherNoCtrl.text = payment.voucherNo;
        _descriptionCtrl.text = payment.description ?? '';
        _selectedImagePath = payment.attachmentPath;
        _livePartyBalance = liveBalance;
        _previousBalance = previousBalance;
        _paymentLines.clear();

        for (final line in lines) {
          final account = isar.paymentAccounts.getSync(line.paymentAccountId);
          _paymentLines.add(PaymentLineDraft(
            accountId: line.paymentAccountId,
            accountName: account?.accountName ?? 'Unknown',
            accountIcon: account?.icon,
            amount: line.amount,
            referenceNo: line.referenceNo,
          ));
        }

        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading payment: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _showImageSourceDialog() async {
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Image Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source != null) {
      await _pickImage(source);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (image != null) {
        setState(() {
          _selectedImagePath = image.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _voucherNoCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  double get _totalPaid =>
      _paymentLines.fold<double>(0, (sum, l) => sum + l.amount);

  double get _closingBalance => _previousBalance - _totalPaid;

  Future<void> _loadPartyBalance(Party supplier) async {
    final company = ref.read(currentCompanyProvider);
    if (company == null) return;

    final paymentDao = ref.read(paymentDaoProvider);
    final liveBalance =
        await paymentDao.getPartyLiveBalance(supplier.id, company.id);

    if (!mounted) return;
    setState(() {
      _livePartyBalance = liveBalance;
      _previousBalance = liveBalance;
    });
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(currentCompanyProvider);
    final user = ref.watch(currentUserProvider);
    final accountsAsync = ref.watch(paymentAccountsProvider);
    final partiesAsync = ref.watch(partyListProvider);
    final paymentDao = ref.read(paymentDaoProvider);

    if (company == null) {
      return const Scaffold(
        body: Center(child: Text('No company selected')),
      );
    }

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.paymentOutId != null ? 'Edit Payment Out' : 'Payment-Out'),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Navigate to bank account management
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Voucher No.',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _voucherNoCtrl.text,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Date',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => _date = picked);
                            }
                          },
                          child: Row(
                            children: [
                              Text(
                                '${_date.day}/${_date.month}/${_date.year}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 20),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSupplierSelector(partiesAsync),
              if (_selectedSupplier != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Party Live Balance: $_currencySymbol ${_livePartyBalance.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: _livePartyBalance > 0 ? Colors.red : Colors.green,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Payment Type',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 12),
              accountsAsync.when(
                data: (accounts) {
                  // Set default Cash account ID if not set
                  if (_paymentLines.isNotEmpty &&
                      _paymentLines[0].accountId == null) {
                    final cashAccount = accounts.firstWhere(
                      (a) => a.accountName == 'Cash',
                      orElse: () => accounts.first,
                    );
                    _paymentLines[0].accountId = cashAccount.id;
                    _paymentLines[0].accountName = cashAccount.accountName;
                    _paymentLines[0].accountIcon = cashAccount.icon;
                  }
                  return Column(
                    children: [
                      ..._paymentLines.asMap().entries.map((entry) {
                        final index = entry.key;
                        final line = entry.value;
                        return _buildPaymentLine(line, accounts, index);
                      }).toList(),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () => _showPaymentTypeDialog(accounts),
                        child: Row(
                          children: [
                            Icon(Icons.add_circle_outline,
                                color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Text(
                              '+ Add Payment Type',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_paymentLines.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Paid',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '$_currencySymbol ${_totalPaid.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Text('Error: $error'),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Opening Balance',
                          style: TextStyle(fontSize: 16),
                        ),
                        Text(
                          '$_currencySymbol ${_previousBalance.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Paid Amount',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        Text(
                          '$_currencySymbol ${_totalPaid.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Closing Balance',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$_currencySymbol ${_closingBalance.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color:
                                _closingBalance > 0 ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _descriptionCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Add Note',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () async {
                      await _showImageSourceDialog();
                    },
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade50,
                      ),
                      child: _selectedImagePath != null
                          ? Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(_selectedImagePath!),
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _selectedImagePath = null;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate,
                                  color: Colors.red.shade700,
                                  size: 28,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Image',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving
                          ? null
                          : () => _savePaymentOut(paymentDao, company, user),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isSaving ? 'Saving...' : 'Save',
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward,
                              size: 20, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupplierSelector(AsyncValue<List<Party>> partiesAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Supplier Name *',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        partiesAsync.when(
          loading: () => Container(
            height: 52,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _selectedSupplier?.name ?? 'Select Supplier',
              style: TextStyle(
                fontSize: 16,
                color: _selectedSupplier == null
                    ? Colors.grey.shade400
                    : Colors.black,
              ),
            ),
          ),
          data: (parties) {
            return SearchableDropdown<Party>(
              items: parties,
              hintText: _selectedSupplier?.name ?? 'Select Supplier',
              isSelected: _selectedSupplier != null,
              onClear: () {
                setState(() {
                  _selectedSupplier = null;
                  _livePartyBalance = 0;
                  _previousBalance = 0;
                });
              },
              onSelected: (selected) async {
                setState(() => _selectedSupplier = selected);
                await _loadPartyBalance(selected);
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
              maxHeight: 300,
            );
          },
        ),
      ],
    );
  }

  Widget _buildPaymentLine(
    PaymentLineDraft line,
    List<PaymentAccount> accounts,
    int index,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Text(
            line.accountIcon ?? '💰',
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.accountName ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (line.referenceNo != null && line.referenceNo!.isNotEmpty)
                  Text(
                    'Ref No. ${line.referenceNo}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() => _paymentLines.removeAt(index));
            },
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: TextField(
              key: ValueKey('amount_${index}_${line.accountId}'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '$_currencySymbol ',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: (value) {
                try {
                  line.amount = double.tryParse(value) ?? 0;
                  setState(() {});
                } catch (e) {
                  print('Error parsing amount: $e');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentTypeDialog(List<PaymentAccount> accounts) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Payment Type',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...accounts.map((account) {
                return ListTile(
                  leading: Text(
                    account.icon ?? '💰',
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(account.accountName),
                  subtitle: account.accountType == PaymentAccountType.bank
                      ? Text(account.bankName ?? '')
                      : null,
                  onTap: () {
                    setState(() {
                      _paymentLines.add(PaymentLineDraft(
                        accountId: account.id,
                        accountName: account.accountName,
                        accountIcon: account.icon,
                        amount: 0,
                      ));
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add_circle, color: Colors.red),
                title: const Text(
                  '+ Add Bank A/c',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAddBankAccountDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddBankAccountDialog() {
    final nameCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    final accountNoCtrl = TextEditingController();
    final ifscCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Bank Account'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Account Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bankCtrl,
                decoration: const InputDecoration(
                  labelText: 'Bank Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: accountNoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Account Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ifscCtrl,
                decoration: const InputDecoration(
                  labelText: 'IFSC Code',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || bankCtrl.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please fill required fields'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final company = ref.read(currentCompanyProvider);
              if (company == null) return;

              final paymentDao = ref.read(paymentDaoProvider);
              await paymentDao.createPaymentAccount(
                companyId: company.id,
                accountType: PaymentAccountType.bank,
                accountName: nameCtrl.text,
                bankName: bankCtrl.text,
                accountNumber:
                    accountNoCtrl.text.isEmpty ? null : accountNoCtrl.text,
                ifscCode: ifscCtrl.text.isEmpty ? null : ifscCtrl.text,
              );

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bank account added successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
                ref.invalidate(paymentAccountsProvider);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _savePaymentOut(
    PaymentDao paymentDao,
    Company company,
    User? user,
  ) async {
    if (_isSaving) return;

    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a supplier'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final validLines = _paymentLines
        .where((l) => l.accountId != null && l.amount > 0)
        .toList();

    if (validLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one payment'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final inputs = validLines
        .map((l) => PaymentLineInput(
              accountId: l.accountId!,
              amount: l.amount,
              referenceNo: l.referenceNo,
            ))
        .toList();

    setState(() => _isSaving = true);

    try {
      PaymentOut? savedPayment;

      if (widget.paymentOutId != null) {
        savedPayment = await paymentDao.updatePaymentOut(
          paymentOutId: widget.paymentOutId!,
          companyId: company.id,
          supplier: _selectedSupplier!,
          voucherDate: _date,
          voucherNo: _voucherNoCtrl.text.trim(),
          previousBalance: _previousBalance,
          lines: inputs,
          description:
              _descriptionCtrl.text.isEmpty ? null : _descriptionCtrl.text,
          attachmentPath: _selectedImagePath,
          userId: user?.id,
        );
      } else {
        savedPayment = await paymentDao.createPaymentOut(
          companyId: company.id,
          supplier: _selectedSupplier!,
          voucherDate: _date,
          voucherNo: _voucherNoCtrl.text.trim(),
          previousBalance: _previousBalance,
          lines: inputs,
          description:
              _descriptionCtrl.text.isEmpty ? null : _descriptionCtrl.text,
          attachmentPath: _selectedImagePath,
          userId: user?.id,
        );
      }

      if (mounted && savedPayment != null) {
        final savedLines = await paymentDao.getPaymentOutLines(savedPayment.id);
        await _showPostSaveActions(
          company: company,
          payment: savedPayment,
          lines: savedLines,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving payment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
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

  Future<void> _showPostSaveActions({
    required Company company,
    required PaymentOut payment,
    required List<PaymentOutLine> lines,
  }) async {
    if (!mounted || _selectedSupplier == null) return;

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
                'Payment Saved',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.blue),
                title: const Text('Share Receipt'),
                onTap: () async {
                  Navigator.pop(context);
                  await PaymentOutReceiptGenerator.shareReceipt(
                    context: this.context,
                    company: company,
                    supplier: _selectedSupplier!,
                    payment: payment,
                    lines: lines,
                    totalAmount: payment.totalAmount,
                    currencySymbol: _currencySymbol,
                    imagePath: payment.attachmentPath,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('Share as PDF'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final pdfBytes =
                        await PaymentOutReceiptGenerator.generateReceiptPdf(
                      company: company,
                      supplier: _selectedSupplier!,
                      payment: payment,
                      lines: lines,
                      totalAmount: payment.totalAmount,
                      currencySymbol: _currencySymbol,
                      imagePath: payment.attachmentPath,
                    );
                    final tempDir = await getTemporaryDirectory();
                    final file = File(
                        '${tempDir.path}/payment_out_${payment.voucherNo}.pdf');
                    await file.writeAsBytes(pdfBytes);
                    await Share.shareXFiles(
                      [XFile(file.path)],
                      subject: 'Payment Out Voucher - ${payment.voucherNo}',
                    );
                  } catch (e) {
                    _showSnackBar('Error sharing PDF: $e', isError: true);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.download, color: Colors.teal),
                title: const Text('Download PDF'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final pdfBytes =
                        await PaymentOutReceiptGenerator.generateReceiptPdf(
                      company: company,
                      supplier: _selectedSupplier!,
                      payment: payment,
                      lines: lines,
                      totalAmount: payment.totalAmount,
                      currencySymbol: _currencySymbol,
                      imagePath: payment.attachmentPath,
                    );
                    final dir = await getApplicationDocumentsDirectory();
                    final fileName = 'payment_out_${payment.voucherNo}.pdf';
                    final file = File('${dir.path}/$fileName');
                    await file.writeAsBytes(pdfBytes);
                    _showSnackBar('PDF saved: ${file.path}');
                  } catch (e) {
                    _showSnackBar('Error downloading PDF: $e', isError: true);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.print, color: Colors.deepPurple),
                title: const Text('Print Receipt'),
                onTap: () async {
                  Navigator.pop(context);
                  final Uint8List pdfBytes =
                      await PaymentOutReceiptGenerator.generateReceiptPdf(
                    company: company,
                    supplier: _selectedSupplier!,
                    payment: payment,
                    lines: lines,
                    totalAmount: payment.totalAmount,
                    currencySymbol: _currencySymbol,
                    imagePath: payment.attachmentPath,
                  );
                  await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.add_circle_outline, color: Colors.orange),
                title: const Text('New Payment-Out'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    this.context,
                    MaterialPageRoute(
                      builder: (_) => const PaymentOutFormScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.list_alt, color: Colors.blueGrey),
                title: const Text('Back to Payment List'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).pop(true);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
