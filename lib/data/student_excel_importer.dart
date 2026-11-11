import 'package:excel/excel.dart';

import 'excel_workbook_decoder.dart';
import '../student.dart';

class StudentExcelImportResult {
  final List<Student> students;
  final int skippedBlankRows;
  final List<String> errors;
  final Set<String> includedFields;
  final Map<String, Set<String>> emptyFieldsByAdmissionNumber;

  const StudentExcelImportResult({
    required this.students,
    required this.skippedBlankRows,
    required this.errors,
    required this.includedFields,
    required this.emptyFieldsByAdmissionNumber,
  });
}

class StudentExcelImporter {
  StudentExcelImportResult parse(List<int> bytes) {
    final workbook = ExcelWorkbookDecoder.decode(bytes);
    if (workbook.tables.isEmpty) {
      throw const FormatException('The workbook does not contain a worksheet.');
    }

    for (final sheet in workbook.tables.values) {
      final rows = sheet.rows;
      final headerRowIndex = _findHeaderRow(rows);
      if (headerRowIndex == -1) continue;

      final headers = <String, int>{};
      for (var column = 0; column < rows[headerRowIndex].length; column++) {
        final header = _normalizeHeader(
          _cellText(rows[headerRowIndex][column]),
        );
        if (header.isNotEmpty) headers[header] = column;
      }

      final registerColumn = _findColumn(headers, [
        'registerno',
        'grno',
        'grnumber',
        'admissionnumber',
      ]);
      final classColumn = _findColumn(headers, ['currentclass', 'class']);
      final rollNumberColumn = _findColumn(headers, [
        'rollno',
        'rollnumber',
        'classrollnumber',
      ]);
      final nameColumn = _findColumn(headers, [
        'nameofthestudent',
        'nameofstudent',
        'studentname',
        'name',
      ]);
      final monthlyFeeColumn = _findColumn(headers, [
        'monthlyfee',
        'monthlyfees',
        'individualmonthlyfee',
        'monthlycharge',
        'monthlyfeepkr',
      ]);
      if (registerColumn == null || classColumn == null || nameColumn == null) {
        throw const FormatException(
          'The register sheet must contain a G.R. / Register No., CLASS / Current Class, and student-name column.',
        );
      }

      final students = <Student>[];
      final errors = <String>[];
      final seenAdmissionNumbers = <String, int>{};
      var skippedBlankRows = 0;
      final emptyFieldsByAdmissionNumber = <String, Set<String>>{};

      for (
        var rowIndex = headerRowIndex + 1;
        rowIndex < rows.length;
        rowIndex++
      ) {
        final row = rows[rowIndex];
        final admissionNumber = _valueAt(row, registerColumn);
        final studentName = _valueAt(row, nameColumn);
        final className = _valueAt(row, classColumn);
        if (admissionNumber.isEmpty &&
            studentName.isEmpty &&
            className.isEmpty) {
          skippedBlankRows++;
          continue;
        }

        final worksheetRow = rowIndex + 1;
        if (admissionNumber.isEmpty ||
            studentName.isEmpty ||
            className.isEmpty) {
          errors.add(
            'Row $worksheetRow is missing a G.R. number, student name, or current class.',
          );
          continue;
        }
        final firstRow = seenAdmissionNumbers.putIfAbsent(
          admissionNumber.toLowerCase(),
          () => worksheetRow,
        );
        if (firstRow != worksheetRow) {
          errors.add(
            'Rows $firstRow and $worksheetRow use G.R. number $admissionNumber. '
            'Correct this duplicate before importing.',
          );
          continue;
        }

        final dateOfBirth = _dateAt(
          row,
          headers,
          ['dateofbirth', 'dob'],
          'date of birth',
          worksheetRow,
          errors,
        );
        final dateOfAdmission = _dateAt(
          row,
          headers,
          ['dateofadmission', 'admissiondate'],
          'date of admission',
          worksheetRow,
          errors,
        );
        final monthlyFee = _monthlyFeeAt(
          row,
          monthlyFeeColumn,
          worksheetRow,
          errors,
        );
        final emptyFields = <String>{
          if (rollNumberColumn != null &&
              _valueAt(row, rollNumberColumn).isEmpty)
            'roll_number',
          if (_isEmpty(row, headers, ['gender'])) 'gender',
          if (_isEmpty(row, headers, ['religion'])) 'religion',
          if (_isEmpty(row, headers, ['dateofbirth', 'dob'])) 'date_of_birth',
          if (_isEmpty(row, headers, ['placeofbirth'])) 'place_of_birth',
          if (_isEmpty(row, headers, ['address'])) 'address',
          if (_isEmpty(row, headers, [
            'fathersname',
            'fathername',
            'fatherguardian',
          ]))
            'guardian_name',
          if (_isEmpty(row, headers, ['contactno', 'contactnumber', 'phone']))
            'guardian_phone',
          if (_isEmpty(row, headers, ['section', 'sectionname']))
            'section_name',
          if (_isEmpty(row, headers, [
            'dateofadmission',
            'admissiondate',
          ]))
            'date_of_admission',
          if (_isEmpty(row, headers, [
            'lastinstitutionattended',
            'previousinstitute',
          ]))
            'previous_institute',
          if (_isEmpty(row, headers, [
            'classinwhichadmitted',
            'admittedclass',
            'classadmitted',
          ]))
            'admitted_class',
          if (monthlyFeeColumn != null &&
              (_valueAt(row, monthlyFeeColumn).isEmpty ||
                  _valueAt(row, monthlyFeeColumn) == '-'))
            'monthly_fee',
          if (_isEmpty(row, headers, ['dateofremoval', 'removaldate']))
            'date_of_removal',
          if (_isEmpty(row, headers, [
            'classatthetimeofremoval',
            'classatremoval',
          ]))
            'class_at_removal',
          if (_isEmpty(row, headers, ['causeofremoval'])) 'cause_of_removal',
          if (_isEmpty(row, headers, ['remarks'])) 'remarks',
          if (_isEmpty(row, headers, [
            'familyno',
            'familynumber',
            'familyid',
            'family',
          ]))
            'family_no',
        };
        emptyFieldsByAdmissionNumber[admissionNumber] = emptyFields;
        students.add(
          Student(
            studentId: 'excel_${admissionNumber.toLowerCase()}',
            admissionNumber: admissionNumber,
            rollNumber: rollNumberColumn == null
                ? ''
                : _valueAt(row, rollNumberColumn),
            firstName: studentName,
            lastName: '',
            className: className,
            sectionName: _valueByHeader(row, headers, [
              'section',
              'sectionname',
            ]),
            guardianName: _valueByHeader(row, headers, [
              'fathersname',
              'fathername',
              'fatherguardian',
            ]),
            guardianPhone: _valueByHeader(row, headers, [
              'contactno',
              'contactnumber',
              'phone',
            ]),
            gender: _gender(_valueByHeader(row, headers, ['gender'])),
            religion: _valueByHeader(row, headers, ['religion']),
            dateOfBirth: dateOfBirth,
            placeOfBirth: _valueByHeader(row, headers, ['placeofbirth']),
            address: _valueByHeader(row, headers, ['address']),
            familyNo: _valueByHeader(row, headers, [
              'familyno',
              'familynumber',
              'familyid',
              'family',
            ]),
            dateOfAdmission: dateOfAdmission,
            previousInstitute: _valueByHeader(row, headers, [
              'lastinstitutionattended',
              'previousinstitute',
            ]),
            admittedClass: _valueByHeader(row, headers, [
              'classinwhichadmitted',
              'admittedclass',
              'classadmitted',
            ]),
            dateOfRemoval: _dateAt(
              row,
              headers,
              ['dateofremoval', 'removaldate'],
              'date of removal',
              worksheetRow,
              errors,
            ),
            classAtRemoval: _valueByHeader(row, headers, [
              'classatthetimeofremoval',
              'classatremoval',
            ]),
            causeOfRemoval: _valueByHeader(row, headers, ['causeofremoval']),
            remarks: _valueByHeader(row, headers, ['remarks']),
            monthlyFee: monthlyFee,
            createdAt: dateOfAdmission ?? DateTime.now(),
          ),
        );
      }

      return StudentExcelImportResult(
        students: students,
        skippedBlankRows: skippedBlankRows,
        errors: errors,
        includedFields: {
          if (_findColumn(headers, ['gender']) != null) 'gender',
          if (rollNumberColumn != null) 'roll_number',
          if (_findColumn(headers, ['religion']) != null) 'religion',
          if (_findColumn(headers, ['dateofbirth', 'dob']) != null)
            'date_of_birth',
          if (_findColumn(headers, ['placeofbirth']) != null) 'place_of_birth',
          if (_findColumn(headers, ['address']) != null) 'address',
          if (_findColumn(headers, [
                'fathersname',
                'fathername',
                'fatherguardian',
              ]) !=
              null)
            'guardian_name',
          if (_findColumn(headers, ['contactno', 'contactnumber', 'phone']) !=
              null)
            'guardian_phone',
          if (_findColumn(headers, ['section', 'sectionname']) != null)
            'section_name',
          if (_findColumn(headers, ['dateofadmission', 'admissiondate']) !=
              null)
            'date_of_admission',
          if (_findColumn(headers, [
                'lastinstitutionattended',
                'previousinstitute',
              ]) !=
              null)
            'previous_institute',
          if (_findColumn(headers, [
                'classinwhichadmitted',
                'admittedclass',
                'classadmitted',
              ]) !=
              null)
            'admitted_class',
          if (monthlyFeeColumn != null) 'monthly_fee',
          if (_findColumn(headers, ['dateofremoval', 'removaldate']) != null)
            'date_of_removal',
          if (_findColumn(headers, [
                'classatthetimeofremoval',
                'classatremoval',
              ]) !=
              null)
            'class_at_removal',
          if (_findColumn(headers, ['causeofremoval']) != null)
            'cause_of_removal',
          if (_findColumn(headers, ['remarks']) != null) 'remarks',
          if (_findColumn(headers, [
                'familyno',
                'familynumber',
                'familyid',
                'family',
              ]) !=
              null)
            'family_no',
        },
        emptyFieldsByAdmissionNumber: emptyFieldsByAdmissionNumber,
      );
    }

    throw const FormatException(
      'No worksheet has the expected student register headings.',
    );
  }

  int _findHeaderRow(List<List<Data?>> rows) {
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final headers = rows[rowIndex]
          .map((cell) => _normalizeHeader(_cellText(cell)))
          .toSet();
      final hasRegister =
          headers.contains('registerno') ||
          headers.contains('grno') ||
          headers.contains('grnumber');
      final hasName =
          headers.contains('nameofthestudent') ||
          headers.contains('nameofstudent') ||
          headers.contains('studentname');
      final hasClass =
          headers.contains('currentclass') || headers.contains('class');
      if (hasRegister && hasName && hasClass) return rowIndex;
    }
    return -1;
  }

  int? _findColumn(Map<String, int> headers, List<String> aliases) {
    for (final alias in aliases) {
      final index = headers[alias];
      if (index != null) return index;
    }
    return null;
  }

  String _valueAt(List<Data?> row, int? column) {
    if (column == null || column >= row.length) return '';
    return _cellText(row[column]).trim();
  }

  String _valueByHeader(
    List<Data?> row,
    Map<String, int> headers,
    List<String> aliases,
  ) => _valueAt(row, _findColumn(headers, aliases));

  bool _isEmpty(
    List<Data?> row,
    Map<String, int> headers,
    List<String> aliases,
  ) {
    final value = _valueByHeader(row, headers, aliases);
    return value.isEmpty || value == '-';
  }

  DateTime? _dateAt(
    List<Data?> row,
    Map<String, int> headers,
    List<String> aliases,
    String label,
    int worksheetRow,
    List<String> errors,
  ) {
    final value = _valueByHeader(row, headers, aliases);
    final parsed = _parseDate(value);
    if (value.isNotEmpty && value != '-' && parsed == null) {
      errors.add('Row $worksheetRow has an invalid $label: "$value".');
    }
    return parsed;
  }

  double _monthlyFeeAt(
    List<Data?> row,
    int? column,
    int worksheetRow,
    List<String> errors,
  ) {
    final value = _valueAt(row, column);
    if (value.isEmpty || value == '-') return 0;
    final normalized = value
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.\-]'), '');
    final fee = double.tryParse(normalized);
    if (fee == null || fee < 0) {
      errors.add('Row $worksheetRow has an invalid monthly fee: "$value".');
      return 0;
    }
    return fee;
  }

  String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is TextCellValue) return value.value.toString().trim();
    return value.toString().trim();
  }

  String _normalizeHeader(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  String _gender(String value) {
    switch (value.trim().toLowerCase()) {
      case 'boy':
      case 'male':
        return 'Boy';
      case 'girl':
      case 'female':
        return 'Girl';
      case '':
        return 'Unknown';
      default:
        return value.trim();
    }
  }

  DateTime? _parseDate(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') return null;

    final isoDate = DateTime.tryParse(normalized);
    if (isoDate != null) {
      return DateTime(isoDate.year, isoDate.month, isoDate.day);
    }

    final ordinalDate = normalized
        .toLowerCase()
        .replaceAllMapped(
          RegExp(r'(\d+)(st|nd|rd|th)\b'),
          (match) => match.group(1)!,
        )
        .replaceAll(',', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final textualDate = RegExp(r'^(\d{1,2})\s+([a-z]+)\s+(\d{4})$')
        .firstMatch(ordinalDate);
    if (textualDate != null) {
      final day = int.parse(textualDate.group(1)!);
      final month = _monthNumber(textualDate.group(2)!);
      final year = int.parse(textualDate.group(3)!);
      if (month != null) return _validDate(year, month, day);
    }

    final numericDate = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$')
        .firstMatch(normalized);
    if (numericDate != null) {
      return _validDate(
        int.parse(numericDate.group(3)!),
        int.parse(numericDate.group(2)!),
        int.parse(numericDate.group(1)!),
      );
    }
    return null;
  }

  DateTime? _validDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  int? _monthNumber(String month) {
    const months = {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    return months[month];
  }
}
