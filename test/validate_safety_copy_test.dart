import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/backup/database_backup_service.dart';

void main() {
  final backupPath = Platform.environment['TLC_SAFETY_COPY_PATH'];

  test(
    'Validate TLC School System safety copy',
    () async {
      sqfliteFfiInit();

      final database = await databaseFactoryFfi.openDatabase(
        backupPath!,
        options: OpenDatabaseOptions(readOnly: true),
      );

      try {
        print('\n========== SAFETY COPY VALIDATION ==========');

        final versionResult = await database.rawQuery('PRAGMA user_version');
        final version = versionResult.first.values.first as int;
        print('DATABASE VERSION: $version');

        final integrity = await database.rawQuery('PRAGMA integrity_check');
        final integrityResult = integrity.first.values.first.toString();
        print('DATABASE INTEGRITY: $integrityResult');

        final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' "
          'ORDER BY name',
        );
        final tableNames = tables
            .map((row) => row['name'].toString())
            .toSet();
        print('APPLICATION TABLE COUNT: ${tables.length}');

        for (final table in tables) {
          final name = table['name'].toString();
          final count = await database.rawQuery(
            'SELECT COUNT(*) AS total FROM "$name"',
          );
          print('$name: ${count.first['total']}');
        }

        final foreignKeyErrors = await database.rawQuery(
          'PRAGMA foreign_key_check',
        );
        print('FOREIGN KEY ERRORS: ${foreignKeyErrors.length}');

        final missingTables = DatabaseBackupService.requiredTables
            .where((name) => !tableNames.contains(name))
            .toList();

        expect(
          version,
          DatabaseBackupService.requiredDatabaseVersion,
          reason: 'Safety copy must use the current app database version.',
        );
        expect(integrityResult.toLowerCase(), 'ok');
        expect(
          missingTables,
          isEmpty,
          reason: 'Safety copy is missing required tables: $missingTables',
        );
        expect(foreignKeyErrors, isEmpty);
      } finally {
        await database.close();
      }
    },
    skip: backupPath == null
        ? 'Set TLC_SAFETY_COPY_PATH to a real safety-copy file to run this manual validation.'
        : false,
  );
}
