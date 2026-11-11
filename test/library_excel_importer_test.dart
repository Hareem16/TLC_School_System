import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/data/library_excel_importer.dart';

void main() {
  test('imports the two class-wise book-list blocks', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      null,
      TextCellValue('PLAYGROUP'),
      null,
      null,
      null,
      null,
      TextCellValue('PRE-YEAR I'),
    ]);
    sheet.appendRow([
      null,
      TextCellValue('SUBJECT'),
      TextCellValue('BOOKS/ PRINTED COPIES'),
      TextCellValue('Author'),
      TextCellValue('PUBLISHER'),
      null,
      TextCellValue('SUBJECT'),
      TextCellValue('BOOKS/ PRINTED COPIES'),
      TextCellValue('Author'),
      TextCellValue('PUBLISHER'),
    ]);
    sheet.appendRow([
      null,
      TextCellValue('English'),
      TextCellValue('English Language Worksheets'),
      TextCellValue('SPECTRUM'),
      TextCellValue('SPECTRUM'),
      null,
      TextCellValue('English'),
      TextCellValue('English language workbook'),
      TextCellValue('Iftikhar Ahmed'),
      TextCellValue('Oxford'),
    ]);

    final result = LibraryExcelImporter().parse(workbook.encode()!);

    expect(result.errors, isEmpty);
    expect(result.books, hasLength(2));
    expect(result.books.first.className, 'PLAYGROUP');
    expect(result.books.first.title, 'English Language Worksheets');
    expect(result.books.last.className, 'PRE-YEAR I');
    expect(result.books.last.publisher, 'Oxford');
  });
}
