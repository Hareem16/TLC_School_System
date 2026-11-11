import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final directory = await getApplicationSupportDirectory();

    if (Platform.isWindows) {
      ffi.sqfliteFfiInit();

      _database = await ffi.databaseFactoryFfi.openDatabase(
        p.join(directory.path, 'tlc_school_system.db'),
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await _createTables(db);
          },
        ),
      );
    } else {
      _database = await openDatabase(
        p.join(directory.path, 'tlc_school_system.db'),
        version: 1,
        onCreate: (db, version) async {
          await _createTables(db);
        },
      );
    }

    return _database!;
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE school_settings (
        school_id TEXT PRIMARY KEY,
        school_name TEXT NOT NULL,
        motto TEXT NOT NULL,
        academic_year TEXT NOT NULL,
        address TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        logo_path TEXT NOT NULL DEFAULT '',
        primary_color INTEGER NOT NULL,
        secondary_color INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        school_id TEXT NOT NULL,
        gr_number TEXT NOT NULL,
        student_name TEXT NOT NULL,
        father_name TEXT NOT NULL,
        class_name TEXT NOT NULL,
        monthly_fee INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        UNIQUE (school_id, gr_number)
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        school_id TEXT NOT NULL,
        action TEXT NOT NULL,
        record_type TEXT NOT NULL,
        record_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> saveSchoolSettings(Map<String, Object?> settings) async {
    final db = await database;

    await db.insert(
      'school_settings',
      settings,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> loadSchoolSettings(String schoolId) async {
    final db = await database;

    final rows = await db.query(
      'school_settings',
      where: 'school_id = ?',
      whereArgs: [schoolId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
