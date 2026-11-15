import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tlc_school_system/auth/app_user.dart';
import 'package:tlc_school_system/data/app_database.dart';
import 'package:tlc_school_system/data/school_finance_repository.dart';

Future<Database> _createFinanceDatabase() => databaseFactoryFfi.openDatabase(
  inMemoryDatabasePath,
  options: OpenDatabaseOptions(
    version: 1,
    onCreate: (database, version) async {
      await database.execute('''
        CREATE TABLE school_account_settings (
          setting_id INTEGER PRIMARY KEY,
          opening_balance REAL NOT NULL,
          opening_balance_date TEXT NOT NULL
        )
      ''');
      await database.execute('''
        CREATE TABLE staff (
          staff_id TEXT PRIMARY KEY,
          monthly_salary REAL NOT NULL
        )
      ''');
      await database.execute('''
        CREATE TABLE staff_salary_records (
          salary_id TEXT PRIMARY KEY,
          staff_id TEXT NOT NULL,
          month_key TEXT NOT NULL,
          base_salary REAL NOT NULL,
          allowances REAL NOT NULL,
          deductions REAL NOT NULL,
          status TEXT NOT NULL,
          paid_at TEXT,
          payment_method TEXT NOT NULL,
          notes TEXT NOT NULL,
          created_at TEXT NOT NULL,
          UNIQUE(staff_id, month_key)
        )
      ''');
      await database.execute('''
        CREATE TABLE fee_payments (
          payment_id TEXT PRIMARY KEY,
          amount REAL NOT NULL,
          paid_at TEXT NOT NULL
        )
      ''');
      await database.execute('''
        CREATE TABLE fee_payment_reversals (
          reversal_id TEXT PRIMARY KEY,
          amount REAL NOT NULL,
          reversed_at TEXT NOT NULL
        )
      ''');
      await database.insert('school_account_settings', {
        'setting_id': 1,
        'opening_balance': 1000,
        'opening_balance_date': '2020-04-01',
      });
      await database.insert('staff', {
        'staff_id': 'teacher-1',
        'monthly_salary': 1000,
      });
    },
  ),
);

void main() {
  setUpAll(sqfliteFfiInit);

  const administrator = AppUser(
    id: 'admin-1',
    fullName: 'School Administrator',
    username: 'admin',
    role: AppRoles.administrator,
    permissions: AppRoles.modules,
    isActive: true,
  );
  const teacher = AppUser(
    id: 'teacher-1',
    fullName: 'Teacher',
    username: 'teacher',
    role: AppRoles.teacher,
    permissions: [],
    isActive: true,
  );

  test('monthly balance includes receipts, reversals, and paid salaries', () async {
    final database = await _createFinanceDatabase();
    addTearDown(database.close);
    final repository = SchoolFinanceRepository(
      database: AppDatabase.forTesting(database),
    );
    await database.insert('fee_payments', {
      'payment_id': 'receipt-april',
      'amount': 1200,
      'paid_at': '2020-04-12T10:00:00.000',
    });
    await database.insert('fee_payments', {
      'payment_id': 'receipt-may',
      'amount': 500,
      'paid_at': '2020-05-04T10:00:00.000',
    });
    await database.insert('fee_payment_reversals', {
      'reversal_id': 'reversal-may',
      'amount': 100,
      'reversed_at': '2020-05-05T10:00:00.000',
    });
    await repository.recordSalaryPayment(
      staffId: 'teacher-1',
      monthKey: '2020-05',
      deductions: 200,
      paymentMethod: 'Bank transfer',
      notes: '',
      actor: administrator,
      paidAt: DateTime(2020, 5, 6),
    );

    final summary = await repository.getAccountSummary(
      throughDate: DateTime(2020, 5, 31),
    );

    expect(summary.currentBalance, 1800);
    expect(summary.months, hasLength(2));
    expect(summary.months.first.feeReceipts, 1200);
    expect(summary.months.first.closingBalance, 2200);
    expect(summary.months.last.feeReversals, 100);
    expect(summary.months.last.salaryPayments, 800);
    expect(summary.months.last.closingBalance, 1800);
  });

  test('salary payment is recorded once and restricted to full-access roles', () async {
    final database = await _createFinanceDatabase();
    addTearDown(database.close);
    final repository = SchoolFinanceRepository(
      database: AppDatabase.forTesting(database),
    );
    final payment = await repository.recordSalaryPayment(
      staffId: 'teacher-1',
      monthKey: '2020-04',
      deductions: 0,
      paymentMethod: 'Cash',
      notes: '',
      actor: administrator,
      paidAt: DateTime(2020, 4, 30),
    );

    expect(payment.netSalary, 1000);
    expect(await repository.getSalaryPayments('2020-04'), hasLength(1));
    await expectLater(
      repository.recordSalaryPayment(
        staffId: 'teacher-1',
        monthKey: '2020-04',
        deductions: 0,
        paymentMethod: 'Cash',
        notes: '',
        actor: administrator,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.setOpeningBalance(
        amount: 0,
        date: DateTime(2020, 4, 1),
        actor: teacher,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
