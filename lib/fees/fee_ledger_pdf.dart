import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/fee_repository.dart';
import '../school_profile.dart';

class FeeLedgerPdf {
  static Future<Uint8List> build({
    required SchoolProfile profile,
    required String monthLabel,
    required List<FeeCharge> charges,
  }) async {
    final logoBytes = (await rootBundle.load('assets/images/tlc_logo.png'))
        .buffer
        .asUint8List();
    final logo = pw.MemoryImage(logoBytes);
    final document = pw.Document();
    final accent = PdfColor.fromInt(profile.primaryColor.toARGB32());
    final totalDue = charges.fold<double>(
      0,
      (total, charge) => total + charge.amountDue,
    );
    final totalPaid = charges.fold<double>(
      0,
      (total, charge) => total + charge.amountPaid,
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(26),
        header: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
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
                      'FEE LEDGER • $monthLabel',
                      style: pw.TextStyle(
                        color: PdfColors.grey700,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Text('PKR ${totalDue.toStringAsFixed(2)} billed'),
              pw.SizedBox(width: 14),
              pw.Text('PKR ${totalPaid.toStringAsFixed(2)} collected'),
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
                [
                  'G.R. No.',
                  'Student',
                  'Class',
                  'Amount Due',
                  'Paid',
                  'Balance',
                  'Status',
                ],
                header: true,
                accent: accent,
              ),
              for (final charge in charges)
                _row(
                  [
                    charge.admissionNumber,
                    charge.studentName,
                    charge.className,
                    'PKR ${charge.amountDue.toStringAsFixed(2)}',
                    'PKR ${charge.amountPaid.toStringAsFixed(2)}',
                    'PKR ${charge.balance.toStringAsFixed(2)}',
                    charge.status,
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
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(
              value,
              style: pw.TextStyle(
                color: header ? PdfColors.white : PdfColors.grey900,
                fontSize: 7,
                fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        )
        .toList(growable: false),
  );
}
