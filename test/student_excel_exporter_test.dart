import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/data/student_excel_exporter.dart';
import 'package:tlc_school_system/student.dart';

void main() {
  test('exports the supplied student records to an Excel worksheet', () {
    final student = Student(
      studentId: 'student-1',
      admissionNumber: 'GR-001',
      rollNumber: '12',
      firstName: 'Amina',
      lastName: 'Khan',
      className: 'Class 3',
      sectionName: 'A',
      guardianName: 'Usman Khan',
      guardianPhone: '03001234567',
      gender: 'Girl',
      monthlyFee: 1250,
      createdAt: DateTime(2024, 8, 1),
    );

    final workbook = Excel.decodeBytes(
      StudentExcelExporter.encode([student]),
    );
    final rows = workbook.tables['Students']!.rows;

    expect(rows, hasLength(2));
    expect(rows.first.first!.value.toString(), contains('G.R. Number'));
    expect(rows[1][0]!.value.toString(), contains('GR-001'));
    expect(rows[1][1]!.value.toString(), contains('12'));
    expect(rows[1][2]!.value.toString(), contains('Amina Khan'));
    expect(rows[1][15]!.value.toString(), contains('1250.00'));
  });
}
