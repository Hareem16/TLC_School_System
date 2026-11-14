import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final backupPath = Platform.environment['TLC_SAFETY_COPY_BACKUP'];

  test(
    'Validate TLC School System safety copy',
    () async {
      sqfliteFfiInit();

      final path = backupPath!.trim();
      final backupFile = File(path);
      expect(
        await backupFile.exists(),
        isTrue,
        reason: 'TLC_SAFETY_COPY_BACKUP points to a file that does not exist: $path',
      );

      final database = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true),
      );

      try {
        print('\\n========== SAFETY COPY VALIDATION ==========');

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
          "ORDER BY name",
        );
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

        expect(version, 14);
        expect(integrityResult.toLowerCase(), 'ok');
        expect(tables.length, 23);
        expect(foreignKeyErrors, isEmpty);
      } finally {
        await database.close();
      }
    },
    skip: backupPath == null || backupPath.trim().isEmpty
        ? 'Set TLC_SAFETY_COPY_BACKUP to a real safety-copy database to run this device-specific check.'
        : false,
  );
}
