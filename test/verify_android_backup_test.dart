import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('Verify Android database backup', () async {
    sqfliteFfiInit();

    final database = await databaseFactoryFfi.openDatabase(
      r'D:\TLC_School_Backups\Android\TLC_School_System_Backup_2026-11-09T15-19-03-249085.db',
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
  });
}
