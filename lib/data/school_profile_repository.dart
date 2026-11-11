import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../school_profile.dart';
import 'app_database.dart';

class SchoolProfileRepository {
  Future<SchoolProfile?> load() async {
    final database = await AppDatabase.instance.database;
    final rows = await database.query('school_profiles', limit: 1);
    return rows.isEmpty ? null : SchoolProfile.fromDatabaseMap(rows.first);
  }

  Future<void> save(SchoolProfile profile) async {
    final database = await AppDatabase.instance.database;
    await database.insert(
      'school_profiles',
      profile.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
