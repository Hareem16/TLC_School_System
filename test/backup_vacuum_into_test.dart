import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('VACUUM INTO creates a valid independent database backup', () async {
    sqfliteFfiInit();

    final factory = databaseFactoryFfi;
    final tempDirectory =
        await Directory.systemTemp.createTemp('tlc_vacuum_test_');

    final sourcePath =
        '${tempDirectory.path}${Platform.pathSeparator}source.db';
    final targetPath =
        '${tempDirectory.path}${Platform.pathSeparator}backup.db';

    Database? sourceDb;
    Database? backupDb;

    try {
      sourceDb = await factory.openDatabase(
        sourcePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE test_records ('
              'id INTEGER PRIMARY KEY, '
              'record_name TEXT NOT NULL'
              ')',
            );
            await db.insert('test_records', {
              'record_name': 'TLC backup verification',
            });
          },
        ),
      );

      await sourceDb.execute('VACUUM INTO ?', [targetPath]);

      final target = File(targetPath);
      expect(await target.exists(), isTrue);
      expect(await target.length(), greaterThan(0));

      backupDb = await factory.openDatabase(
        targetPath,
        options: OpenDatabaseOptions(readOnly: true),
      );

      final integrity = await backupDb.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');

      final records = await backupDb.query('test_records');
      expect(records.length, 1);
      expect(
        records.first['record_name'],
        'TLC backup verification',
      );

      print('VACUUM INTO: SUCCESS');
      print('Backup size: ${await target.length()} bytes');
      print('Integrity: ${integrity.first.values.first}');
    } finally {
      await backupDb?.close();
      await sourceDb?.close();

      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  });
}
