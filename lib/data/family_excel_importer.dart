import 'package:excel/excel.dart';

import 'excel_workbook_decoder.dart';

class FamilyImportRecord {
  final String admissionNumber;
  final String familyNo;
  final String studentName;
  final String fatherName;
  final String className;

  const FamilyImportRecord({
    required this.admissionNumber,
    required this.familyNo,
    required this.studentName,
    required this.fatherName,
    required this.className,
  });
}

class FamilyExcelImportResult {
  final List<FamilyImportRecord> records;
  final int skippedBlankRows;
  final List<String> errors;

  const FamilyExcelImportResult({
    required this.records,
    required this.skippedBlankRows,
    required this.errors,
  });
}

class FamilyExcelImporter {
  FamilyExcelImportResult parse(List<int> bytes) {
    final workbook = ExcelWorkbookDecoder.decode(bytes);
    for (final sheet in workbook.tables.values) {
      final rows = sheet.rows;
      for (var headerIndex = 0; headerIndex < rows.length; headerIndex++) {
        final headers = <String, int>{};
        for (var column = 0; column < rows[headerIndex].length; column++) {
          final header = _normalize(_cellText(rows[headerIndex][column]));
          if (header.isNotEmpty) headers[header] = column;
        }
        final admissionColumn = _findColumn(headers, [
          'grno',
          'grnumber',
          'registerno',
          'admissionnumber',
        ]);
        final familyColumn = _findColumn(headers, [
          'familyno',
          'familynumber',
          'familyid',
          'family',
        ]);
        if (admissionColumn == null || familyColumn == null) continue;

        final records = <FamilyImportRecord>[];
        final errors = <String>[];
        final seenAdmissionNumbers = <String, int>{};
        var skippedBlankRows = 0;
        for (var rowIndex = headerIndex + 1; rowIndex < rows.length; rowIndex++) {
          final row = rows[rowIndex];
          final admissionNumber = _valueAt(row, admissionColumn);
          final familyNo = _valueAt(row, familyColumn);
          final studentName = _valueAt(
            row,
            _findColumn(headers, ['studentname', 'nameofstudent', 'name']),
          );
          final fatherName = _valueAt(
            row,
            _findColumn(headers, [
              'fathername',
              'fathersname',
              'fatherguardian',
            ]),
          );
          final className = _valueAt(
            row,
            _findColumn(headers, ['class', 'classes', 'currentclass']),
          );
          if ([admissionNumber, familyNo, studentName, fatherName, className]
              .every((value) => value.isEmpty)) {
            skippedBlankRows++;
            continue;
          }
          final worksheetRow = rowIndex + 1;
          if (admissionNumber.isEmpty ||
              admissionNumber == '-' ||
              familyNo.isEmpty ||
              familyNo == '-') {
            errors.add(
              'Row $worksheetRow is missing a G.R. number or Family No.',
            );
            continue;
          }
          final normalizedAdmission = admissionNumber.toLowerCase();
          final firstRow = seenAdmissionNumbers.putIfAbsent(
            normalizedAdmission,
            () => worksheetRow,
          );
          if (firstRow != worksheetRow) {
            errors.add(
              'Rows $firstRow and $worksheetRow use G.R. number '
              '$admissionNumber. Correct this duplicate before importing.',
            );
            continue;
          }
          records.add(
            FamilyImportRecord(
              admissionNumber: admissionNumber,
              familyNo: familyNo,
              studentName: studentName,
              fatherName: fatherName,
              className: className,
            ),
          );
        }
        return FamilyExcelImportResult(
          records: records,
          skippedBlankRows: skippedBlankRows,
          errors: errors,
        );
      }
    }
    throw const FormatException(
      'The sibling workbook must include G.R. No. and Family No. columns.',
    );
  }

  int? _findColumn(Map<String, int> headers, List<String> aliases) {
    for (final alias in aliases) {
      final column = headers[alias];
      if (column != null) return column;
    }
    return null;
  }

  String _valueAt(List<Data?> row, int? column) =>
      column == null || column >= row.length ? '' : _cellText(row[column]);

  String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text?.trim() ?? '';
    return value.toString().trim();
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
