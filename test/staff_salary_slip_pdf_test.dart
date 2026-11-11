import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/data/staff_repository.dart';
import 'package:tlc_school_system/school_profile.dart';
import 'package:tlc_school_system/staff/staff_salary_slip_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const staff = StaffMember(
    id: 'staff-1',
    employeeNumber: 'TLC-123',
    fullName: 'Ayesha Teacher',
    fatherName: 'Parent Name',
    gender: 'Female',
    role: 'Teacher',
    academicQualification: 'M.A.',
    professionalQualification: 'B.Ed.',
    appointmentDate: '2024-01-01',
    monthlySalary: 40000,
  );

  test('builds a monthly salary slip PDF', () async {
    final bytes = await StaffSalarySlipPdf.build(
      profile: SchoolProfile.tlc(),
      staff: staff,
      month: DateTime(2026, 10),
      unpaidDays: 1,
      otherDeductions: 500,
      bankName: 'Bank',
      bankAccountName: 'Ayesha Teacher',
      bankAccountNumber: '123456',
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('rejects salary deductions greater than the salary', () async {
    await expectLater(
      StaffSalarySlipPdf.build(
        profile: SchoolProfile.tlc(),
        staff: staff,
        month: DateTime(2026, 10),
        unpaidDays: 0,
        otherDeductions: 40001,
        bankName: '',
        bankAccountName: '',
        bankAccountNumber: '',
      ),
      throwsArgumentError,
    );
  });
}
