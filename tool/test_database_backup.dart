import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/data/app_database.dart';

Future<void> main() async {
  sqfliteFfiInit();

  final database = await AppDatabase.instance.database;
  final version = await database.rawQuery(
    'SELECT sqlite_version() AS version',
  );

  print('SQLite version: ${version.first['version']}');

  final snapshot = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'tlc_backup_test.db',
  );

  try {
    if (await snapshot.exists()) {
      await snapshot.delete();
    }

    await database.execute(
      'VACUUM INTO ?',
      [snapshot.path],
    );

    print('Snapshot created: ${await snapshot.exists()}');
    print('Snapshot size: ${await snapshot.length()} bytes');

    final testDb = await databaseFactoryFfi.openDatabase(
      snapshot.path,
      options: OpenDatabaseOptions(readOnly: true),
    );

    try {
      final integrity = await testDb.rawQuery(
        'PRAGMA integrity_check',
      );

      print('Integrity check: ${integrity.first.values.first}');

      final tables = await testDb.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );

      print('Application tables: ${tables.length}');
    } finally {
      await testDb.close();
    }
  } finally {
    await database.close();
    if (await snapshot.exists()) {
      await snapshot.delete();
    }
  }
}
