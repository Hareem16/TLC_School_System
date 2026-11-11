import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/data/student_excel_importer.dart';

void main() {
  test('maps register headers and parses ordinal dates', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([TextCellValue('School register')]);
    sheet.appendRow([TextCellValue('Admission register')]);
    sheet.appendRow([
      TextCellValue('REGISTER NO.'),
      TextCellValue('CURRENT CLASS'),
      TextCellValue('NAME OF THE STUDENT'),
      TextCellValue("FATHER'S NAME"),
      TextCellValue('GENDER'),
      TextCellValue('RELIGION'),
      TextCellValue('ADDRESS'),
      TextCellValue('DATE OF BIRTH'),
      TextCellValue('PLACE OF BIRTH'),
      TextCellValue('LAST INSTITUTION ATTENDED'),
      TextCellValue('DATE OF ADMISSION'),
      TextCellValue('CLASS IN WHICH ADMITTED'),
      TextCellValue('DATE OF REMOVAL'),
      TextCellValue('CLASS AT THE TIME OF REMOVAL'),
      TextCellValue('CAUSE OF REMOVAL'),
      TextCellValue('REMARKS'),
    ]);
    sheet.appendRow([
      IntCellValue(940),
      TextCellValue('I'),
      TextCellValue('ABDULLAH ASAD'),
      TextCellValue('ASAD ALI'),
      TextCellValue('BOY'),
      TextCellValue('ISLAM'),
      TextCellValue('Main Street'),
      TextCellValue('12TH JUNE 2020'),
      TextCellValue('KARACHI'),
      TextCellValue('Previous School'),
      TextCellValue('12TH JULY 2023'),
      TextCellValue('P-I'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
    ]);
    sheet.appendRow(List.filled(16, null));

    final result = StudentExcelImporter().parse(workbook.encode()!);

    expect(result.errors, isEmpty);
    expect(result.skippedBlankRows, 1);
    expect(result.students, hasLength(1));
    final student = result.students.single;
    expect(student.admissionNumber, '940');
    expect(student.studentName, 'ABDULLAH ASAD');
    expect(student.guardianName, 'ASAD ALI');
    expect(student.gender, 'Boy');
    expect(student.religion, 'ISLAM');
    expect(student.dateOfBirth, DateTime(2020, 6, 12));
    expect(student.dateOfAdmission, DateTime(2023, 7, 12));
    expect(student.admittedClass, 'P-I');
  });

  test('maps G.R. No. and NAME OF STUDENT from the supplied record format', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      TextCellValue('S. No.'),
      TextCellValue('G.R. No.'),
      TextCellValue('CLASS'),
      TextCellValue('NAME OF STUDENT'),
      TextCellValue("FATHER'S NAME"),
    ]);
    sheet.appendRow([
      IntCellValue(923),
      IntCellValue(923),
      TextCellValue('P-I'),
      TextCellValue('ALI ABBAS'),
      TextCellValue('DANISH SADIQ'),
    ]);

    final result = StudentExcelImporter().parse(workbook.encode()!);

    expect(result.errors, isEmpty);
    expect(result.students, hasLength(1));
    expect(result.students.single.admissionNumber, '923');
    expect(result.students.single.className, 'P-I');
    expect(result.students.single.fullName, 'ALI ABBAS');
    expect(result.students.single.guardianName, 'DANISH SADIQ');
  });

  test('imports monthly fees and records when the fee column is present', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      TextCellValue('G.R. Number'),
      TextCellValue('Class'),
      TextCellValue('Student Name'),
      TextCellValue('Monthly Fee (PKR)'),
    ]);
    sheet.appendRow([
      IntCellValue(923),
      TextCellValue('P-I'),
      TextCellValue('ALI ABBAS'),
      TextCellValue('1,250.50'),
    ]);

    final result = StudentExcelImporter().parse(workbook.encode()!);

    expect(result.errors, isEmpty);
    expect(result.students.single.monthlyFee, 1250.50);
    expect(result.includedFields, contains('monthly_fee'));
  });

  test('imports roll number when the register contains a roll column', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      TextCellValue('G.R. Number'),
      TextCellValue('Roll No.'),
      TextCellValue('Class'),
      TextCellValue('Student Name'),
    ]);
    sheet.appendRow([
      IntCellValue(923),
      IntCellValue(7),
      TextCellValue('P-I'),
      TextCellValue('ALI ABBAS'),
    ]);

    final result = StudentExcelImporter().parse(workbook.encode()!);

    expect(result.errors, isEmpty);
    expect(result.students.single.rollNumber, '7');
    expect(result.includedFields, contains('roll_number'));
  });

  test('tracks blank fields so re-imports preserve previously saved values', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      TextCellValue('G.R. No.'),
      TextCellValue('Class'),
      TextCellValue('Student Name'),
      TextCellValue('Address'),
      TextCellValue('Family No.'),
    ]);
    sheet.appendRow([
      IntCellValue(923),
      TextCellValue('P-I'),
      TextCellValue('ALI ABBAS'),
      TextCellValue(''),
      TextCellValue('FAM-11'),
    ]);

    final result = StudentExcelImporter().parse(workbook.encode()!);

    expect(result.includedFields, containsAll(['address', 'family_no']));
    expect(
      result.emptyFieldsByAdmissionNumber['923'],
      contains('address'),
    );
    expect(
      result.emptyFieldsByAdmissionNumber['923'],
      isNot(contains('family_no')),
    );
    expect(result.students.single.familyNo, 'FAM-11');
  });

  test('rejects invalid monthly fee values', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      TextCellValue('G.R. No.'),
      TextCellValue('Class'),
      TextCellValue('Student Name'),
      TextCellValue('Monthly Fee'),
    ]);
    sheet.appendRow([
      IntCellValue(923),
      TextCellValue('P-I'),
      TextCellValue('ALI ABBAS'),
      TextCellValue('not a fee'),
    ]);

    final result = StudentExcelImporter().parse(workbook.encode()!);

    expect(result.errors, hasLength(1));
    expect(result.errors.single, contains('invalid monthly fee'));
  });

  test('rejects repeated G.R. numbers in a workbook', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      TextCellValue('REGISTER NO.'),
      TextCellValue('CURRENT CLASS'),
      TextCellValue('NAME OF THE STUDENT'),
    ]);
    for (final name in ['Student One', 'Student Two']) {
      sheet.appendRow([
        IntCellValue(10),
        TextCellValue('I'),
        TextCellValue(name),
      ]);
    }

    final result = StudentExcelImporter().parse(workbook.encode()!);

    expect(result.students, hasLength(1));
    expect(result.errors, hasLength(1));
    expect(result.errors.single, contains('Rows 2 and 3 use G.R. number 10'));
  });
}
