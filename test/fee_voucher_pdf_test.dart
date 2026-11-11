import 'package:flutter_test/flutter_test.dart';

import 'package:tlc_school_system/data/fee_repository.dart';
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
    );

    final bytes = await FeeVoucherPdf.build(
      profile: SchoolProfile.tlc(),
      charges: const [charge],
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final pdfText = String.fromCharCodes(bytes);
    expect(pdfText, contains('startxref'));
    expect(pdfText.trimRight(), endsWith('%%EOF'));
  });
}
