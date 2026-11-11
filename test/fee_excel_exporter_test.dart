import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/data/fee_excel_exporter.dart';
import 'package:tlc_school_system/data/fee_repository.dart';

void main() {
  test('exports fee balances and payment status to an Excel worksheet', () {
    const charge = FeeCharge(
      id: 'fee-1',
      studentId: 'student-1',
      admissionNumber: 'GR-001',
      studentName: 'Amina Khan',
      className: 'Class 3',
      monthKey: '2026-10',
      amountDue: 1250,
      amountPaid: 500,
    );

    final workbook = Excel.decodeBytes(FeeExcelExporter.encode([charge]));
    final rows = workbook.tables['Fee Ledger']!.rows;

    expect(rows, hasLength(2));
    expect(rows.first.first!.value.toString(), contains('Fee Month'));
    expect(rows[1][0]!.value.toString(), contains('2026-10'));
    expect(rows[1][6]!.value.toString(), contains('750.00'));
    expect(rows[1][7]!.value.toString(), contains('Partial'));
  });
}
