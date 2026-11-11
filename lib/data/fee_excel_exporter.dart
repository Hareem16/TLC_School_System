import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'fee_repository.dart';

class FeeExcelExporter {
  static Uint8List encode(Iterable<FeeCharge> charges) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Fee Ledger'];
    sheet.appendRow([
      'Fee Month',
      'G.R. Number',
      'Student Name',
      'Class',
      'Amount Due (PKR)',
      'Amount Paid (PKR)',
      'Balance (PKR)',
      'Status',
    ].map(TextCellValue.new).toList());

    for (final charge in charges) {
      sheet.appendRow([
        charge.monthKey,
        charge.admissionNumber,
        charge.studentName,
        charge.className,
        charge.amountDue.toStringAsFixed(2),
        charge.amountPaid.toStringAsFixed(2),
        charge.balance.toStringAsFixed(2),
        charge.status,
      ].map(TextCellValue.new).toList());
    }

    final bytes = workbook.encode();
    if (bytes == null) {
      throw StateError('The fee ledger workbook could not be encoded.');
    }
    return Uint8List.fromList(bytes);
  }
}
