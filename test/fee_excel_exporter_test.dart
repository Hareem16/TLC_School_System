import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/data/fee_excel_exporter.dart';
import 'package:tlc_school_system/data/fee_repository.dart';

void main() {
  test(
    'exports itemized fees, totals, payment status, and worksheet filters',
    () {
      const charge = FeeCharge(
        id: 'fee-1',
        studentId: 'student-1',
        admissionNumber: 'GR-001',
        studentName: 'Amina Khan',
        className: 'Class 3',
        monthKey: '2026-10',
        amountDue: 1250,
        amountPaid: 500,
        fees: 1250,
        arrears: [
          FeeCharge(
            id: 'fee-previous',
            studentId: 'student-1',
            admissionNumber: 'GR-001',
            studentName: 'Amina Khan',
            className: 'Class 3',
            monthKey: '2026-09',
            amountDue: 400,
            amountPaid: 150,
            fees: 400,
          ),
        ],
      );

      const title = 'TLC RECEIPT OF WEEK-WISE (2nd Nov, 26 to 8th Nov, 26)';
      final workbook = Excel.decodeBytes(
        FeeExcelExporter.encode([charge], title: title),
      );
      expect(workbook.tables.keys, contains('Fee Ledger'));
      expect(workbook.tables.length, 1);
      final rows = workbook.tables['Fee Ledger']!.rows;

      expect(rows, hasLength(4));
      expect(rows[0][0]!.value.toString(), title);
      expect(rows[0][0]!.cellStyle!.isBold, isTrue);
      expect(rows[0][0]!.cellStyle!.fontSize, 16);
      expect(rows[1].map((cell) => cell?.value.toString()).toList(), [
        'Date',
        'Receipt No (Voucher No.)',
        'Student Name',
        'Class',
        'Details (Month/s)',
        'Fees',
        'Annual',
        'Admission',
        'Lab',
        'Copies',
        'Stationery',
        'Extras',
        'LPC',
        'Arrears',
        'Total Payable',
        'Amount Paid',
        'Outstanding',
        'Payment Status',
        'Remarks',
      ]);
      expect(rows[1][0]!.cellStyle!.isBold, isTrue);
      expect(rows[2][1]!.value.toString(), 'GR-001-202610');
      expect(rows[2][4]!.value.toString(), '2026-09, 2026-10');
      expect(rows[2][5]!.value, const IntCellValue(1250));
      expect(rows[2][13]!.value, const IntCellValue(250));
      expect(rows[2][14]!.value, const IntCellValue(1500));
      expect(rows[2][15]!.value, const IntCellValue(500));
      expect(rows[2][16]!.value, const IntCellValue(1000));
      expect(rows[2][17]!.value.toString(), 'Partial Paid');
      expect(rows[2][18]!.value.toString(), contains('2026-09: PKR 250.00'));
      expect(rows[2][18]!.value.toString(), contains('1000.00 outstanding'));
      expect(rows[2][5]!.cellStyle!.numberFormat, NumFormat.standard_2);
      expect(rows[2][0]!.cellStyle!.leftBorder.borderStyle, BorderStyle.Medium);
      expect(rows[2][1]!.cellStyle!.rightBorder.borderStyle, BorderStyle.Thin);
      expect(rows[3][14]!.value, const FormulaCellValue('SUM(O3:O3)'));
      expect(rows[3][16]!.value, const FormulaCellValue('SUM(Q3:Q3)'));

      final worksheet = ZipDecoder()
          .decodeBytes(FeeExcelExporter.encode([charge], title: title))
          .findFile('xl/worksheets/sheet1.xml');
      expect(worksheet, isNotNull);
      final worksheetXml = utf8.decode(worksheet!.content as List<int>);
      final filterPosition = worksheetXml.indexOf('<autoFilter');
      final mergePosition = worksheetXml.indexOf('<mergeCells');
      expect(filterPosition, lessThan(mergePosition));
      expect(worksheetXml, contains('<autoFilter ref="A2:S3"/>'));
      expect(RegExp('<col min=').allMatches(worksheetXml), hasLength(19));
    },
  );

  test('exports an informative workbook when no charges match', () {
    final workbook = Excel.decodeBytes(
      FeeExcelExporter.encode(
        const [],
        title: 'TLC RECEIPT OF DATE-WISE (3rd Nov, 26 (Tuesday))',
      ),
    );
    final rows = workbook.tables['Fee Ledger']!.rows;

    expect(rows[0][0]!.value.toString(), contains('DATE-WISE'));
    expect(rows[2][0]!.value.toString(), contains('No fee records matched'));
  });
}
