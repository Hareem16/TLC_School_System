import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/fee_repository.dart';
import '../school_profile.dart';

class FeeVoucherPdf {
  static Future<Uint8List> build({
    required SchoolProfile profile,
    required List<FeeCharge> charges,
  }) async {
    if (charges.isEmpty) {
      throw ArgumentError.value(
        charges,
        'charges',
        'At least one charge is required.',
      );
    }
    final logoBytes = (await rootBundle.load('assets/images/tlc_logo.png'))
        .buffer
        .asUint8List();
    return compute(FeeVoucherPdf._buildFeeVoucherPdfInBackground, {
      'profile': profile.toDatabaseMap(),
      'logoBytes': logoBytes,
      'charges': charges
          .map(
            (charge) => <String, Object?>{
              'fee_id': charge.id,
              'student_id': charge.studentId,
              'admission_number': charge.admissionNumber,
              'student_name': charge.studentName,
              'guardian_name': charge.guardianName,
              'class_name': charge.className,
              'month_key': charge.monthKey,
              'family_no': charge.familyNo,
              'amount_due': charge.amountDue,
              'amount_paid': charge.amountPaid,
            },
          )
          .toList(growable: false),
    });
  }

  static Future<Uint8List> _buildFeeVoucherPdfInBackground(
    Map<String, Object?> request,
  ) {
    final profile = SchoolProfile.fromDatabaseMap(
      Map<String, Object?>.from(request['profile']! as Map),
    );
    final logo = pw.MemoryImage(request['logoBytes']! as Uint8List);
    final charges = (request['charges']! as List).map(
      (row) => FeeCharge.fromDatabaseMap(Map<String, Object?>.from(row as Map)),
    );
    final document = pw.Document();
    for (final charge in charges) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5.landscape,
          margin: const pw.EdgeInsets.all(14),
          build: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(
                width: (PdfPageFormat.a5.landscape.width - 36) / 2,
                height: PdfPageFormat.a5.landscape.height - 28,
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: pw.Alignment.center,
                  child: pw.SizedBox(
                    width: (PdfPageFormat.a5.landscape.width - 36) / 2,
                    child: FeeVoucherPdf._voucher(profile, charge, logo),
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.SizedBox(
                width: (PdfPageFormat.a5.landscape.width - 36) / 2,
                height: PdfPageFormat.a5.landscape.height - 28,
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: pw.Alignment.center,
                  child: pw.SizedBox(
                    width: (PdfPageFormat.a5.landscape.width - 36) / 2,
                    child: FeeVoucherPdf._voucher(profile, charge, logo),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return document.save();
  }

  static pw.Widget _voucher(
    SchoolProfile profile,
    FeeCharge charge,
    pw.MemoryImage logo,
  ) {
    final accent = PdfColor.fromInt(profile.primaryColor.toARGB32());
    final issueDate = DateTime.parse('${charge.monthKey}-01');
    final dueDate = DateTime(issueDate.year, issueDate.month, 10);
    final validityDate = DateTime(issueDate.year, issueDate.month, 12);
    final month = _shortMonth(issueDate);
    final challanNumber =
        '${charge.admissionNumber}-${charge.monthKey.replaceAll('-', '')}';

    return pw.Container(
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Image(logo, width: 34, height: 34, fit: pw.BoxFit.contain),
              pw.SizedBox(width: 7),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      profile.schoolName,
                      textAlign: pw.TextAlign.center,
                      maxLines: 2,
                      style: pw.TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (profile.address.trim().isNotEmpty)
                      pw.Text(
                        profile.address,
                        textAlign: pw.TextAlign.center,
                        maxLines: 1,
                        style: const pw.TextStyle(fontSize: 6.5),
                      ),
                    if (profile.phone.trim().isNotEmpty)
                      pw.Text(
                        profile.phone,
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 6.5),
                      ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            '${profile.bankName}  |  A/C: ${profile.bankAccount}',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          ),
          pw.Divider(color: accent, thickness: 1),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            color: PdfColor.fromInt(0xFFFCEBEC),
            child: pw.Text(
              'FEE VOUCHER',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                color: accent,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 3),
          _detailRow(
            'G.R. No.',
            charge.admissionNumber,
            'Challan #',
            challanNumber,
          ),
          _detailRow(
            'Name',
            charge.studentName,
            'Issue On',
            _dateLabel(issueDate),
          ),
          _detailRow(
            'F-Name',
            charge.guardianName,
            'Adm. No.',
            charge.admissionNumber,
          ),
          _detailRow('Class', charge.className, 'Month', month),
          _detailRow(
            'Family No.',
            charge.familyNo.trim().isEmpty ? 'Not assigned' : charge.familyNo,
            '',
            '',
          ),
          pw.SizedBox(height: 3),
          pw.Table(
            border: pw.TableBorder(
              top: pw.BorderSide(color: accent),
              bottom: pw.BorderSide(color: accent),
              horizontalInside: const pw.BorderSide(
                color: PdfColors.grey400,
                width: 0.4,
              ),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.6),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
            },
            children: [
              _feeRow(
                'Head of Accounts',
                '@Rs.',
                months: 'Months',
                isHeader: true,
                color: accent,
              ),
              _feeRow('Tuition Fee', _money(charge.amountDue), months: month),
              _feeRow('Admission Fee', '0'),
              _feeRow('Annual Charges', '0'),
              _feeRow('Lab Charges', '0'),
              _feeRow('Stationary Charges', '0'),
              _feeRow('Arrears', '0'),
            ],
          ),
          pw.SizedBox(height: 3),
          _amountRow(
            'Amount payable within due date: ${_dateLabel(dueDate)}',
            _money(charge.amountDue),
            bold: true,
            accent: accent,
          ),
          _amountRow(
            'Amount payable after ${_dateLabel(dueDate)}',
            '${_money(charge.amountDue)} + Rs.450 fine/month',
          ),
          _amountRow('Challan validity date', _dateLabel(validityDate)),
          pw.SizedBox(height: 3),
          pw.Text(
            'Instructions for Parents',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.2),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            'After the expiry date of submission of fee, the management '
            'reserves the right to stop your child from taking Classes / '
            'Examinations in case of non-payment without any prior notice. '
            'No objection will be entertained in this regard. Fees paid '
            'after the due date are subject to a fine of Rs.450/- per month. '
            'For re-issuance of fee voucher Rs.50/- will be charged. '
            'Fee once paid is not transferable and non-refundable.',
            style: const pw.TextStyle(fontSize: 6.1, lineSpacing: 1),
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signature('Authorized person'),
              _signature('Banker sign'),
            ],
          ),
        ],
      ),
    );
  }

  static pw.TableRow _feeRow(
    String label,
    String amount, {
    String months = '',
    bool isHeader = false,
    PdfColor? color,
  }) {
    final style = pw.TextStyle(
      fontSize: isHeader ? 6.5 : 7,
      fontWeight: isHeader || label == 'Tuition Fee'
          ? pw.FontWeight.bold
          : pw.FontWeight.normal,
      color: isHeader ? PdfColors.white : PdfColors.black,
    );
    return pw.TableRow(
      decoration: isHeader && color != null
          ? pw.BoxDecoration(color: color)
          : null,
      children: [
        _tableCell(label, style),
        _tableCell(amount, style, align: pw.TextAlign.right),
        _tableCell(months, style, align: pw.TextAlign.center),
      ],
    );
  }

  static pw.Widget _tableCell(
    String text,
    pw.TextStyle style, {
    pw.TextAlign align = pw.TextAlign.left,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
    child: pw.Text(text, textAlign: align, style: style),
  );

  static pw.Widget _detailRow(
    String leftLabel,
    String leftValue,
    String rightLabel,
    String rightValue,
  ) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: '$leftLabel: ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(text: leftValue),
              ],
              style: const pw.TextStyle(fontSize: 6.7),
            ),
          ),
        ),
        pw.Expanded(
          flex: 2,
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: '$rightLabel: ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(text: rightValue),
              ],
              style: const pw.TextStyle(fontSize: 6.7),
            ),
          ),
        ),
      ],
    ),
  );

  static pw.Widget _amountRow(
    String label,
    String amount, {
    bool bold = false,
    PdfColor? accent,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 6.7,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: accent,
            ),
          ),
        ),
        pw.Text(
          amount,
          style: pw.TextStyle(fontSize: 6.7, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  static pw.Widget _signature(String label) => pw.SizedBox(
    width: 100,
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.SizedBox(
          height: 18,
          child: pw.Align(
            alignment: pw.Alignment.bottomCenter,
            child: pw.Container(height: 0.6, color: PdfColors.black),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(label, style: const pw.TextStyle(fontSize: 6)),
      ],
    ),
  );

  static String _money(double amount) => 'PKR ${amount.toStringAsFixed(0)}';

  static String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  static String _shortMonth(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]}-${date.year.toString().substring(2)}';
  }
}
