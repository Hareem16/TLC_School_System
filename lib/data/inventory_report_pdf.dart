import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../school_profile.dart';
import 'inventory_repository.dart';

class InventoryReportPdf {
  static Future<Uint8List> build({
    required SchoolProfile profile,
    required List<InventoryItem> items,
  }) async {
    final logoBytes = (await rootBundle.load('assets/images/tlc_logo.png'))
        .buffer
        .asUint8List();
    final logo = pw.MemoryImage(logoBytes);
    final document = pw.Document();
    final accent = PdfColor.fromInt(profile.primaryColor.toARGB32());

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 16),
          child: pw.Row(
            children: [
              pw.Image(logo, width: 42, height: 42),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      profile.schoolName,
                      style: pw.TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'INVENTORY & SUPPLIES • ${profile.academicYear}',
                      style: const pw.TextStyle(
                        color: PdfColors.grey700,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Text('Items: ${items.length}'),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            '${profile.developerCredit}  •  Page ${context.pageNumber}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              _row(
                ['Item', 'Category', 'Unit', 'On hand', 'Reorder level', 'Status'],
                header: true,
                accent: accent,
              ),
              for (final item in items)
                _row(
                  [
                    item.name,
                    item.category,
                    item.unit,
                    item.quantityOnHand.toStringAsFixed(2),
                    item.reorderLevel.toStringAsFixed(2),
                    item.isLowStock ? 'Low stock' : 'In stock',
                  ],
                  header: false,
                  accent: accent,
                ),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }

  static pw.TableRow _row(
    List<String> values, {
    required bool header,
    required PdfColor accent,
  }) => pw.TableRow(
    decoration: header ? pw.BoxDecoration(color: accent) : null,
    children: values
        .map(
          (value) => pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(
              value,
              style: pw.TextStyle(
                color: header ? PdfColors.white : PdfColors.grey900,
                fontSize: 8,
                fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        )
        .toList(growable: false),
  );
}
