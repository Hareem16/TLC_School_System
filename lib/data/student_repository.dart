import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../student.dart';
import 'app_database.dart';

class StudentImportCounts {
  final int imported;
  final int updated;
  final int unchanged;

  const StudentImportCounts({
    required this.imported,
    required this.updated,
    required this.unchanged,
  });
}

class StudentRepository {
  Future<List<Student>> getAll({
    List<String>? classSectionKeys,
    List<String>? studentIds,
  }) async {
    final database = await AppDatabase.instance.database;
    final clauses = <String>[];
    final arguments = <Object?>[];

    if (studentIds != null) {
      if (studentIds.isEmpty) return const [];
      clauses.add(
        'student_id IN (${List.filled(studentIds.length, '?').join(',')})',
      );
      arguments.addAll(studentIds);
    }
    if (classSectionKeys != null) {
      if (classSectionKeys.isEmpty) return const [];
      final classFilters = <String>[];
      for (final key in classSectionKeys) {
        final parts = key.split('\u001f');
        if (parts.length != 2) {
          throw FormatException('Invalid class-section access key: $key');
        }
        classFilters.add("(class_name = ? AND COALESCE(section_name, '') = ?)");
        arguments
          ..add(parts[0])
          ..add(parts[1]);
      }
      clauses.add('(${classFilters.join(' OR ')})');
    }

    final rows = await database.query(
      'students',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'created_at DESC',
    );
    return rows.map(Student.fromDatabaseMap).toList();
  }

  Future<void> save(Student student) async {
    final database = await AppDatabase.instance.database;
    await database.insert(
      'students',
      student.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(Student student) async {
    final database = await AppDatabase.instance.database;
    await database.update(
      'students',
      student.toDatabaseMap(),
      where: 'student_id = ?',
      whereArgs: [student.studentId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<StudentImportCounts> importStudents(
    List<Student> students, {
    required Set<String> includedFields,
    required Map<String, Set<String>> emptyFieldsByAdmissionNumber,
  }) async {
    final database = await AppDatabase.instance.database;
    var imported = 0;
    var updated = 0;
    var unchanged = 0;
    const requiredFields = {
      'admission_number',
      'first_name',
      'last_name',
      'class_name',
    };

    await database.transaction((transaction) async {
      for (final student in students) {
        final existing = await transaction.query(
          'students',
          where: 'LOWER(TRIM(admission_number)) = LOWER(TRIM(?))',
          whereArgs: [student.admissionNumber],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final existingRow = existing.single;
          final values = student.toDatabaseMap()
            ..remove('student_id')
            ..remove('created_at')
            ..removeWhere(
              (field, _) =>
                  !requiredFields.contains(field) &&
                  (!includedFields.contains(field) ||
                      emptyFieldsByAdmissionNumber[
                              student.admissionNumber
                          ]?.contains(field) ==
                          true),
            );
          final existingFullName =
              '${existingRow['first_name']} ${existingRow['last_name']}'.trim();
          if (existingFullName == student.firstName.trim()) {
            values
              ..remove('first_name')
              ..remove('last_name');
          }

          final hasChanges = values.entries.any(
            (entry) => existingRow[entry.key] != entry.value,
          );
          if (hasChanges) {
            await transaction.update(
              'students',
              values,
              where: 'student_id = ?',
              whereArgs: [existingRow['student_id']],
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
            updated++;
          } else {
            unchanged++;
          }
          continue;
        }
        await transaction.insert(
          'students',
          student.toDatabaseMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        imported++;
      }
    });

    return StudentImportCounts(
      imported: imported,
      updated: updated,
      unchanged: unchanged,
    );
  }

  Future<List<Student>> getFamilyMembers(List<Student> linkedStudents) async {
    if (linkedStudents.isEmpty) return const [];
    final database = await AppDatabase.instance.database;
    final studentIds = linkedStudents.map((student) => student.studentId);
    final familyNumbers = linkedStudents
        .map((student) => student.familyNo.trim())
        .where((familyNo) => familyNo.isNotEmpty)
        .toSet()
        .map((familyNo) => familyNo.toLowerCase())
        .toList(growable: false);
    final idPlaceholders = List.filled(studentIds.length, '?').join(',');
    final familyClause = familyNumbers.isEmpty
        ? ''
        : ' OR LOWER(TRIM(family_no)) IN (${List.filled(familyNumbers.length, '?').join(',')})';
    final rows = await database.query(
      'students',
      where: '(student_id IN ($idPlaceholders)$familyClause)',
      whereArgs: [...studentIds, ...familyNumbers],
      orderBy: 'class_name COLLATE NOCASE, first_name COLLATE NOCASE',
    );
    return rows.map(Student.fromDatabaseMap).toList(growable: false);
  }

  Future<void> delete(String studentId) async {
    final database = await AppDatabase.instance.database;
    await database.delete(
      'students',
      where: 'student_id = ?',
      whereArgs: [studentId],
    );
  }
}
