import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../student.dart';

class StudentExcelExporter {
  static Uint8List encode(Iterable<Student> students) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Students'];
    sheet.appendRow([
      'G.R. Number',
      'Roll No.',
      'Student Name',
      'Gender',
      'Date of Birth',
      'Place of Birth',
      'Religion',
      'Address',
      'Father / Guardian',
      'Contact Number',
      'Class',
      'Section',
      'Date of Admission',
      'Previous Institute',
      'Class Admitted',
      'Monthly Fee (PKR)',
      'Date of Removal',
      'Class at Removal',
      'Cause of Removal',
      'Remarks',
      'Created At',
      'Family No.',
    ].map(TextCellValue.new).toList());

    for (final student in students) {
      sheet.appendRow([
        student.admissionNumber,
        student.rollNumber,
        student.fullName,
        student.gender,
        _date(student.dateOfBirth),
        student.placeOfBirth,
        student.religion,
        student.address,
        student.guardianName,
        student.guardianPhone,
        student.className,
        student.sectionName,
        _date(student.dateOfAdmission),
        student.previousInstitute,
        student.admittedClass,
        student.monthlyFee.toStringAsFixed(2),
        _date(student.dateOfRemoval),
        student.classAtRemoval,
        student.causeOfRemoval,
        student.remarks,
        student.createdAt.toIso8601String(),
        student.familyNo,
      ].map(TextCellValue.new).toList());
    }

    final bytes = workbook.encode();
    if (bytes == null) {
      throw StateError('The student workbook could not be encoded.');
    }
    return Uint8List.fromList(bytes);
  }

  static String _date(DateTime? value) =>
      value?.toIso8601String().split('T').first ?? '';
}
