import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('Validate TLC School System safety copy', () async {
    sqfliteFfiInit();

    const backupPath =
        r'D:\TLC_School_System_Safety_Backups'
        r'\TLC_School_System_2026-11-09_21-29-34.db';

    final database = await databaseFactoryFfi.openDatabase(
      backupPath,
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
  });
}
