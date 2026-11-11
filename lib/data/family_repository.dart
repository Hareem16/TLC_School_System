import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../student.dart';
import 'app_database.dart';
import 'family_excel_importer.dart';

class FamilyGroup {
  final String familyNo;
  final List<Student> students;

  const FamilyGroup({required this.familyNo, required this.students});

  String get fatherName => students
      .map((student) => student.guardianName.trim())
      .firstWhere((name) => name.isNotEmpty, orElse: () => 'Not provided');
}

class FamilyImportCounts {
  final int updated;
  final int unchanged;

  const FamilyImportCounts({required this.updated, required this.unchanged});
}

class FamilyRepository {
  Future<List<FamilyGroup>> getFamilies() async {
    final database = await AppDatabase.instance.database;
    final rows = await database.query(
      'students',
      where: "TRIM(COALESCE(family_no, '')) != ''",
      orderBy:
          'family_no COLLATE NOCASE, class_name COLLATE NOCASE, first_name COLLATE NOCASE',
    );
    final groups = <String, List<Student>>{};
    final familyLabels = <String, String>{};
    for (final row in rows) {
      final student = Student.fromDatabaseMap(row);
      final key = student.familyNo.trim().toLowerCase();
      familyLabels.putIfAbsent(key, () => student.familyNo.trim());
      groups.putIfAbsent(key, () => []).add(student);
    }
    return [
      for (final entry in groups.entries)
        FamilyGroup(
          familyNo: familyLabels[entry.key]!,
          students: List.unmodifiable(entry.value),
        ),
    ];
  }

  Future<FamilyImportCounts> importSiblingAssignments(
    List<FamilyImportRecord> records,
  ) async {
    if (records.isEmpty) {
      throw ArgumentError('The sibling workbook contains no assignments.');
    }
    final database = await AppDatabase.instance.database;
    var updated = 0;
    var unchanged = 0;
    await database.transaction((transaction) async {
      for (final record in records) {
        final existing = await transaction.query(
          'students',
          columns: ['student_id', 'family_no'],
          where: 'LOWER(TRIM(admission_number)) = LOWER(TRIM(?))',
          whereArgs: [record.admissionNumber],
          limit: 1,
        );
        if (existing.isEmpty) {
          throw FormatException(
            'G.R. number ${record.admissionNumber} was not found in student records. '
            'Import or correct the student register before importing families.',
          );
        }
        final studentId = existing.single['student_id']! as String;
        final previousFamilyNo =
            (existing.single['family_no'] as String?)?.trim() ?? '';
        if (previousFamilyNo == record.familyNo.trim()) {
          unchanged++;
          continue;
        }
        await transaction.update(
          'students',
          {'family_no': record.familyNo.trim()},
          where: 'student_id = ?',
          whereArgs: [studentId],
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        updated++;
      }
    });
    return FamilyImportCounts(updated: updated, unchanged: unchanged);
  }
}
