import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';

class DatabaseBackupService {
  static const int requiredDatabaseVersion = AppDatabase.schemaVersion;

  static const List<String> requiredTables = [
    'school_profiles',
    'students',
    'staff',
    'library_books',
    'attendance',
    'user_accounts',
    'fee_charges',
    'fee_payments',
    'fee_payment_allocations',
    'inventory_items',
    'inventory_movements',
    'staff_salary_records',
    'school_account_settings',
    'fee_payment_reversals',
    'exams',
    'exam_subjects',
    'exam_results',
    'exam_subject_teachers',
    'exam_class_teachers',
    'exam_publications',
    'timetable_entries',
    'complaints',
    'class_subjects',
    'school_notices',
    'ece_worksheets',
    'account_requests',
    'auth_preferences',
    'admin_audit_logs',
  ];

  bool _supportsVacuumInto(String version) {
    final parts = version.split('.').map(int.tryParse).toList();

    if (parts.length < 2 || parts[0] == null || parts[1] == null) {
      return false;
    }

    final major = parts[0]!;
    final minor = parts[1]!;

    return major > 3 || (major == 3 && minor >= 27);
  }

  Future<List<Map<String, Object?>>> _getApplicationTables(
    DatabaseExecutor database,
  ) async {
    return database.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' "
      "ORDER BY name",
    );
  }

  Future<void> _validateIntegrity(
    DatabaseExecutor database,
    String description,
  ) async {
    final rows = await database.rawQuery('PRAGMA integrity_check');

    if (rows.length != 1 ||
        rows.first.values.first.toString().toLowerCase() != 'ok') {
      throw StateError(
        '$description failed SQLite integrity validation: $rows',
      );
    }

    final foreignKeyErrors = await database.rawQuery(
      'PRAGMA foreign_key_check',
    );

    if (foreignKeyErrors.isNotEmpty) {
      throw StateError(
        '$description contains foreign-key violations: '
        '${foreignKeyErrors.length}',
      );
    }
  }

  Future<void> _validateDatabaseVersion(
    Database database,
    String description,
  ) async {
    final version = await database.getVersion();

    if (version != requiredDatabaseVersion) {
      throw StateError(
        '$description has database version $version. '
        'Required version is $requiredDatabaseVersion. '
        'No database version changes are permitted.',
      );
    }
  }

  Future<void> _validateRequiredTables(
    DatabaseExecutor database,
    String description,
  ) async {
    final rows = await _getApplicationTables(database);

    final existingTables = rows.map((row) => row['name'].toString()).toSet();

    final missingTables = requiredTables
        .where((table) => !existingTables.contains(table))
        .toList();

    if (missingTables.isNotEmpty) {
      throw StateError(
        '$description is missing required tables: '
        '${missingTables.join(', ')}',
      );
    }
  }

  Future<String> _getSchemaSignature(DatabaseExecutor database) async {
    final schema = await database.rawQuery(
      "SELECT type, name, tbl_name, sql "
      "FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_%' "
      "AND type IN ('table', 'index', 'trigger', 'view') "
      "ORDER BY type, name, tbl_name",
    );

    return jsonEncode(schema);
  }

  String _quoteIdentifier(String identifier) {
    return '"${identifier.replaceAll('"', '""')}"';
  }

  Future<void> _validateRecordCounts(Database source, Database backup) async {
    final sourceTables = await _getApplicationTables(source);

    final backupTables = await _getApplicationTables(backup);

    final sourceNames = sourceTables
        .map((row) => row['name'].toString())
        .toSet();

    final backupNames = backupTables
        .map((row) => row['name'].toString())
        .toSet();

    if (sourceNames.length != backupNames.length ||
        !sourceNames.containsAll(backupNames) ||
        !backupNames.containsAll(sourceNames)) {
      throw StateError(
        'The backup table list does not match the original database.',
      );
    }

    for (final table in sourceNames) {
      final quotedTable = _quoteIdentifier(table);

      final sourceRows = await source.rawQuery(
        'SELECT COUNT(*) AS total FROM $quotedTable',
      );

      final backupRows = await backup.rawQuery(
        'SELECT COUNT(*) AS total FROM $quotedTable',
      );

      final sourceCount = int.parse(sourceRows.first['total'].toString());

      final backupCount = int.parse(backupRows.first['total'].toString());

      if (sourceCount != backupCount) {
        throw StateError(
          'Record count mismatch in table "$table". '
          'Original: $sourceCount, Backup: $backupCount.',
        );
      }
    }
  }

  Future<void> validateBackupAgainstDatabase(
    Database source,
    Database backup,
  ) async {
    await _validateDatabaseVersion(source, 'Original database');

    await _validateDatabaseVersion(backup, 'Backup database');

    await _validateRequiredTables(source, 'Original database');

    await _validateRequiredTables(backup, 'Backup database');

    await _validateIntegrity(source, 'Original database');

    await _validateIntegrity(backup, 'Backup database');

    final sourceSchema = await _getSchemaSignature(source);

    final backupSchema = await _getSchemaSignature(backup);

    if (sourceSchema != backupSchema) {
      throw StateError('Backup schema does not match the original database.');
    }

    await _validateRecordCounts(source, backup);
  }

  Future<String?> createBackup() async {
    final database = await AppDatabase.instance.database;

    final versionRows = await database.rawQuery(
      'SELECT sqlite_version() AS version',
    );

    final sqliteVersion = versionRows.first['version']?.toString() ?? '';

    if (!_supportsVacuumInto(sqliteVersion)) {
      throw UnsupportedError(
        'SQLite $sqliteVersion does not support VACUUM INTO. '
        'SQLite 3.27.0 or newer is required.',
      );
    }

    final databaseVersion = await database.getVersion();

    if (databaseVersion != requiredDatabaseVersion) {
      throw StateError(
        'Database version mismatch. '
        'Expected $requiredDatabaseVersion but found $databaseVersion. '
        'Backup cancelled.',
      );
    }

    final temporaryDirectory = await getTemporaryDirectory();

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');

    final snapshot = File(
      p.join(temporaryDirectory.path, 'TLC_Backup_$timestamp.db'),
    );

    try {
      if (await snapshot.exists()) {
        await snapshot.delete();
      }

      await database.execute('VACUUM INTO ?', [snapshot.path]);

      if (!await snapshot.exists() || await snapshot.length() == 0) {
        throw StateError('The backup file was not created correctly.');
      }

      final backupDatabase = await openDatabase(snapshot.path, readOnly: true);

      try {
        await validateBackupAgainstDatabase(database, backupDatabase);
      } finally {
        await backupDatabase.close();
      }

      final bytes = await snapshot.readAsBytes();

      if (bytes.isEmpty) {
        throw StateError('The verified backup file is unexpectedly empty.');
      }

      final location = await FilePicker.saveFile(
        dialogTitle: 'Save TLC School System Database Backup',
        fileName: 'TLC_School_System_Backup_$timestamp.db',
        mimeType: 'application/x-sqlite3',
        bytes: bytes,
      );

      return location?.toString();
    } finally {
      if (await snapshot.exists()) {
        await snapshot.delete();
      }
    }
  }
  Future<void> _validateRestoreCandidate(
    Database currentDatabase,
    Database candidate,
  ) async {
    await _validateDatabaseVersion(candidate, 'Selected backup');
    await _validateRequiredTables(candidate, 'Selected backup');
    await _validateIntegrity(candidate, 'Selected backup');

    final currentSchema = await _getSchemaSignature(currentDatabase);
    final candidateSchema = await _getSchemaSignature(candidate);
    if (currentSchema != candidateSchema) {
      throw StateError(
        'The selected backup does not match this app database schema. '
        'Restore was cancelled; update the app or select a compatible backup.',
      );
    }
  }

  Future<String> restoreBackup(String backupPath) async {
    final sourceFile = File(backupPath);
    if (!await sourceFile.exists() || await sourceFile.length() == 0) {
      throw StateError('The selected backup file is missing or empty.');
    }

    final databaseDirectory = await getDatabasesPath();
    final databasePath = p.join(databaseDirectory, 'tlc_school_system.db');
    final absoluteBackupPath = p.normalize(p.absolute(sourceFile.path));
    final absoluteDatabasePath = p.normalize(p.absolute(databasePath));
    if (absoluteBackupPath.toLowerCase() == absoluteDatabasePath.toLowerCase()) {
      throw StateError('Select a backup file, not the currently open database.');
    }

    final currentDatabase = await AppDatabase.instance.database;
    final candidate = await openDatabase(sourceFile.path, readOnly: true);
    try {
      await _validateRestoreCandidate(currentDatabase, candidate);
    } finally {
      await candidate.close();
    }

    final versionRows = await currentDatabase.rawQuery(
      'SELECT sqlite_version() AS version',
    );
    final sqliteVersion = versionRows.first['version']?.toString() ?? '';
    if (!_supportsVacuumInto(sqliteVersion)) {
      throw UnsupportedError(
        'SQLite $sqliteVersion cannot create the required safety backup. '
        'Restore was cancelled.',
      );
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final safetyPath = p.join(
      databaseDirectory,
      'TLC_PreRestore_Safety_$timestamp.db',
    );
    final stagingPath = p.join(
      databaseDirectory,
      'tlc_school_system.restore.tmp',
    );
    final rollbackPath = p.join(
      databaseDirectory,
      'tlc_school_system.rollback.db',
    );

    final safetyFile = File(safetyPath);
    final stagingFile = File(stagingPath);
    final rollbackFile = File(rollbackPath);
    final databaseFile = File(databasePath);
    var originalMoved = false;
    var replacementInstalled = false;

    try {
      if (await stagingFile.exists()) await stagingFile.delete();
      if (await rollbackFile.exists()) {
        throw StateError(
          'A previous restore recovery file exists at $rollbackPath. '
          'Do not continue until it has been checked.',
        );
      }

      await currentDatabase.execute('PRAGMA wal_checkpoint(FULL)');
      await currentDatabase.execute('VACUUM INTO ?', [safetyPath]);
      if (!await safetyFile.exists() || await safetyFile.length() == 0) {
        throw StateError('Could not create the pre-restore safety backup.');
      }

      await AppDatabase.instance.close();

      await sourceFile.copy(stagingPath);
      final stagedDatabase = await openDatabase(stagingPath, readOnly: true);
      try {
        final safetyDatabase = await openDatabase(safetyPath, readOnly: true);
        try {
          await validateBackupAgainstDatabase(safetyDatabase, stagedDatabase);
        } finally {
          await safetyDatabase.close();
        }
      } finally {
        await stagedDatabase.close();
      }

      for (final suffix in ['-wal', '-shm']) {
        final sidecar = File('$databasePath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }

      await databaseFile.rename(rollbackPath);
      originalMoved = true;
      await stagingFile.rename(databasePath);
      replacementInstalled = true;

      final restoredDatabase = await AppDatabase.instance.database;
      await _validateDatabaseVersion(restoredDatabase, 'Restored database');
      await _validateRequiredTables(restoredDatabase, 'Restored database');
      await _validateIntegrity(restoredDatabase, 'Restored database');

      await rollbackFile.delete();
      return safetyPath;
    } catch (error) {
      if (replacementInstalled) {
        await AppDatabase.instance.close();
      }
      if (originalMoved && await rollbackFile.exists()) {
        if (await databaseFile.exists()) await databaseFile.delete();
        await rollbackFile.rename(databasePath);
        await AppDatabase.instance.database;
      }
      rethrow;
    } finally {
      if (await stagingFile.exists()) await stagingFile.delete();
    }
  }

}
