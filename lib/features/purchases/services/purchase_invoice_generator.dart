// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/company_model.dart';
import '../../../data/models/inventory_models.dart';
import '../../../data/models/invoice_stock_models.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/transaction_model.dart';

class PurchaseInvoiceGenerator {
  static final _dateFormat = DateFormat('dd MMM, yyyy hh:mm a');
  static final _currencyFormat = NumberFormat('#,##,##0.00');

  static String _currencySymbol(Company company) {
    const symbols = {
      'PKR': '₨',
      'USD': r'$',
      'EUR': '€',
      'GBP': '£',
      'INR': '₹',
      'SAR': 'ر.س',
      'AED': 'د.إ',
    };
    final currency = company.primaryCurrency ?? 'PKR';
    return symbols[currency] ?? currency;
  }

  // Generate purchase invoice as image
  static Future<Uint8List> generatePurchaseInvoiceImage({
    required Company company,
    required Party supplier,
    required Invoice invoice,
    required Transaction transaction,
    required List<Map<String, dynamic>>
        lineItems, // product name, qty, rate, amount
    List<Map<String, dynamic>>? paymentLines,
    double? supplierBalance,
    double? openingBalance,
    String? notes,
    String? attachmentImagePath,
  }) async {
    try {
      final currencySymbol = _currencySymbol(company);
      // Debug: Print opening balance parameter
      print('=== PURCHASE OPENING BALANCE DEBUG ===');
      print('openingBalance parameter: $openingBalance');
      print('supplierBalance parameter: $supplierBalance');
      print('======================================');

      // ── Pre-load attachment image and calculate dynamic canvas height ─────
      ui.Image? attachmentUiImage;
      if (attachmentImagePath != null && attachmentImagePath.isNotEmpty) {
        try {
          Uint8List? attachBytes;
          final lowerPath = attachmentImagePath.toLowerCase();
          final isRemote = lowerPath.startsWith('http://') ||
              lowerPath.startsWith('https://');

          if (isRemote) {
            final response = await http.get(Uri.parse(attachmentImagePath));
            if (response.statusCode >= 200 && response.statusCode < 300) {
              attachBytes = response.bodyBytes;
            }
          } else {
            final attachFile = File(attachmentImagePath);
            if (await attachFile.exists()) {
              attachBytes = await attachFile.readAsBytes();
            }
          }

          if (attachBytes != null && attachBytes.isNotEmpty) {
            final codec = await ui.instantiateImageCodec(attachBytes);
            final frame = await codec.getNextFrame();
            attachmentUiImage = frame.image;
          }
        } catch (e) {
          print('Warning: could not load attachment image: $e');
        }
      }

      double extraCanvasHeight = 0;
      if (notes != null && notes.isNotEmpty) {
        final estimatedLines = (notes.length / 70).ceil().clamp(1, 30);
        extraCanvasHeight += 60.0 + (estimatedLines * 24.0);
      }
      if (attachmentUiImage != null) {
        final scaleFactor = 720.0 / attachmentUiImage.width;
        final scaledH =
            (attachmentUiImage.height * scaleFactor).clamp(0.0, 500.0);
        extraCanvasHeight += scaledH + 80.0;
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final canvasWidth = 800.0;
      final canvasHeight = 1400.0 + extraCanvasHeight;

      // Background - use a slightly off-white background for better contrast
      final paint = Paint()..color = const Color(0xFFFAFAFA);
      canvas.drawRect(Rect.fromLTWH(0, 0, canvasWidth, canvasHeight), paint);

      // Add a border
      final borderPaint = Paint()
        ..color = Colors.grey.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(
          Rect.fromLTWH(10, 10, canvasWidth - 20, canvasHeight - 20),
          borderPaint);

      // Header - Company name
      _drawText(
        canvas,
        company.name,
        const Offset(40, 40),
        const TextStyle(
            fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
      );

      // Invoice ID
      _drawText(
        canvas,
        invoice.id.toString(),
        const Offset(40, 75),
        TextStyle(fontSize: 14, color: Colors.grey.shade600),
      );

      // Title
      _drawText(
        canvas,
        'Purchase Invoice',
        const Offset(280, 150),
        const TextStyle(
            fontSize: 32, fontWeight: FontWeight.bold, color: Colors.orange),
      );

      // Supplier details
      _drawText(
        canvas,
        'Bill From:',
        const Offset(40, 220),
        TextStyle(fontSize: 14, color: Colors.grey.shade600),
      );
      _drawText(
        canvas,
        supplier.name,
        const Offset(40, 245),
        const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black87),
      );
      if (supplier.phone != null && supplier.phone!.isNotEmpty) {
        _drawText(
          canvas,
          'Phone: ${supplier.phone}',
          const Offset(40, 270),
          const TextStyle(fontSize: 14, color: Colors.black87),
        );
      }

      // Date & Time
      _drawText(
        canvas,
        'Date & Time: ${_dateFormat.format(invoice.invoiceDate)}',
        const Offset(600, 280),
        const TextStyle(fontSize: 14, color: Colors.black87),
      );

      // Items table
      double yPos = 340;

      // Table header background
      final headerPaint = Paint()
        ..color = Colors.orange.shade100
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(40, yPos, 720, 35), headerPaint);

      // Table headers
      _drawText(
          canvas,
          'Item',
          Offset(50, yPos + 8),
          const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87));
      _drawRightAlignedText(
          canvas,
          'Qty',
          Offset(480, yPos + 8),
          const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87));
      _drawRightAlignedText(
          canvas,
          'Rate',
          Offset(600, yPos + 8),
          const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87));
      _drawRightAlignedText(
          canvas,
          'Amount',
          Offset(750, yPos + 8),
          const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87));

      yPos += 35;

      // Table border - draw the header border
      final headerBorderPaint = Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRect(const Rect.fromLTWH(40, 340, 720, 35), headerBorderPaint);

      // Calculate totals from line items instead of relying on database values
      double calculatedSubTotal = 0;
      double totalQuantity = 0;
      double totalRate = 0;

      // Debug: Print lineItems data
      print('=== PURCHASE LINE ITEMS DEBUG ===');
      print('lineItems count: ${lineItems.length}');
      for (int i = 0; i < lineItems.length; i++) {
        print('Item $i: ${lineItems[i]}');
      }
      print('===================================');

      // Debug: Check if lineItems is empty
      if (lineItems.isEmpty) {
        print('WARNING: lineItems is empty in generatePurchaseInvoiceImage');
        // Add a placeholder item to show there's an issue
        _drawText(
            canvas,
            'No items found',
            Offset(50, yPos + 8),
            TextStyle(
                fontSize: 13,
                color: Colors.red.shade700,
                fontStyle: FontStyle.italic));
        yPos += 30;
      } else {
        print('Rendering ${lineItems.length} line items');
        for (int index = 0; index < lineItems.length; index++) {
          final line = lineItems[index];
          print('Processing line item $index: $line');

          // Try different possible key names for flexibility
          final productName = line['productName'] as String? ??
              line['product_name'] as String? ??
              line['item_name'] as String? ??
              line['name'] as String? ??
              'Unknown Product';

          final qty =
              (line['qty'] as num? ?? line['quantity'] as num? ?? 0).toDouble();

          final rate = (line['rate'] as num? ??
                  line['price'] as num? ??
                  line['unit_price'] as num? ??
                  0)
              .toDouble();

          final amount = (line['amount'] as num?) != null
              ? (line['amount'] as num).toDouble()
              : qty * rate;

          calculatedSubTotal += amount;
          totalQuantity += qty;
          totalRate += rate;

          print(
              'Rendering: $productName, Qty: $qty, Rate: $rate, Amount: $amount');

          canvas.drawLine(Offset(40, yPos), Offset(760, yPos), borderPaint);

          // Item name (left aligned)
          _drawText(canvas, productName, Offset(50, yPos + 8),
              const TextStyle(fontSize: 13, color: Colors.black87));

          // Quantity (right aligned)
          final qtyText = qty == qty.roundToDouble()
              ? qty.toStringAsFixed(0)
              : qty.toStringAsFixed(2);
          _drawRightAlignedText(canvas, qtyText, Offset(480, yPos + 8),
              const TextStyle(fontSize: 13, color: Colors.black87));

          // Rate (right aligned)
          _drawRightAlignedText(
              canvas,
              _currencyFormat.format(rate),
              Offset(600, yPos + 8),
              const TextStyle(fontSize: 13, color: Colors.black87));

          // Amount (right aligned)
          _drawRightAlignedText(
              canvas,
              _currencyFormat.format(amount),
              Offset(750, yPos + 8),
              const TextStyle(fontSize: 13, color: Colors.black87));

          yPos += 30;
        }
      }

      // Bottom border
      canvas.drawLine(Offset(40, yPos), Offset(760, yPos), borderPaint);

      // Draw the complete table border
      final tableBorderPaint = Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      // Left border
      canvas.drawLine(
          const Offset(40, 340), Offset(40, yPos), tableBorderPaint);
      // Right border
      canvas.drawLine(
          const Offset(760, 340), Offset(760, yPos), tableBorderPaint);

      // Display total quantity and total rate
      yPos += 10;
      _drawText(
          canvas,
          'Total Qty: ${totalQuantity == totalQuantity.roundToDouble() ? totalQuantity.toStringAsFixed(0) : totalQuantity.toStringAsFixed(2)} | Total Rate: $currencySymbol ${_currencyFormat.format(totalRate)}',
          Offset(520, yPos),
          const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange));

      yPos += 20;

      // Amounts section
      final amountBoxPaint = Paint()
        ..color = Colors.grey.shade100
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(40, yPos, 720, 50),
          const Radius.circular(8),
        ),
        amountBoxPaint,
      );

      final amountBorderPaint = Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(40, yPos, 720, 50),
          const Radius.circular(8),
        ),
        amountBorderPaint,
      );

      _drawText(
          canvas,
          'Total:',
          Offset(60, yPos + 20),
          const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87));
      _drawRightAlignedText(
          canvas,
          '$currencySymbol ${_currencyFormat.format(calculatedSubTotal)}',
          Offset(740, yPos + 20),
          const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87));

      yPos += 70;

      // Always show Payment Summary section using the balance snapshot saved on invoice
      final previousBalance = invoice.previousBalance;
      final totalPaid = invoice.paidAmount > 0
          ? invoice.paidAmount
          : (paymentLines?.fold<double>(
                  0.0,
                  (sum, p) =>
                      sum + ((p['amount'] as num?)?.toDouble() ?? 0.0)) ??
              0.0);

      // Payment Summary - Clean Simple Design
      _drawText(
          canvas,
          'Payment Summary',
          Offset(40, yPos),
          const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black));
      yPos += 30;

      // Simple Payment Summary Box
      final summaryBoxPaint = Paint()
        ..color = Colors.grey.shade100
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(40, yPos, 720, 150),
          const Radius.circular(4),
        ),
        summaryBoxPaint,
      );

      final summaryBorderPaint = Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(40, yPos, 720, 150),
          const Radius.circular(4),
        ),
        summaryBorderPaint,
      );

      yPos += 20;

      // Use calculated total instead of database value for accuracy
      final totalToDisplay =
          calculatedSubTotal > 0 ? calculatedSubTotal : invoice.grandTotal;

      print(
          'GENERATOR: Database total: ${invoice.grandTotal}, Calculated total: $calculatedSubTotal, Using: $totalToDisplay');

      // Previous Balance
      _drawText(canvas, 'Previous Balance:', Offset(60, yPos),
          const TextStyle(fontSize: 14, color: Colors.black87));
      _drawText(
          canvas,
          '$currencySymbol ${_currencyFormat.format(previousBalance)}',
          Offset(600, yPos),
          const TextStyle(fontSize: 14, color: Colors.black87));
      yPos += 25;

      // Total Amount - simple styling
      _drawText(canvas, 'Total Amount:', Offset(60, yPos),
          const TextStyle(fontSize: 14, color: Colors.black87));
      _drawText(
          canvas,
          '$currencySymbol ${_currencyFormat.format(totalToDisplay)}',
          Offset(600, yPos),
          const TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black));
      yPos += 25;

      // Paid Amount - simple styling
      _drawText(canvas, 'Paid Amount:', Offset(60, yPos),
          const TextStyle(fontSize: 14, color: Colors.black87));
      _drawText(
          canvas,
          '$currencySymbol ${_currencyFormat.format(totalPaid)}',
          Offset(600, yPos),
          const TextStyle(fontSize: 14, color: Colors.black));
      yPos += 25;

      // Closing Balance
      final closingBalance = invoice.remainingBalance;
      _drawText(canvas, 'Closing Balance:', Offset(60, yPos),
          const TextStyle(fontSize: 14, color: Colors.black87));
      _drawText(
          canvas,
          closingBalance > 0
              ? '$currencySymbol ${_currencyFormat.format(closingBalance)}'
              : 'CLEARED',
          Offset(600, yPos),
          TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: closingBalance > 0 ? Colors.red : Colors.green));

      // Supplier Current Balance - Clean Design
      if (supplierBalance != null) {
        yPos += 30;

        // Simple supplier balance container
        final balanceBoxPaint = Paint()
          ..color = Colors.grey.shade100
          ..style = PaintingStyle.fill;

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(40, yPos, 720, 50),
            const Radius.circular(4),
          ),
          balanceBoxPaint,
        );

        final balanceBorderPaint = Paint()
          ..color = Colors.grey.shade400
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(40, yPos, 720, 50),
            const Radius.circular(4),
          ),
          balanceBorderPaint,
        );

        _drawText(canvas, 'Supplier Current Balance:', Offset(60, yPos + 15),
            const TextStyle(fontSize: 14, color: Colors.black87));

        _drawText(
            canvas,
            supplierBalance >= 0
                ? 'We Owe: $currencySymbol ${_currencyFormat.format(supplierBalance.abs())}'
                : 'They Owe: $currencySymbol ${_currencyFormat.format(supplierBalance.abs())}',
            Offset(500, yPos + 15),
            const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black));
      }

      // ── Notes section ─────────────────────────────────────────────────────
      if (notes != null && notes.isNotEmpty) {
        yPos += 20;
        _drawText(
          canvas,
          'Notes',
          Offset(40, yPos),
          const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
        );
        yPos += 28;

        final notesSpan = TextSpan(
          text: notes,
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        );
        final notesPainter = TextPainter(
          text: notesSpan,
          textDirection: ui.TextDirection.ltr,
          textAlign: TextAlign.left,
        );
        notesPainter.layout(minWidth: 0, maxWidth: 680);
        final notesBoxH = notesPainter.height + 24;

        final notesBgPaint = Paint()
          ..color = const Color(0xFFFFF8E1) // amber-50
          ..style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(40, yPos, 720, notesBoxH),
              const Radius.circular(6)),
          notesBgPaint,
        );
        final notesBorderPaint = Paint()
          ..color = const Color(0xFFFFD54F) // amber-300
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(40, yPos, 720, notesBoxH),
              const Radius.circular(6)),
          notesBorderPaint,
        );
        notesPainter.paint(canvas, Offset(52, yPos + 12));
        yPos += notesBoxH + 24;
      }

      yPos += 70;
      // ── Attachment image section ───────────────────────────────────────────
      if (attachmentUiImage != null) {
        _drawText(
          canvas,
          'Attachment',
          Offset(40, yPos),
          const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
        );
        yPos += 28;

        final scaleFactor = 720.0 / attachmentUiImage.width;
        final scaledW = 720.0;
        final scaledH =
            (attachmentUiImage.height * scaleFactor).clamp(0.0, 500.0);

        final imgBorderPaint = Paint()
          ..color = Colors.grey.shade400
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRect(
            Rect.fromLTWH(40, yPos, scaledW, scaledH), imgBorderPaint);

        final srcRect = Rect.fromLTWH(0, 0, attachmentUiImage.width.toDouble(),
            attachmentUiImage.height.toDouble());
        final dstRect = Rect.fromLTWH(40, yPos, scaledW, scaledH);
        canvas.drawImageRect(attachmentUiImage, srcRect, dstRect, Paint());

        yPos += scaledH + 24;
      }

      final picture = recorder.endRecording();
      final img =
          await picture.toImage(canvasWidth.toInt(), canvasHeight.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('Failed to generate image data');
      }

      final imageBytes = byteData.buffer.asUint8List();
      print('Generated purchase invoice image with ${imageBytes.length} bytes');
      return imageBytes;
    } catch (e) {
      print('Error generating purchase invoice image: $e');
      rethrow;
    }
  }

  /// Loads all purchase invoice data from [isar] and renders the PNG.
  /// Notes and attachmentPath are read automatically from the stored Invoice.
  static Future<Uint8List> buildImageById({
    required int invoiceId,
    required Isar isar,
    required Company company,
  }) async {
    final invoice = await isar.invoices.get(invoiceId);
    if (invoice == null)
      throw Exception('Purchase Invoice #$invoiceId not found');

    final supplier = await isar.partys.get(invoice.partyId);
    if (supplier == null) throw Exception('Supplier not found');

    final transaction = await isar.transactions.get(invoice.transactionId);
    if (transaction == null) throw Exception('Transaction not found');

    final transactionLines = await isar.transactionLines
        .filter()
        .transactionIdEqualTo(transaction.id)
        .findAll();

    final lineItems = <Map<String, dynamic>>[];
    for (final line in transactionLines) {
      final product = line.productId != null
          ? await isar.products.get(line.productId!)
          : null;
      lineItems.add({
        'productName': product?.name ?? 'Unknown Product',
        'qty': line.quantity,
        'rate': line.unitPrice,
      });
    }

    return generatePurchaseInvoiceImage(
      company: company,
      supplier: supplier,
      invoice: invoice,
      transaction: transaction,
      lineItems: lineItems,
      openingBalance: invoice.previousBalance,
      notes: invoice.notes,
      attachmentImagePath: invoice.attachmentPath,
    );
  }

  /// Share an existing purchase invoice as an image.
  /// All data (including notes & attachment) is loaded from Isar automatically.
  static Future<void> shareExistingAsImage({
    required int invoiceId,
    required Isar isar,
    required Company company,
  }) async {
    final imageBytes = await buildImageById(
        invoiceId: invoiceId, isar: isar, company: company);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/purchase_invoice_$invoiceId.png');
    await file.writeAsBytes(imageBytes);
    await Share.shareXFiles([XFile(file.path)], text: 'Purchase Invoice');
    Future.delayed(const Duration(seconds: 30), () {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    });
  }

  static Future<void> _shareAsImage(
    Company company,
    Party supplier,
    Invoice invoice,
    Transaction transaction,
    List<Map<String, dynamic>> lineItems,
    List<Map<String, dynamic>>? paymentLines,
    double? supplierBalance,
    double? openingBalance, [
    String? notes,
    String? attachmentImagePath,
  ]) async {
    try {
      print(
          'Starting purchase invoice image generation for invoice ${transaction.referenceNo}');
      print('Line items count: ${lineItems.length}');

      final imageBytes = await generatePurchaseInvoiceImage(
        company: company,
        supplier: supplier,
        invoice: invoice,
        transaction: transaction,
        lineItems: lineItems,
        paymentLines: paymentLines,
        supplierBalance: supplierBalance,
        openingBalance: openingBalance,
        notes: notes,
        attachmentImagePath: attachmentImagePath,
      );

      print(
          'Purchase invoice image generated successfully, size: ${imageBytes.length} bytes');

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'purchase_invoice_${transaction.referenceNo}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      print('Purchase invoice image saved to: ${file.path}');

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Purchase Invoice - ${transaction.referenceNo}',
      );

      print('Purchase invoice image shared successfully');
    } catch (e) {
      print('Error sharing purchase invoice image: $e');
      rethrow;
    }
  }

  // Share purchase invoice with options
  static Future<void> sharePurchaseInvoice({
    required BuildContext context,
    required Company company,
    required Party supplier,
    required Invoice invoice,
    required Transaction transaction,
    required List<Map<String, dynamic>> lineItems,
    List<Map<String, dynamic>>? paymentLines,
    double? supplierBalance,
    double? openingBalance,
    String? notes,
    String? attachmentImagePath,
  }) async {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          alignment: Alignment.topCenter,
          insetPadding: const EdgeInsets.only(top: 100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Share Purchase Invoice',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.image, color: Colors.blue),
                  title: const Text('Share as Image'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _shareAsImage(
                        company,
                        supplier,
                        invoice,
                        transaction,
                        lineItems,
                        paymentLines,
                        supplierBalance,
                        openingBalance,
                        notes,
                        attachmentImagePath);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Direct share as image method
  static Future<void> shareAsImage({
    required Company company,
    required Party supplier,
    required Invoice invoice,
    required Transaction transaction,
    required List<Map<String, dynamic>> lineItems,
    List<Map<String, dynamic>>? paymentLines,
    double? supplierBalance,
    double? openingBalance,
    String? notes,
    String? attachmentImagePath,
  }) async {
    await _shareAsImage(
        company,
        supplier,
        invoice,
        transaction,
        lineItems,
        paymentLines,
        supplierBalance,
        openingBalance,
        notes,
        attachmentImagePath);
  }

  static void _drawText(
      Canvas canvas, String text, Offset position, TextStyle style) {
    try {
      final textSpan = TextSpan(text: text, style: style);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.left,
      );

      textPainter.layout();

      // Add bounds checking
      if (position.dx >= 0 && position.dy >= 0) {
        textPainter.paint(canvas, position);
      } else {
        print('Warning: Invalid text position $position for text: $text');
      }
    } catch (e) {
      print('Error drawing text "$text" at $position: $e');
    }
  }

  static void _drawRightAlignedText(
      Canvas canvas, String text, Offset position, TextStyle style) {
    try {
      final textSpan = TextSpan(text: text, style: style);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.right,
      );

      textPainter.layout();

      // Calculate right-aligned position
      final rightAlignedPosition = Offset(
        position.dx - textPainter.width,
        position.dy,
      );

      // Add bounds checking
      if (rightAlignedPosition.dx >= 0 && rightAlignedPosition.dy >= 0) {
        textPainter.paint(canvas, rightAlignedPosition);
      } else {
        print(
            'Warning: Invalid right-aligned text position $rightAlignedPosition for text: $text');
      }
    } catch (e) {
      print('Error drawing right-aligned text "$text" at $position: $e');
    }
  }
}
