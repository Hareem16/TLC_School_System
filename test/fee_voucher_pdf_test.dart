import 'package:flutter_test/flutter_test.dart';

import 'package:tlc_school_system/data/fee_repository.dart';
import 'package:tlc_school_system/fees/fee_receipt_pdf.dart';
import 'package:tlc_school_system/fees/fee_voucher_pdf.dart';
import 'package:tlc_school_system/school_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates a monthly fee voucher PDF for duplicate printing', () async {
    const charge = FeeCharge(
      id: 'fee-1',
      studentId: 'student-1',
      admissionNumber: '16893',
      studentName: 'Student One',
      guardianName: 'Parent One',
      className: 'IX - A',
      monthKey: '2026-10',
      amountDue: 5500,
      amountPaid: 0,
      fees: 5500,
      arrears: [
        FeeCharge(
          id: 'fee-previous',
          studentId: 'student-1',
          admissionNumber: '16893',
          studentName: 'Student One',
          guardianName: 'Parent One',
          className: 'IX - A',
          monthKey: '2026-09',
          amountDue: 1200,
          amountPaid: 300,
          fees: 1200,
        ),
      ],
    );

    final bytes = await FeeVoucherPdf.build(
      profile: SchoolProfile.tlc(),
      charges: const [charge],
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final pdfText = String.fromCharCodes(bytes);
    expect(pdfText, startsWith('%PDF-1.4'));
    final startXrefMarker = pdfText.lastIndexOf('startxref\n');
    expect(startXrefMarker, greaterThan(0));
    final xrefOffset = int.parse(
      pdfText
          .substring(startXrefMarker + 'startxref\n'.length)
          .split('\n')
          .first
          .trim(),
    );
    expect(pdfText.startsWith('xref\n', xrefOffset), isTrue);
    final xrefLines = pdfText.substring(xrefOffset).split('\n');
    final xrefRange = xrefLines[1].split(' ');
    final firstObjectNumber = int.parse(xrefRange.first);
    final objectCount = int.parse(xrefRange.last);
    for (var objectNumber = 1; objectNumber < objectCount; objectNumber++) {
      final entry = xrefLines[2 + objectNumber - firstObjectNumber];
      if (!entry.endsWith(' n ')) continue;
      final objectOffset = int.parse(entry.substring(0, 10));
      expect(
        pdfText.startsWith('$objectNumber 0 obj', objectOffset),
        isTrue,
        reason: 'xref entry for object $objectNumber must point to its object',
      );
    }
    expect(pdfText.trimRight(), endsWith('%%EOF'));
  });

  test('creates a receipt PDF with its month-by-month allocations', () async {
    final bytes = await FeeReceiptPdf.build(
      profile: SchoolProfile.tlc(),
      payment: FeePayment(
        paymentId: 'payment-1',
        receiptNumber: 'TLC-20260301-ABC12345',
        studentName: 'Student One',
        admissionNumber: '16893',
        className: 'IX - A',
        monthKey: '2026-03',
        amountDue: 1800,
        amountPaidThisReceipt: 1000,
        receiptAmount: 1000,
        totalPaid: 1000,
        balance: 800,
        paidAt: DateTime(2026, 3, 1),
        paymentMethod: 'Cash',
        notes: '',
        allocations: const [
          FeePaymentAllocation(
            feeId: 'fee-jan',
            monthKey: '2026-01',
            amount: 400,
          ),
          FeePaymentAllocation(
            feeId: 'fee-feb',
            monthKey: '2026-02',
            amount: 600,
          ),
        ],
      ),
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
