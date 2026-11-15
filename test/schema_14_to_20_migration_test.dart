import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tlc_school_system/data/app_database.dart';

Future<void> _createSchema14Fixture(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''
    CREATE TABLE students (
      student_id TEXT PRIMARY KEY,
      admission_number TEXT NOT NULL UNIQUE,
      first_name TEXT NOT NULL,
      last_name TEXT NOT NULL,
      class_name TEXT NOT NULL,
      monthly_fee REAL NOT NULL DEFAULT 0,
      family_no TEXT NOT NULL DEFAULT '',
      roll_number TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE fee_charges (
      fee_id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL,
      month_key TEXT NOT NULL,
      amount_due REAL NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(student_id, month_key),
      FOREIGN KEY(student_id) REFERENCES students(student_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE fee_payments (
      payment_id TEXT PRIMARY KEY,
      fee_id TEXT NOT NULL,
      receipt_number TEXT NOT NULL UNIQUE,
      amount REAL NOT NULL,
      paid_at TEXT NOT NULL,
      payment_method TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '',
      received_by_user_id TEXT NOT NULL DEFAULT '',
      received_by_name TEXT NOT NULL DEFAULT '',
      received_by_role TEXT NOT NULL DEFAULT '',
      FOREIGN KEY(fee_id) REFERENCES fee_charges(fee_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE fee_payment_reversals (
      reversal_id TEXT PRIMARY KEY,
      payment_id TEXT NOT NULL UNIQUE,
      amount REAL NOT NULL,
      reason TEXT NOT NULL,
      reversed_at TEXT NOT NULL,
      reversed_by_user_id TEXT NOT NULL,
      reversed_by_name TEXT NOT NULL,
      FOREIGN KEY(payment_id) REFERENCES fee_payments(payment_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE user_accounts (
      account_id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL,
      username TEXT NOT NULL COLLATE NOCASE UNIQUE,
      password_salt TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL,
      permissions TEXT NOT NULL,
      assigned_class_sections TEXT NOT NULL DEFAULT '[]',
      linked_student_ids TEXT NOT NULL DEFAULT '[]',
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE exams (
      exam_id TEXT PRIMARY KEY,
      exam_name TEXT NOT NULL,
      class_name TEXT NOT NULL,
      section_name TEXT NOT NULL DEFAULT '',
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      academic_year TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE exam_subjects (
      subject_id TEXT PRIMARY KEY,
      exam_id TEXT NOT NULL,
      subject_name TEXT NOT NULL,
      exam_date TEXT NOT NULL,
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      total_marks REAL NOT NULL,
      room TEXT NOT NULL DEFAULT '',
      FOREIGN KEY(exam_id) REFERENCES exams(exam_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE exam_results (
      result_id TEXT PRIMARY KEY,
      subject_id TEXT NOT NULL,
      student_id TEXT NOT NULL,
      marks_obtained REAL NOT NULL,
      remarks TEXT NOT NULL DEFAULT '',
      UNIQUE(subject_id, student_id),
      FOREIGN KEY(subject_id) REFERENCES exam_subjects(subject_id),
      FOREIGN KEY(student_id) REFERENCES students(student_id)
    )
  ''');

  await db.insert('students', {
    'student_id': 'student-existing',
    'admission_number': 'GR-014',
    'first_name': 'Amina',
    'last_name': 'Khan',
    'class_name': 'Class 8',
    'monthly_fee': 2500,
    'family_no': 'FAM-01',
    'roll_number': '08',
    'created_at': '2025-04-01T08:00:00.000',
  });
  await db.insert('fee_charges', {
    'fee_id': 'fee-existing',
    'student_id': 'student-existing',
    'month_key': '2025-04',
    'amount_due': 2500,
    'created_at': '2025-04-01T08:00:00.000',
  });
  await db.insert('fee_payments', {
    'payment_id': 'payment-existing',
    'fee_id': 'fee-existing',
    'receipt_number': 'TLC-REC-014',
    'amount': 1000,
    'paid_at': '2025-04-05T10:30:00.000',
    'payment_method': 'Cash',
    'notes': 'Existing receipt before upgrade',
    'received_by_user_id': 'admin-1',
    'received_by_name': 'Administrator',
    'received_by_role': 'Admin',
  });
  await db.insert('fee_payment_reversals', {
    'reversal_id': 'reversal-existing',
    'payment_id': 'payment-existing',
    'amount': 1000,
    'reason': 'Existing correction record',
    'reversed_at': '2025-04-06T10:30:00.000',
    'reversed_by_user_id': 'admin-1',
    'reversed_by_name': 'Administrator',
  });
  await db.insert('user_accounts', {
    'account_id': 'parent-1',
    'full_name': 'Parent Khan',
    'username': 'parent.khan',
    'password_salt': 'fixture-salt',
    'password_hash': 'fixture-hash',
    'role': 'Parent / Guardian',
    'permissions': '["Dashboard"]',
    'created_at': '2025-04-01T08:00:00.000',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('schema 14 upgrades to 20 without losing school or finance history', () async {
    final directory = await Directory.systemTemp.createTemp('tlc_schema_upgrade_');
    final databasePath = '${directory.path}${Platform.pathSeparator}tlc_school_system.db';
    Database? legacy;
    Database? upgraded;

    try {
      databaseFactory = databaseFactoryFfi;
      await databaseFactoryFfi.setDatabasesPath(directory.path);

      legacy = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 14,
          onCreate: (db, version) => _createSchema14Fixture(db),
        ),
      );
      await legacy.close();
      legacy = null;

      upgraded = await AppDatabase.instance.database;
      final version = (await upgraded.getVersion());
      expect(version, 20);

      final students = await upgraded.query(
        'students',
        where: 'student_id = ?',
        whereArgs: ['student-existing'],
      );
      expect(students, hasLength(1));
      expect(students.single['admission_number'], 'GR-014');
      expect(students.single['monthly_fee'], 2500);

      final charges = await upgraded.query(
        'fee_charges',
        where: 'fee_id = ?',
        whereArgs: ['fee-existing'],
      );
      expect(charges, hasLength(1));
      expect(charges.single['fees'], 2500);
      expect(charges.single['amount_due'], 2500);

      final receipts = await upgraded.query(
        'fee_payments',
        where: 'payment_id = ?',
        whereArgs: ['payment-existing'],
      );
      expect(receipts, hasLength(1));
      expect(receipts.single['receipt_number'], 'TLC-REC-014');
      expect(receipts.single['amount'], 1000);

      final reversals = await upgraded.query(
        'fee_payment_reversals',
        where: 'reversal_id = ?',
        whereArgs: ['reversal-existing'],
      );
      expect(reversals, hasLength(1));
      expect(reversals.single['reason'], 'Existing correction record');

      final allocations = await upgraded.query(
        'fee_payment_allocations',
        where: 'payment_id = ?',
        whereArgs: ['payment-existing'],
      );
      expect(allocations, hasLength(1));
      expect(allocations.single['fee_id'], 'fee-existing');
      expect(allocations.single['amount'], 1000);

      final parent = await upgraded.query(
        'user_accounts',
        where: 'account_id = ?',
        whereArgs: ['parent-1'],
      );
      expect(parent, hasLength(1));
      expect(
        parent.single['permissions'],
        contains('Results & Report Cards'),
      );

      final integrity = await upgraded.rawQuery('PRAGMA integrity_check');
      expect(integrity.single.values.single, 'ok');
      final foreignKeyErrors = await upgraded.rawQuery('PRAGMA foreign_key_check');
      expect(foreignKeyErrors, isEmpty);

      await expectLater(
        upgraded.update(
          'fee_payment_allocations',
          {'amount': 1},
          where: 'payment_id = ?',
          whereArgs: ['payment-existing'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await upgraded?.close();
      await legacy?.close();
      await AppDatabase.instance.close();
      await directory.delete(recursive: true);
    }
  });
}
