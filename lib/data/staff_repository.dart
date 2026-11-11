import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_database.dart';
import 'record_id.dart';
import 'staff_excel_importer.dart';

class StaffMember {
  final String id;
  final String employeeNumber;
  final String fullName;
  final String fatherName;
  final String gender;
  final String role;
  final String academicQualification;
  final String professionalQualification;
  final String appointmentDate;
  final double monthlySalary;

  const StaffMember({
    required this.id,
    required this.employeeNumber,
    required this.fullName,
    required this.fatherName,
    required this.gender,
    required this.role,
    required this.academicQualification,
    required this.professionalQualification,
    required this.appointmentDate,
    required this.monthlySalary,
  });

  factory StaffMember.fromDatabaseMap(Map<String, Object?> row) => StaffMember(
    id: row['staff_id']! as String,
    employeeNumber: row['employee_number']! as String,
    fullName: row['full_name']! as String,
    fatherName: (row['father_name'] as String?) ?? '',
    gender: (row['gender'] as String?) ?? '',
    role: row['role']! as String,
    academicQualification: (row['academic_qualification'] as String?) ?? '',
    professionalQualification:
        (row['professional_qualification'] as String?) ?? '',
    appointmentDate: (row['appointment_date'] as String?) ?? '',
    monthlySalary: (row['monthly_salary']! as num).toDouble(),
  );
}

class StaffImportCounts {
  final int imported;
  final int updated;
  final int unchanged;

  const StaffImportCounts({
    required this.imported,
    required this.updated,
    required this.unchanged,
  });
}

class StaffRepository {
  Future<List<StaffMember>> getAll({String search = ''}) async {
    final database = await AppDatabase.instance.database;
    final normalizedSearch = '%${search.trim()}%';
    final rows = await database.query(
      'staff',
      where: search.trim().isEmpty
          ? null
          : 'full_name LIKE ? OR role LIKE ? OR employee_number LIKE ?',
      whereArgs: search.trim().isEmpty
          ? null
          : [normalizedSearch, normalizedSearch, normalizedSearch],
      orderBy: '''
        CASE
          WHEN LOWER(role) LIKE '%principal%' THEN 0
          WHEN LOWER(role) LIKE '%admin%' THEN 1
          WHEN REPLACE(REPLACE(LOWER(role), '.', ''), ' ', '') LIKE '%fdo%'
            OR LOWER(role) LIKE '%front desk%' THEN 2
          WHEN LOWER(role) LIKE '%teacher%' THEN 3
          WHEN LOWER(role) LIKE '%auxiliary%'
            OR LOWER(role) LIKE '%auxilary%'
            OR LOWER(role) LIKE '%auxillary%' THEN 4
          ELSE 5
        END,
        role COLLATE NOCASE,
        full_name COLLATE NOCASE
      ''',
    );
    return rows.map(StaffMember.fromDatabaseMap).toList(growable: false);
  }

  Future<StaffImportCounts> importStaff(List<StaffImportRecord> staff) async {
    final database = await AppDatabase.instance.database;
    var imported = 0;
    var updated = 0;
    var unchanged = 0;
    await database.transaction((transaction) async {
      for (final member in staff) {
        final existing = await transaction.query(
          'staff',
          where: 'import_key = ? OR (LOWER(TRIM(full_name)) = LOWER(TRIM(?)) AND LOWER(TRIM(father_name)) = LOWER(TRIM(?)))',
          whereArgs: [
            member.importKey,
            member.fullName,
            member.fatherName,
          ],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final row = existing.single;
          final values = <String, Object?>{
            'full_name': member.fullName,
            'role': member.role,
            'father_name': member.fatherName,
            'gender': member.gender,
            'academic_qualification': member.academicQualification,
            'professional_qualification': member.professionalQualification,
            'appointment_date': member.appointmentDate,
            'monthly_salary': member.monthlySalary,
          }..removeWhere(
            (field, value) =>
                member.blankFields.contains(field) ||
                row[field] == value,
          );
          if (values.isNotEmpty) {
            await transaction.update(
              'staff',
              values,
              where: 'staff_id = ?',
              whereArgs: [row['staff_id']],
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
            updated++;
          } else {
            unchanged++;
          }
          continue;
        }
        await transaction.insert('staff', {
          'staff_id': newRecordId(),
          'employee_number': member.employeeNumber,
          'full_name': member.fullName,
          'role': member.role,
          'phone': null,
          'monthly_salary': member.monthlySalary,
          'father_name': member.fatherName,
          'gender': member.gender,
          'academic_qualification': member.academicQualification,
          'professional_qualification': member.professionalQualification,
          'appointment_date': member.appointmentDate,
          'import_key': member.importKey,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        imported++;
      }
    });
    return StaffImportCounts(
      imported: imported,
      updated: updated,
      unchanged: unchanged,
    );
  }
}
