import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/auth/app_user.dart';
import 'package:tlc_school_system/data/app_database.dart';
import 'package:tlc_school_system/data/fee_repository.dart';

Future<Database> _createFeeDatabase() => databaseFactoryFfi.openDatabase(
  inMemoryDatabasePath,
  options: OpenDatabaseOptions(
    version: 1,
    onCreate: (database, version) async {
      await database.execute('''
        CREATE TABLE students (
          student_id TEXT PRIMARY KEY,
          admission_number TEXT NOT NULL,
          first_name TEXT NOT NULL,
          last_name TEXT NOT NULL,
          class_name TEXT NOT NULL,
          guardian_name TEXT,
          family_no TEXT NOT NULL DEFAULT ''
        )
      ''');
      await database.execute('''
        CREATE TABLE fee_charges (
          fee_id TEXT PRIMARY KEY,
          student_id TEXT NOT NULL,
          month_key TEXT NOT NULL,
          amount_due REAL NOT NULL,
          fees REAL NOT NULL DEFAULT 0,
          annual REAL NOT NULL DEFAULT 0,
          admission REAL NOT NULL DEFAULT 0,
          lab REAL NOT NULL DEFAULT 0,
          copies REAL NOT NULL DEFAULT 0,
          stationery REAL NOT NULL DEFAULT 0,
          extras REAL NOT NULL DEFAULT 0,
          lpc REAL NOT NULL DEFAULT 0,
          remarks TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL
        )
      ''');
      await database.execute('''
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
          received_by_role TEXT NOT NULL DEFAULT ''
        )
      ''');
      await database.execute('''
        CREATE TABLE fee_payment_allocations (
          allocation_id TEXT PRIMARY KEY,
          payment_id TEXT NOT NULL,
          fee_id TEXT NOT NULL,
          amount REAL NOT NULL
        )
      ''');
      await database.execute('''
        CREATE TABLE fee_payment_reversals (
          reversal_id TEXT PRIMARY KEY,
          payment_id TEXT NOT NULL UNIQUE,
          amount REAL NOT NULL,
          reason TEXT NOT NULL,
          reversed_at TEXT NOT NULL,
          reversed_by_user_id TEXT NOT NULL,
          reversed_by_name TEXT NOT NULL
        )
      ''');
      await database.execute('''
        CREATE TABLE admin_audit_logs (
          log_id TEXT PRIMARY KEY,
          actor_user_id TEXT NOT NULL,
          actor_name TEXT NOT NULL,
          action TEXT NOT NULL,
          target TEXT NOT NULL,
          details TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    },
  ),
);

void main() {
  setUpAll(sqfliteFfiInit);

  const frontDeskOfficer = AppUser(
    id: 'fdo-1',
    fullName: 'Front Desk Officer',
    username: 'fdo',
    role: AppRoles.frontDeskOfficer,
    permissions: ['Fees & Vouchers'],
    isActive: true,
  );
  const administrator = AppUser(
    id: 'admin-1',
    fullName: 'School Administrator',
    username: 'admin',
    role: AppRoles.administrator,
    permissions: AppRoles.modules,
    isActive: true,
  );

  test('only an Administrator can reverse a fee payment', () async {
    await expectLater(
      FeeRepository().reversePayment(
        paymentId: 'payment-1',
        actor: frontDeskOfficer,
        reason: 'Testing',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('a fee payment reversal requires a reason', () async {
    await expectLater(
      FeeRepository().reversePayment(
        paymentId: 'payment-1',
        actor: administrator,
        reason: '  ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test(
    'allocates oldest month first and restores all months on reversal',
    () async {
      final database = await _createFeeDatabase();
      addTearDown(database.close);
      final repository = FeeRepository(
        database: AppDatabase.forTesting(database),
      );
      final createdAt = DateTime(2026, 3).toIso8601String();
      await database.insert('students', {
        'student_id': 'student-1',
        'admission_number': 'GR-001',
        'first_name': 'Amina',
        'last_name': 'Khan',
        'class_name': 'Class 3',
        'guardian_name': 'Parent Khan',
      });
      for (final charge in [
        ('fee-jan', '2026-01', 100.0),
        ('fee-feb', '2026-02', 200.0),
        ('fee-mar', '2026-03', 300.0),
      ]) {
        await database.insert('fee_charges', {
          'fee_id': charge.$1,
          'student_id': 'student-1',
          'month_key': charge.$2,
          'amount_due': charge.$3,
          'fees': charge.$3,
          'created_at': createdAt,
        });
      }
      const marchCharge = FeeCharge(
        id: 'fee-mar',
        studentId: 'student-1',
        admissionNumber: 'GR-001',
        studentName: 'Amina Khan',
        className: 'Class 3',
        monthKey: '2026-03',
        amountDue: 300,
        amountPaid: 0,
        fees: 300,
      );

      final firstReceipt = await repository.recordPayment(
        charge: marchCharge,
        amount: 250,
        paymentMethod: 'Cash',
        notes: '',
        receivedBy: frontDeskOfficer,
      );
      expect(
        firstReceipt.allocations.map((allocation) => allocation.monthKey),
        ['2026-01', '2026-02'],
      );
      expect(firstReceipt.allocations.map((allocation) => allocation.amount), [
        100,
        150,
      ]);

      final afterFirstPayment = (await repository.getMonthlyCharges('2026-03'))
          .single;
      expect(afterFirstPayment.arrears.map((charge) => charge.monthKey), [
        '2026-02',
      ]);
      expect(afterFirstPayment.arrearsBalance, 50);
      expect(afterFirstPayment.totalOutstanding, 350);

      final secondReceipt = await repository.recordPayment(
        charge: marchCharge,
        amount: 150,
        paymentMethod: 'Cash',
        notes: '',
        receivedBy: frontDeskOfficer,
      );
      expect(
        secondReceipt.allocations.map((allocation) => allocation.monthKey),
        ['2026-02', '2026-03'],
      );
      expect(secondReceipt.allocations.map((allocation) => allocation.amount), [
        50,
        100,
      ]);
      expect(await repository.getPayments('fee-feb'), hasLength(2));

      await repository.reversePayment(
        paymentId: secondReceipt.paymentId,
        actor: administrator,
        reason: 'Test correction',
      );
      final reversedHistory = await repository.getPayments('fee-feb');
      expect(reversedHistory, hasLength(3));
      expect(
        reversedHistory
            .singleWhere((payment) => payment.isReversal)
            .amountPaidThisReceipt,
        -50,
      );
      final afterReversal = (await repository.getMonthlyCharges('2026-03'))
          .single;
      expect(afterReversal.arrearsBalance, 50);
      expect(afterReversal.balance, 300);
      expect(afterReversal.totalOutstanding, 350);
    },
  );

  test(
    'can apply a payment to a specifically selected arrears month',
    () async {
      final database = await _createFeeDatabase();
      addTearDown(database.close);
      final repository = FeeRepository(
        database: AppDatabase.forTesting(database),
      );
      await database.insert('students', {
        'student_id': 'student-2',
        'admission_number': 'GR-002',
        'first_name': 'Sara',
        'last_name': 'Ali',
        'class_name': 'Class 3',
      });
      for (final charge in [
        ('fee-sep', '2026-09', 100.0),
        ('fee-oct', '2026-10', 200.0),
        ('fee-nov', '2026-11', 300.0),
      ]) {
        await database.insert('fee_charges', {
          'fee_id': charge.$1,
          'student_id': 'student-2',
          'month_key': charge.$2,
          'amount_due': charge.$3,
          'created_at': DateTime(2026, 11).toIso8601String(),
        });
      }

      final receipt = await repository.recordPayment(
        charge: const FeeCharge(
          id: 'fee-nov',
          studentId: 'student-2',
          admissionNumber: 'GR-002',
          studentName: 'Sara Ali',
          className: 'Class 3',
          monthKey: '2026-11',
          amountDue: 300,
          amountPaid: 0,
        ),
        amount: 75,
        applyToFeeId: 'fee-oct',
        paymentMethod: 'Cash',
        notes: '',
        receivedBy: frontDeskOfficer,
      );

      expect(receipt.allocations, hasLength(1));
      expect(receipt.allocations.single.monthKey, '2026-10');
      expect(receipt.allocations.single.amount, 75);
      final charges = await repository.getMonthlyCharges('2026-11');
      expect(charges.single.arrears.map((charge) => charge.monthKey), [
        '2026-09',
        '2026-10',
      ]);
      expect(charges.single.arrears.last.balance, 125);
    },
  );

  test('returns only fee months inside an inclusive month range', () async {
    final database = await _createFeeDatabase();
    addTearDown(database.close);
    final repository = FeeRepository(
      database: AppDatabase.forTesting(database),
    );
    await database.insert('students', {
      'student_id': 'student-range',
      'admission_number': 'GR-RANGE',
      'first_name': 'Amina',
      'last_name': 'Khan',
      'class_name': 'Class 3',
    });
    for (final month in ['2026-03', '2026-04', '2027-03', '2027-04']) {
      await database.insert('fee_charges', {
        'fee_id': 'fee-$month',
        'student_id': 'student-range',
        'month_key': month,
        'amount_due': 100,
        'created_at': '$month-01T00:00:00.000',
      });
    }

    final charges = await repository.getChargesForMonthRange(
      '2026-04',
      '2027-03',
    );

    expect(charges.map((charge) => charge.monthKey), ['2026-04', '2027-03']);
  });
}
