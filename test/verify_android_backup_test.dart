import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final backupPath = Platform.environment['TLC_ANDROID_BACKUP'];

  test(
    'Verify Android database backup',
    () async {
      sqfliteFfiInit();

      final path = backupPath!.trim();
      final backupFile = File(path);
      expect(
        await backupFile.exists(),
        isTrue,
        reason: 'TLC_ANDROID_BACKUP points to a file that does not exist: $path',
      );

      final database = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true),
      );

      try {
        final integrity = await database.rawQuery('PRAGMA integrity_check');
        final result = integrity.first.values.first.toString();

        print('DATABASE INTEGRITY: $result');

        final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
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

        expect(result.toLowerCase(), 'ok');
        expect(tables, isNotEmpty);
      } finally {
        await database.close();
      }
    },
    skip: backupPath == null || backupPath.trim().isEmpty
        ? 'Set TLC_ANDROID_BACKUP to a real Android database backup to run this device-specific check.'
        : false,
  );
}
