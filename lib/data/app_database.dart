import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final databaseDirectory = await getDatabasesPath();
    debugPrint('TLC DATABASE DIRECTORY: $databaseDirectory');
    debugPrint(
      'TLC DATABASE FULL PATH: ${path.join(databaseDirectory, 'tlc_school_system.db')}',
    );

    _database = await openDatabase(
      path.join(databaseDirectory, 'tlc_school_system.db'),
      version: 14,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE school_profiles (
            school_id TEXT PRIMARY KEY, school_name TEXT NOT NULL,
            motto TEXT NOT NULL, developer_credit TEXT NOT NULL,
            academic_year TEXT NOT NULL, address TEXT NOT NULL,
            phone TEXT NOT NULL, logo_path TEXT NOT NULL,
            primary_color INTEGER NOT NULL, secondary_color INTEGER NOT NULL,
            bank_name TEXT NOT NULL DEFAULT 'Bank Al-Habib Ltd.',
            bank_account TEXT NOT NULL DEFAULT '1164-0981-003052-01-2'
          )
        ''');
        await database.execute('''
          CREATE TABLE students (
            student_id TEXT PRIMARY KEY, admission_number TEXT NOT NULL UNIQUE,
            roll_number TEXT NOT NULL DEFAULT '',
            first_name TEXT NOT NULL, last_name TEXT NOT NULL,
            class_name TEXT NOT NULL, section_name TEXT, guardian_name TEXT,
            guardian_phone TEXT, gender TEXT NOT NULL DEFAULT 'Unknown',
            religion TEXT NOT NULL DEFAULT '', date_of_birth TEXT,
            place_of_birth TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '',
            family_no TEXT NOT NULL DEFAULT '',
            date_of_admission TEXT, previous_institute TEXT NOT NULL DEFAULT '',
            admitted_class TEXT NOT NULL DEFAULT '', date_of_removal TEXT,
            class_at_removal TEXT NOT NULL DEFAULT '',
            cause_of_removal TEXT NOT NULL DEFAULT '', remarks TEXT NOT NULL DEFAULT '',
            monthly_fee REAL NOT NULL DEFAULT 0, created_at TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE staff (
            staff_id TEXT PRIMARY KEY, employee_number TEXT NOT NULL UNIQUE,
            full_name TEXT NOT NULL, role TEXT NOT NULL, phone TEXT,
            monthly_salary REAL NOT NULL DEFAULT 0,
            father_name TEXT NOT NULL DEFAULT '',
            gender TEXT NOT NULL DEFAULT '',
            academic_qualification TEXT NOT NULL DEFAULT '',
            professional_qualification TEXT NOT NULL DEFAULT '',
            appointment_date TEXT NOT NULL DEFAULT '',
            import_key TEXT UNIQUE,
            created_at TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE library_books (
            book_id TEXT PRIMARY KEY,
            class_name TEXT NOT NULL,
            subject TEXT NOT NULL,
            title TEXT NOT NULL,
            author TEXT NOT NULL DEFAULT '',
            publisher TEXT NOT NULL DEFAULT '',
            import_key TEXT UNIQUE,
            created_at TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE attendance (
            attendance_id TEXT PRIMARY KEY, student_id TEXT NOT NULL,
            attendance_date TEXT NOT NULL, status TEXT NOT NULL, notes TEXT,
            UNIQUE(student_id, attendance_date),
            FOREIGN KEY(student_id) REFERENCES students(student_id)
          )
        ''');
        await database.execute('''
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
        await _createOperationalTables(database);
        await _createScheduleTables(database);
        await _createComplaintsTable(database);
        await _createContentTables(database);
        await _createAuthSupportTables(database);
        await _createFeePaymentCorrectionTables(database);
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.update(
            'school_profiles',
            {
              'primary_color': const Color(0xFFC62828).toARGB32(),
              'secondary_color': const Color(0xFF8E1717).toARGB32(),
            },
            where: 'primary_color = ? AND secondary_color = ?',
            whereArgs: [
              const Color(0xFF1565C0).toARGB32(),
              const Color(0xFF0D47A1).toARGB32(),
            ],
          );
        }
        if (oldVersion < 3) {
          await database.execute(
            "ALTER TABLE students ADD COLUMN gender TEXT NOT NULL DEFAULT 'Unknown'",
          );
          await database.execute(
            "ALTER TABLE students ADD COLUMN religion TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            'ALTER TABLE students ADD COLUMN date_of_birth TEXT',
          );
          await database.execute(
            "ALTER TABLE students ADD COLUMN place_of_birth TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE students ADD COLUMN address TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            'ALTER TABLE students ADD COLUMN date_of_admission TEXT',
          );
          await database.execute(
            "ALTER TABLE students ADD COLUMN previous_institute TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE students ADD COLUMN admitted_class TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            'ALTER TABLE students ADD COLUMN date_of_removal TEXT',
          );
          await database.execute(
            "ALTER TABLE students ADD COLUMN class_at_removal TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE students ADD COLUMN cause_of_removal TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE students ADD COLUMN remarks TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            'ALTER TABLE students ADD COLUMN monthly_fee REAL NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 4) {
          await database.execute('''
            CREATE TABLE user_accounts (
              account_id TEXT PRIMARY KEY,
              full_name TEXT NOT NULL,
              username TEXT NOT NULL COLLATE NOCASE UNIQUE,
              password_salt TEXT NOT NULL,
              password_hash TEXT NOT NULL,
              role TEXT NOT NULL,
              permissions TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 5) {
          await database.execute(
            'ALTER TABLE staff ADD COLUMN monthly_salary REAL NOT NULL DEFAULT 0',
          );
          await _createOperationalTables(database);
        }
        if (oldVersion < 6) {
          await _createScheduleTables(database);
        }
        if (oldVersion < 7) {
          await database.execute(
            "ALTER TABLE user_accounts ADD COLUMN assigned_class_sections TEXT NOT NULL DEFAULT '[]'",
          );
          await database.execute(
            "ALTER TABLE user_accounts ADD COLUMN linked_student_ids TEXT NOT NULL DEFAULT '[]'",
          );
        }
        if (oldVersion < 8) {
          await database.execute(
            "ALTER TABLE school_profiles ADD COLUMN bank_name TEXT NOT NULL DEFAULT 'Bank Al-Habib Ltd.'",
          );
          await database.execute(
            "ALTER TABLE school_profiles ADD COLUMN bank_account TEXT NOT NULL DEFAULT '1164-0981-003052-01-2'",
          );
          await database.execute(
            "ALTER TABLE staff ADD COLUMN father_name TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE staff ADD COLUMN gender TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE staff ADD COLUMN academic_qualification TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE staff ADD COLUMN professional_qualification TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE staff ADD COLUMN appointment_date TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            'ALTER TABLE staff ADD COLUMN import_key TEXT',
          );
          await database.execute(
            'CREATE UNIQUE INDEX staff_import_key_index ON staff(import_key)',
          );
          await database.execute('''
            CREATE TABLE library_books (
              book_id TEXT PRIMARY KEY,
              class_name TEXT NOT NULL,
              subject TEXT NOT NULL,
              title TEXT NOT NULL,
              author TEXT NOT NULL DEFAULT '',
              publisher TEXT NOT NULL DEFAULT '',
              import_key TEXT UNIQUE,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 9) {
          await _createComplaintsTable(database);
        }
        if (oldVersion < 10) {
          if (oldVersion >= 9) {
            await database.execute(
              "ALTER TABLE complaints ADD COLUMN owner_user_id TEXT NOT NULL DEFAULT ''",
            );
          }
          await database.update(
            'user_accounts',
            {'permissions': '["Dashboard","Complaints","Notices"]'},
            where: 'role = ? AND permissions = ?',
            whereArgs: ['Parent / Guardian', '["Dashboard"]'],
          );
          await _createContentTables(database);
        }
        if (oldVersion < 11) {
          await _createAuthSupportTables(database);
        }
        if (oldVersion < 12) {
          await database.execute(
            "ALTER TABLE fee_payments ADD COLUMN received_by_user_id TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE fee_payments ADD COLUMN received_by_name TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE fee_payments ADD COLUMN received_by_role TEXT NOT NULL DEFAULT ''",
          );
          await _createFeePaymentCorrectionTables(database);
        }
        if (oldVersion < 13) {
          await database.execute(
            "ALTER TABLE students ADD COLUMN family_no TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 14) {
          await database.execute(
            "ALTER TABLE students ADD COLUMN roll_number TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );
    return _database!;
  }

  Future<void> close() async {
    final db = _database;

    if (db == null) return;

    _database = null;
    await db.close();
  }

  static Future<void> _createOperationalTables(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE fee_charges (
        fee_id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        month_key TEXT NOT NULL,
        amount_due REAL NOT NULL CHECK (amount_due >= 0),
        created_at TEXT NOT NULL,
        UNIQUE(student_id, month_key),
        FOREIGN KEY(student_id) REFERENCES students(student_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE fee_payments (
        payment_id TEXT PRIMARY KEY,
        fee_id TEXT NOT NULL,
        receipt_number TEXT NOT NULL UNIQUE,
        amount REAL NOT NULL CHECK (amount > 0),
        paid_at TEXT NOT NULL,
        payment_method TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        received_by_user_id TEXT NOT NULL DEFAULT '',
        received_by_name TEXT NOT NULL DEFAULT '',
        received_by_role TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(fee_id) REFERENCES fee_charges(fee_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX fee_charges_month_index ON fee_charges(month_key)
    ''');
    await database.execute('''
      CREATE TABLE inventory_items (
        item_id TEXT PRIMARY KEY,
        item_name TEXT NOT NULL,
        category TEXT NOT NULL,
        unit TEXT NOT NULL,
        reorder_level REAL NOT NULL DEFAULT 0 CHECK (reorder_level >= 0),
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE inventory_movements (
        movement_id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL,
        direction TEXT NOT NULL CHECK (direction IN ('in', 'out')),
        quantity REAL NOT NULL CHECK (quantity > 0),
        unit_cost REAL NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
        supplier TEXT NOT NULL DEFAULT '',
        reference TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        moved_at TEXT NOT NULL,
        FOREIGN KEY(item_id) REFERENCES inventory_items(item_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE staff_salary_records (
        salary_id TEXT PRIMARY KEY,
        staff_id TEXT NOT NULL,
        month_key TEXT NOT NULL,
        base_salary REAL NOT NULL CHECK (base_salary >= 0),
        allowances REAL NOT NULL DEFAULT 0 CHECK (allowances >= 0),
        deductions REAL NOT NULL DEFAULT 0 CHECK (deductions >= 0),
        status TEXT NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'paid')),
        paid_at TEXT,
        payment_method TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        UNIQUE(staff_id, month_key),
        FOREIGN KEY(staff_id) REFERENCES staff(staff_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX staff_salary_month_index ON staff_salary_records(month_key)
    ''');
  }

  static Future<void> _createFeePaymentCorrectionTables(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS fee_payment_reversals (
        reversal_id TEXT PRIMARY KEY,
        payment_id TEXT NOT NULL UNIQUE,
        amount REAL NOT NULL CHECK (amount > 0),
        reason TEXT NOT NULL,
        reversed_at TEXT NOT NULL,
        reversed_by_user_id TEXT NOT NULL,
        reversed_by_name TEXT NOT NULL,
        FOREIGN KEY(payment_id) REFERENCES fee_payments(payment_id)
      )
    ''');
    await database.execute('''
      CREATE TRIGGER IF NOT EXISTS fee_payment_reversals_validate
      BEFORE INSERT ON fee_payment_reversals
      WHEN TRIM(NEW.reason) = ''
        OR NEW.amount != (
          SELECT amount FROM fee_payments
          WHERE payment_id = NEW.payment_id
        )
      BEGIN
        SELECT RAISE(ABORT, 'A reversal must match its receipt and include a reason.');
      END
    ''');
    await database.execute('''
      CREATE TRIGGER IF NOT EXISTS fee_payments_prevent_update
      BEFORE UPDATE ON fee_payments
      BEGIN
        SELECT RAISE(ABORT, 'Fee receipts are permanent and cannot be edited.');
      END
    ''');
    await database.execute('''
      CREATE TRIGGER IF NOT EXISTS fee_payments_prevent_delete
      BEFORE DELETE ON fee_payments
      BEGIN
        SELECT RAISE(ABORT, 'Fee receipts are permanent and cannot be deleted.');
      END
    ''');
    await database.execute('''
      CREATE TRIGGER IF NOT EXISTS fee_payment_reversals_prevent_update
      BEFORE UPDATE ON fee_payment_reversals
      BEGIN
        SELECT RAISE(ABORT, 'Fee reversals are permanent and cannot be edited.');
      END
    ''');
    await database.execute('''
      CREATE TRIGGER IF NOT EXISTS fee_payment_reversals_prevent_delete
      BEFORE DELETE ON fee_payment_reversals
      BEGIN
        SELECT RAISE(ABORT, 'Fee reversals are permanent and cannot be deleted.');
      END
    ''');
  }

  static Future<void> _createScheduleTables(DatabaseExecutor database) async {
    await database.execute('''
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
    await database.execute('''
      CREATE TABLE exam_subjects (
        subject_id TEXT PRIMARY KEY,
        exam_id TEXT NOT NULL,
        subject_name TEXT NOT NULL,
        exam_date TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        total_marks REAL NOT NULL CHECK (total_marks > 0),
        room TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(exam_id) REFERENCES exams(exam_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE exam_results (
        result_id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL,
        student_id TEXT NOT NULL,
        marks_obtained REAL NOT NULL CHECK (marks_obtained >= 0),
        remarks TEXT NOT NULL DEFAULT '',
        UNIQUE(subject_id, student_id),
        FOREIGN KEY(subject_id) REFERENCES exam_subjects(subject_id) ON DELETE CASCADE,
        FOREIGN KEY(student_id) REFERENCES students(student_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE timetable_entries (
        entry_id TEXT PRIMARY KEY,
        class_name TEXT NOT NULL,
        section_name TEXT NOT NULL DEFAULT '',
        weekday INTEGER NOT NULL CHECK (weekday BETWEEN 1 AND 7),
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        subject TEXT NOT NULL,
        teacher_name TEXT NOT NULL DEFAULT '',
        room TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createComplaintsTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE complaints (
        complaint_id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL DEFAULT '',
        reporter_name TEXT NOT NULL,
        reporter_role TEXT NOT NULL,
        contact TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL,
        subject TEXT NOT NULL,
        description TEXT NOT NULL,
        priority TEXT NOT NULL CHECK (priority IN ('Low', 'Medium', 'High')),
        status TEXT NOT NULL DEFAULT 'Open'
          CHECK (status IN ('Open', 'In Progress', 'Resolved', 'Closed')),
        resolution_notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX complaints_created_index ON complaints(created_at)',
    );
  }

  static Future<void> _createContentTables(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE class_subjects (
        class_subject_id TEXT PRIMARY KEY,
        class_name TEXT NOT NULL,
        subject_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(class_name, subject_name)
      )
    ''');
    await database.execute('''
      CREATE TABLE school_notices (
        notice_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        audience TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE ece_worksheets (
        worksheet_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        class_name TEXT NOT NULL,
        subject TEXT NOT NULL,
        instructions TEXT NOT NULL DEFAULT '',
        activity_text TEXT NOT NULL DEFAULT '',
        file_name TEXT NOT NULL DEFAULT '',
        file_bytes BLOB,
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createAuthSupportTables(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE account_requests (
        request_id TEXT PRIMARY KEY,
        full_name TEXT NOT NULL,
        username TEXT NOT NULL COLLATE NOCASE,
        contact TEXT NOT NULL DEFAULT '',
        requested_role TEXT NOT NULL,
        password_salt TEXT,
        password_hash TEXT,
        status TEXT NOT NULL DEFAULT 'Pending'
          CHECK (status IN ('Pending', 'Approved', 'Rejected')),
        created_at TEXT NOT NULL,
        reviewed_at TEXT,
        reviewer_user_id TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE auth_preferences (
        preference_key TEXT PRIMARY KEY,
        preference_value TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE admin_audit_logs (
        log_id TEXT PRIMARY KEY,
        actor_user_id TEXT NOT NULL,
        actor_name TEXT NOT NULL,
        action TEXT NOT NULL,
        target TEXT NOT NULL DEFAULT '',
        details TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX account_requests_status_index ON account_requests(status, created_at)',
    );
    await database.execute(
      'CREATE INDEX admin_audit_created_index ON admin_audit_logs(created_at)',
    );
  }
}
