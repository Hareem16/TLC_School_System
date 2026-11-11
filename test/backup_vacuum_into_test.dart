import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('VACUUM INTO creates a valid database backup', () async {
    sqfliteFfiInit();

    const sourcePath =
        r'D:\TLC_School_Backups\SQLite\TLC_Windows_DB_20261109.db';

    final source = File(sourcePath);
    expect(await source.exists(), isTrue,
        reason: 'Verified source backup must exist.');

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final target = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'tlc_vacuum_test_$timestamp.db',
    );

    final factory = databaseFactoryFfi;
    Database? sourceDb;
    Database? backupDb;

    try {
      sourceDb = await factory.openDatabase(
        sourcePath,
        options: OpenDatabaseOptions(readOnly: true),
      );

      await sourceDb.execute(
        'VACUUM INTO ?',
        [target.path],
      );

      expect(await target.exists(), isTrue);
      expect(await target.length(), greaterThan(0));

      backupDb = await factory.openDatabase(
        target.path,
        options: OpenDatabaseOptions(readOnly: true),
      );

      final integrity = await backupDb.rawQuery(
        'PRAGMA integrity_check',
      );

      expect(integrity.first.values.first, 'ok');

      final tables = await backupDb.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );

      expect(tables.length, 23);

      print('VACUUM INTO: SUCCESS');
      print('Backup size: ${await target.length()} bytes');
      print('Integrity: ${integrity.first.values.first}');
      print('Application tables: ${tables.length}');
    } finally {
      await backupDb?.close();
      await sourceDb?.close();

      if (await target.exists()) {
        await target.delete();
      }
    }
  });
}
