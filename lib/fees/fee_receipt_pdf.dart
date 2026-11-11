

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/fee_repository.dart';
import '../school_profile.dart';

class FeeReceiptPdf {
  static Future<Uint8List> build({
    required SchoolProfile profile,
    required FeePayment payment,
  }) async {
    final logoBytes = (await rootBundle.load('assets/images/tlc_logo.png'))
        .buffer
        .asUint8List();
    final logo = pw.MemoryImage(logoBytes);
    final document = pw.Document();
    final accent = PdfColor.fromInt(profile.primaryColor.toARGB32());

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: accent, width: 1.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Image(logo, width: 54, height: 54, fit: pw.BoxFit.contain),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          profile.schoolName,
                          style: pw.TextStyle(
                            color: accent,
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (profile.address.trim().isNotEmpty)
                          pw.Text(profile.address),
                        if (profile.phone.trim().isNotEmpty)
                          pw.Text(profile.phone),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 8),
                color: PdfColor.fromInt(0xFFFCEBEC),
                child: pw.Center(
                  child: pw.Text(
                    'FEE PAYMENT RECEIPT',
                    style: pw.TextStyle(
                      color: accent,
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 12),
              _detailRow('Receipt No.', payment.receiptNumber),
              _detailRow('Date', _dateLabel(payment.paidAt)),
              _detailRow('Student', payment.studentName),
              _detailRow('G.R. No.', payment.admissionNumber),
              _detailRow('Class', payment.className),
              _detailRow('Fee month', _monthLabel(payment.monthKey)),
              pw.Divider(color: accent),
              _detailRow('Monthly fee', _money(payment.amountDue)),
              _detailRow('Paid on this receipt', _money(payment.amountPaidThisReceipt)),
              _detailRow('Total paid for this month', _money(payment.totalPaid)),
              _detailRow('Remaining balance', _money(payment.balance)),
              _detailRow('Payment method', payment.paymentMethod),
              if (payment.receivedByName.trim().isNotEmpty)
                _detailRow(
                  'Received by',
                  '${payment.receivedByName} (${payment.receivedByRole})',
                ),
              if (payment.notes.trim().isNotEmpty)
                _detailRow('Notes', payment.notes),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _signatureLine('Parent / Guardian'),
                  _signatureLine('Authorized signature'),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  profile.developerCredit,
                  style: pw.TextStyle(
                    color: PdfColors.grey700,
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return document.save();
  }

  static pw.Widget _detailRow(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 145,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
        ),
        pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: 9))),
      ],
    ),
  );

  static pw.Widget _signatureLine(String label) => pw.SizedBox(
    width: 145,
    child: pw.Column(
      children: [
        pw.Divider(),
        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
      ],
    ),
  );

  static String _money(double amount) => 'PKR ${amount.toStringAsFixed(2)}';

  static String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  static String _monthLabel(String monthKey) {
    final date = DateTime.parse('$monthKey-01');
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}
