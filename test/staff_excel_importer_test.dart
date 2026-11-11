import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/data/staff_excel_importer.dart';

void main() {
  test('parses the teacher and staff workbook columns', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([TextCellValue('THE LEARNING CIRCLE')]);
    sheet.appendRow([
      TextCellValue('S. No.'),
      TextCellValue('Employee Name'),
      TextCellValue('Father / Husband Name'),
      TextCellValue('Gender'),
      TextCellValue('Academic Qualification'),
      TextCellValue('Professional Qualification'),
      TextCellValue('Designation'),
      TextCellValue('Date of Appointment'),
      TextCellValue('Monthly Salary'),
    ]);
    sheet.appendRow([
      IntCellValue(1),
      TextCellValue('ASAD SAHAB'),
      TextCellValue('ASGHAR HUSSAIN SIDDIQUI'),
      TextCellValue('Male'),
      TextCellValue('Intermediate'),
      TextCellValue('-'),
      TextCellValue('Sports Teacher'),
      TextCellValue('1/3/2026'),
      TextCellValue('30,000.00'),
    ]);

    final result = StaffExcelImporter().parse(workbook.encode()!);

    expect(result.errors, isEmpty);
    expect(result.staff, hasLength(1));
    expect(result.staff.single.fullName, 'ASAD SAHAB');
    expect(result.staff.single.role, 'Sports Teacher');
    expect(result.staff.single.monthlySalary, 30000);
    expect(result.staff.single.appointmentDate, '2026-03-01T00:00:00.000');
    expect(result.staff.single.employeeNumber, startsWith('TLC-'));
  });

  test('uses adjacent academic and professional qualification columns', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Employees'];
    sheet.appendRow([
      TextCellValue('S. No.'),
      TextCellValue('Employee Name'),
      TextCellValue('Father / Husband Name'),
      TextCellValue('Gender'),
      TextCellValue('Qualification'),
      null,
      TextCellValue('Designation'),
      TextCellValue('Date of Appointment'),
      TextCellValue('Monthly Salary'),
    ]);
    sheet.appendRow([
      null,
      null,
      null,
      null,
      TextCellValue('Academic'),
      TextCellValue('Professional'),
    ]);
    sheet.appendRow([
      IntCellValue(1),
      TextCellValue('MISS FAKHRA RASHID'),
      TextCellValue('RASHID HUSSAIN'),
      TextCellValue('Female'),
      TextCellValue('B.Com'),
      TextCellValue('B. Ed'),
      TextCellValue('PRINCIPAL'),
      TextCellValue('18/07/2024'),
      TextCellValue('40,000.00'),
    ]);

    final result = StaffExcelImporter().parse(workbook.encode()!);

    expect(result.errors, isEmpty);
    expect(result.staff, hasLength(1));
    expect(result.staff.single.academicQualification, 'B.Com');
    expect(result.staff.single.professionalQualification, 'B. Ed');
    expect(result.staff.single.monthlySalary, 40000);
  });
}
