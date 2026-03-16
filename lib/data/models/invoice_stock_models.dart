import 'package:isar/isar.dart';

part 'invoice_stock_models.g.dart';

enum InvoiceType { sale, purchase }

@collection
class Invoice {
  Id id = Isar.autoIncrement;

  @Index()
  late int companyId;

  @Index()
  late int transactionId;

  @Index()
  @enumerated
  late InvoiceType invoiceType;

  @Index()
  late int partyId;

  @Index()
  late DateTime invoiceDate;

  DateTime? dueDate;

  double grandTotal = 0;
  String? status;

  // Running balance fields for purchase system
  double previousBalance = 0; // Unpaid balance from previous invoices
  double paidAmount = 0; // Amount paid on this invoice
  double remainingBalance =
      0; // Unpaid amount (previousBalance + grandTotal - paidAmount)
  String? invoiceNumber; // For better tracking

  /// Optional notes / remarks entered by the user on the sale form.
  String? notes;

  /// Absolute file-system path to a user-attached image (stored on device).
  String? attachmentPath;
}

enum StockMovementType {
  inPurchase,
  outSale,
  inAdjustment,
  outAdjustment,
}

@collection
class StockLedger {
  Id id = Isar.autoIncrement;

  @Index()
  late int companyId;

  @Index()
  late int productId;

  @Index()
  late DateTime date;

  @Index()
  @enumerated
  late StockMovementType movementType;

  double quantityDelta = 0;
  double unitCost = 0; // Cost per unit for this movement
  double totalCost = 0; // Total cost (quantity * unitCost)

  int? transactionId;
  int? invoiceId;
}
