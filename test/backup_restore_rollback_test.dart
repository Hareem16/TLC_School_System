import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tlc_school_system/backup/database_backup_service.dart';
import 'package:tlc_school_system/data/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('restore failure after moving original database restores all original records', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tlc_restore_rollback_',
    );

    final backupPath = '${directory.path}${Platform.pathSeparator}candidate.db';

    Database? database;

    try {
      await AppDatabase.instance.close();
      databaseFactory = databaseFactoryFfi;
      await databaseFactoryFfi.setDatabasesPath(directory.path);

      database = await AppDatabase.instance.database;

      await database.insert('students', {
        'student_id': 'rollback-student-1',
        'admission_number': 'ROLLBACK-001',
        'first_name': 'Original',
        'last_name': 'Student',
        'class_name': 'Class 8',
        'created_at': '2026-11-15T08:00:00',
      });

      await database.execute('VACUUM INTO ?', [backupPath]);

      await database.insert('students', {
        'student_id': 'rollback-student-2',
        'admission_number': 'ROLLBACK-002',
        'first_name': 'Second',
        'last_name': 'Student',
        'class_name': 'Class 9',
        'created_at': '2026-11-15T08:05:00',
      });

      final service = DatabaseBackupService(
        afterOriginalMovedForTesting: () async {
          throw StateError('SIMULATED RESTORE FAILURE');
        },
      );

      await expectLater(
        service.restoreBackup(backupPath),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'SIMULATED RESTORE FAILURE',
          ),
        ),
      );

      database = await AppDatabase.instance.database;

      final students = await database.query(
        'students',
        orderBy: 'admission_number',
      );

      expect(students, hasLength(2));
      expect(students.map((student) => student['admission_number']).toList(), [
        'ROLLBACK-001',
        'ROLLBACK-002',
      ]);

      final integrity = await database.rawQuery('PRAGMA integrity_check');
      expect(integrity.single.values.single, 'ok');

      final foreignKeys = await database.rawQuery('PRAGMA foreign_key_check');
      expect(foreignKeys, isEmpty);

      final safetyCopies = directory
          .listSync()
          .where(
            (entity) =>
                entity is File &&
                entity.path.contains('TLC_PreRestore_Safety_'),
          )
          .toList();

      expect(safetyCopies, hasLength(1));
      expect(await File(backupPath).exists(), isTrue);

      expect(
        await File(
          '${directory.path}${Platform.pathSeparator}'
          'tlc_school_system.restore.tmp',
        ).exists(),
        isFalse,
      );

      expect(
        await File(
          '${directory.path}${Platform.pathSeparator}'
          'tlc_school_system.rollback.db',
        ).exists(),
        isFalse,
      );
    } finally {
      await database?.close();
      await AppDatabase.instance.close();
      await directory.delete(recursive: true);
    }
  });
}
