import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/data/family_excel_importer.dart';

void main() {
  test('reads family number assignments by G.R. number', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Siblings'];
    sheet.appendRow([
      TextCellValue('G.R. No.'),
      TextCellValue('Student Name'),
      TextCellValue('Father Name'),
      TextCellValue('Classes'),
      TextCellValue('Family No.'),
      TextCellValue('Total Siblings'),
    ]);
    sheet.appendRow([
      IntCellValue(923),
      TextCellValue('ALI ABBAS'),
      TextCellValue('DANISH SADIQ'),
      TextCellValue('P-I'),
      TextCellValue('FAM-11'),
      IntCellValue(2),
    ]);

    final result = FamilyExcelImporter().parse(workbook.encode()!);

    expect(result.errors, isEmpty);
    expect(result.records, hasLength(1));
    expect(result.records.single.admissionNumber, '923');
    expect(result.records.single.familyNo, 'FAM-11');
    expect(result.records.single.fatherName, 'DANISH SADIQ');
    expect(result.records.single.className, 'P-I');
  });

  test('rejects duplicate G.R. numbers in a sibling workbook', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Siblings'];
    sheet.appendRow([TextCellValue('G.R. No.'), TextCellValue('Family No.')]);
    sheet.appendRow([IntCellValue(923), TextCellValue('FAM-11')]);
    sheet.appendRow([IntCellValue(923), TextCellValue('FAM-11')]);

    final result = FamilyExcelImporter().parse(workbook.encode()!);

    expect(result.records, hasLength(1));
    expect(result.errors, hasLength(1));
    expect(result.errors.single, contains('Rows 2 and 3 use G.R. number 923'));
  });
}
