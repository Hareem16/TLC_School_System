import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  final result = await db.rawQuery('SELECT sqlite_version() AS version');
  print('TLC SQLite version: ${result.first['version']}');
  await db.close();
}
