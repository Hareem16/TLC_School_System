import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/staff_repository.dart';
import '../school_profile.dart';

class StaffSalarySlipPdf {
  static Future<Uint8List> build({
    required SchoolProfile profile,
    required StaffMember staff,
    required DateTime month,
    required double unpaidDays,
    required double otherDeductions,
    required String bankName,
    required String bankAccountName,
    required String bankAccountNumber,
  }) async {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    if (unpaidDays < 0 || unpaidDays > daysInMonth) {
      throw ArgumentError.value(unpaidDays, 'unpaidDays');
    }
    if (otherDeductions < 0) {
      throw ArgumentError.value(otherDeductions, 'otherDeductions');
    }
    final unpaidDeduction = staff.monthlySalary / daysInMonth * unpaidDays;
    final totalDeductions = unpaidDeduction + otherDeductions;
    if (totalDeductions > staff.monthlySalary) {
      throw ArgumentError(
        'Total deductions cannot exceed the monthly salary.',
      );
    }

    final logoBytes = (await rootBundle.load('assets/images/tlc_logo.png'))
        .buffer
        .asUint8List();
    final document = pw.Document();
    final accent = PdfColor.fromInt(profile.primaryColor.toARGB32());
    final monthLabel = '${_monthName(month.month)} ${month.year}';
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 0.8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                child: pw.Row(
                  children: [
                    pw.Image(
                      pw.MemoryImage(logoBytes),
                      width: 42,
                      height: 42,
                      fit: pw.BoxFit.contain,
                    ),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: pw.Text(
                        profile.schoolName,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          color: accent,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 8),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(),
                    bottom: pw.BorderSide(),
                  ),
                ),
                child: pw.Text(
                  'SALARY SLIP RECEIPT - $monthLabel',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.7),
                  1: pw.FlexColumnWidth(3.3),
                },
                children: [
                  _detailRow('NAME OF TEACHER', staff.fullName),
                  _detailRow('TEACHER ID', staff.employeeNumber),
                  _detailRow('DESIGNATION', staff.role),
                  _detailRow('BANK NAME', _display(bankName)),
                  _detailRow('BANK ACCOUNT NAME', _display(bankAccountName)),
                  _detailRow('BANK ACCOUNT NO.', _display(bankAccountNumber)),
                  _detailRow('DATE', monthLabel),
                ],
              ),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2),
                  1: pw.FlexColumnWidth(1),
                  2: pw.FlexColumnWidth(1),
                },
                children: [
                  _salaryRow(
                    'DESCRIPTION',
                    'SALARY',
                    'DEDUCTION',
                    header: true,
                    accent: PdfColor.fromInt(0xFFD7F0D2),
                  ),
                  _salaryRow(
                    'BASIC SALARY',
                    _money(staff.monthlySalary),
                    '',
                  ),
                  _salaryRow(
                    'NPD (${_dayCount(unpaidDays)} days)',
                    '',
                    _money(unpaidDeduction),
                  ),
                  if (otherDeductions > 0)
                    _salaryRow(
                      'OTHER DEDUCTIONS',
                      '',
                      _money(otherDeductions),
                    ),
                  _salaryRow(
                    'TOTAL',
                    _money(staff.monthlySalary),
                    _money(totalDeductions),
                    bold: true,
                  ),
                  _salaryRow(
                    'NET TOTAL',
                    _money(staff.monthlySalary - totalDeductions),
                    '',
                    bold: true,
                    accent: PdfColor.fromInt(0xFFBFE8F5),
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Padding(
                padding: const pw.EdgeInsets.all(10),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Generated as a salary voucher; payment is not recorded by this printout.',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return document.save();
  }

  static pw.TableRow _detailRow(String label, String value) => pw.TableRow(
    children: [
      _cell(label, bold: true),
      _cell(value),
    ],
  );

  static pw.TableRow _salaryRow(
    String description,
    String salary,
    String deduction, {
    bool header = false,
    bool bold = false,
    PdfColor? accent,
  }) => pw.TableRow(
    decoration: header || accent != null
        ? pw.BoxDecoration(
            color: accent ?? PdfColor.fromInt(0xFFD7F0D2),
          )
        : null,
    children: [
      _cell(description, bold: header || bold, centered: header),
      _cell(salary, bold: header || bold, centered: true),
      _cell(deduction, bold: header || bold, centered: true),
    ],
  );

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool centered = false,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 9),
    child: pw.Text(
      text,
      textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  static String _money(double amount) => 'PKR ${amount.toStringAsFixed(2)}';

  static String _display(String value) =>
      value.trim().isEmpty ? 'Not provided' : value.trim();

  static String _dayCount(double days) =>
      days == days.roundToDouble() ? days.toStringAsFixed(0) : '$days';

  static String _monthName(int month) => const [
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
  ][month - 1];
}
