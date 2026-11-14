import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('VACUUM INTO creates a valid database backup', () async {
    sqfliteFfiInit();

    // CI must not depend on a database stored on a developer's D: drive.
    // Build a disposable source database so the backup operation is tested
    // on every platform, including GitHub Actions' Linux runners.
    final directory = await Directory.systemTemp.createTemp(
      'tlc_vacuum_into_test_',
    );
    final sourcePath = '${directory.path}${Platform.pathSeparator}source.db';
    final targetPath = '${directory.path}${Platform.pathSeparator}backup.db';

    Database? sourceDb;
    Database? backupDb;

    try {
      sourceDb = await databaseFactoryFfi.openDatabase(sourcePath);
      await sourceDb.execute(
        'CREATE TABLE backup_probe (id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
      );
      await sourceDb.insert('backup_probe', {'value': 'TLC backup verification'});
      await sourceDb.close();
      sourceDb = null;

      sourceDb = await databaseFactoryFfi.openDatabase(
        sourcePath,
        options: OpenDatabaseOptions(readOnly: true),
      );

      await sourceDb.execute('VACUUM INTO ?', [targetPath]);

      final target = File(targetPath);
      expect(await target.exists(), isTrue);
      expect(await target.length(), greaterThan(0));

      backupDb = await databaseFactoryFfi.openDatabase(
        targetPath,
        options: OpenDatabaseOptions(readOnly: true),
      );

      final integrity = await backupDb.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');

      final rows = await backupDb.query('backup_probe');
      expect(rows, hasLength(1));
      expect(rows.single['value'], 'TLC backup verification');

      print('VACUUM INTO: SUCCESS');
      print('Backup size: ${await target.length()} bytes');
      print('Integrity: ${integrity.first.values.first}');
    } finally {
      await backupDb?.close();
      await sourceDb?.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });
}
