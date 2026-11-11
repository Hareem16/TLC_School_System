import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';

import 'excel_workbook_decoder.dart';

class StaffImportRecord {
  final String employeeNumber;
  final String importKey;
  final String fullName;
  final String fatherName;
  final String gender;
  final String role;
  final String academicQualification;
  final String professionalQualification;
  final String appointmentDate;
  final double monthlySalary;
  final Set<String> blankFields;

  const StaffImportRecord({
    required this.employeeNumber,
    required this.importKey,
    required this.fullName,
    required this.fatherName,
    required this.gender,
    required this.role,
    required this.academicQualification,
    required this.professionalQualification,
    required this.appointmentDate,
    required this.monthlySalary,
    required this.blankFields,
  });
}

class StaffExcelImportResult {
  final List<StaffImportRecord> staff;
  final int skippedBlankRows;
  final List<String> errors;

  const StaffExcelImportResult({
    required this.staff,
    required this.skippedBlankRows,
    required this.errors,
  });
}

class StaffExcelImporter {
  StaffExcelImportResult parse(List<int> bytes) {
    final workbook = ExcelWorkbookDecoder.decode(bytes);
    for (final sheet in workbook.tables.values) {
      final rows = sheet.rows;
      final headerIndex = _findHeaderRow(rows);
      if (headerIndex < 0) continue;

      final headers = <String, int>{};
      for (var column = 0; column < rows[headerIndex].length; column++) {
        final header = _normalize(_cellText(rows[headerIndex][column]));
        if (header.isNotEmpty) headers[header] = column;
      }
      final nameColumn = _findColumn(headers, ['employeename']);
      final fatherColumn = _findColumn(headers, [
        'fatherhusbandname',
        'fathername',
      ]);
      final genderColumn = _findColumn(headers, ['gender']);
      final roleColumn = _findColumn(headers, ['designation', 'role']);
      final appointmentColumn = _findColumn(headers, [
        'dateofappointment',
        'appointmentdate',
      ]);
      final salaryColumn = _findColumn(headers, [
        'monthly_salary',
        'monthsalary',
        'monthlysalary',
      ]);
      if (nameColumn == null ||
          roleColumn == null ||
          appointmentColumn == null ||
          salaryColumn == null) {
        continue;
      }

      final academicColumn =
          _findColumn(headers, ['academicqualification']) ??
          _findColumn(headers, ['qualification']);
      final professionalColumn =
          _findColumn(headers, ['professionalqualification']) ??
          (academicColumn == null ? null : academicColumn + 1);
      final records = <StaffImportRecord>[];
      final errors = <String>[];
      final seen = <String>{};
      var skippedBlankRows = 0;

      for (var rowIndex = headerIndex + 1; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        final name = _valueAt(row, nameColumn);
        final father = _valueAt(row, fatherColumn);
        final role = _valueAt(row, roleColumn);
        final appointmentText = _valueAt(row, appointmentColumn);
        final salaryText = _valueAt(row, salaryColumn);
        if ([
          name,
          father,
          role,
          appointmentText,
          salaryText,
        ].every((value) => value.isEmpty)) {
          skippedBlankRows++;
          continue;
        }
        final worksheetRow = rowIndex + 1;
        if (name.isEmpty || role.isEmpty) {
          errors.add(
            'Row $worksheetRow is missing an employee name or designation.',
          );
          continue;
        }
        final salary = _parseSalary(salaryText);
        if (salary == null || salary < 0) {
          errors.add(
            'Row $worksheetRow has an invalid monthly salary: "$salaryText".',
          );
          continue;
        }
        final appointment = appointmentText.isEmpty || appointmentText == '-'
            ? null
            : _parseDate(row, appointmentColumn);
        if (appointmentText.isNotEmpty &&
            appointmentText != '-' &&
            appointment == null) {
          errors.add(
            'Row $worksheetRow has an invalid appointment date: "$appointmentText".',
          );
          continue;
        }

        final normalizedKey = [
          _normalize(name),
          _normalize(father),
        ].join('\u001f');
        if (!seen.add(normalizedKey)) {
          skippedBlankRows++;
          continue;
        }
        final importKey = 'staff:$normalizedKey';
        final employeeNumber =
            'TLC-${sha256.convert(utf8.encode(importKey)).toString().substring(0, 12).toUpperCase()}';
        records.add(
          StaffImportRecord(
            employeeNumber: employeeNumber,
            importKey: importKey,
            fullName: name,
            fatherName: father,
            gender: _valueAt(row, genderColumn),
            role: role,
            academicQualification: _valueAt(row, academicColumn),
            professionalQualification: _valueAt(row, professionalColumn),
            appointmentDate: appointment?.toIso8601String() ?? '',
            monthlySalary: salary,
            blankFields: {
              if (father.isEmpty || father == '-') 'father_name',
              if (_valueAt(row, genderColumn).isEmpty ||
                  _valueAt(row, genderColumn) == '-')
                'gender',
              if (_valueAt(row, academicColumn).isEmpty ||
                  _valueAt(row, academicColumn) == '-')
                'academic_qualification',
              if (_valueAt(row, professionalColumn).isEmpty ||
                  _valueAt(row, professionalColumn) == '-')
                'professional_qualification',
              if (appointmentText.isEmpty || appointmentText == '-')
                'appointment_date',
              if (salaryText.isEmpty || salaryText == '-') 'monthly_salary',
            },
          ),
        );
      }
      return StaffExcelImportResult(
        staff: records,
        skippedBlankRows: skippedBlankRows,
        errors: errors,
      );
    }
    throw const FormatException(
      'No worksheet contains the required Employee Name, Designation, '
      'Date of Appointment, and Monthly Salary headings.',
    );
  }

  int _findHeaderRow(List<List<Data?>> rows) {
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final cells = rows[rowIndex]
          .map((cell) => _normalize(_cellText(cell)))
          .toSet();
      if (cells.contains('employeename') &&
          cells.contains('designation') &&
          cells.any(
            (value) =>
                value == 'dateofappointment' || value == 'appointmentdate',
          ) &&
          cells.any(
            (value) =>
                value == 'monthly_salary' ||
                value == 'monthsalary' ||
                value == 'monthlysalary',
          )) {
        return rowIndex;
      }
    }
    return -1;
  }

  int? _findColumn(Map<String, int> headers, List<String> aliases) {
    for (final alias in aliases) {
      final column = headers[alias];
      if (column != null) return column;
    }
    return null;
  }

  String _valueAt(List<Data?> row, int? column) =>
      column == null || column >= row.length
      ? ''
      : _cellText(row[column]).trim();

  String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text?.trim() ?? '';
    if (value is DateTimeCellValue) {
      return _dateLabel(value.asDateTimeLocal());
    }
    return value.toString().trim();
  }

  DateTime? _parseDate(List<Data?> row, int column) {
    if (column >= row.length) return null;
    final value = row[column]?.value;
    if (value is DateTimeCellValue) {
      final date = value.asDateTimeLocal();
      return DateTime(date.year, date.month, date.day);
    }
    final text = _cellText(row[column]);
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    final dateParts = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$')
        .firstMatch(text);
    if (dateParts != null) {
      final day = int.parse(dateParts[1]!);
      final month = int.parse(dateParts[2]!);
      final year = int.parse(dateParts[3]!);
      final date = DateTime(year, month, day);
      if (date.year == year && date.month == month && date.day == day) {
        return date;
      }
    }
    if (value is IntCellValue || value is DoubleCellValue) {
      final serial = double.tryParse(value.toString());
      if (serial != null && serial >= 1 && serial < 2958466) {
        final date = DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
        return DateTime(date.year, date.month, date.day);
      }
    }
    return null;
  }

  double? _parseSalary(String value) {
    final normalized = value.replaceAll(',', '').replaceAll(' ', '').trim();
    if (normalized.isEmpty || normalized == '-') return 0;
    return double.tryParse(normalized);
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');

  String _dateLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}
