import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tlc_school_system/data/fee_payment_allocation_guards.dart';

Future<Database> _createDatabase() => databaseFactoryFfi.openDatabase(
  inMemoryDatabasePath,
  options: OpenDatabaseOptions(
    version: 1,
    onConfigure: (database) async {
      await database.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (database, version) async {
      await database.execute('''
        CREATE TABLE fee_charges (
          fee_id TEXT PRIMARY KEY,
          student_id TEXT NOT NULL
        )
      ''');
      await database.execute('''
        CREATE TABLE fee_payments (
          payment_id TEXT PRIMARY KEY,
          fee_id TEXT NOT NULL,
          amount REAL NOT NULL CHECK (amount > 0),
          FOREIGN KEY(fee_id) REFERENCES fee_charges(fee_id)
        )
      ''');
      await database.execute('''
        CREATE TABLE fee_payment_allocations (
          allocation_id TEXT PRIMARY KEY,
          payment_id TEXT NOT NULL,
          fee_id TEXT NOT NULL,
          amount REAL NOT NULL CHECK (amount > 0),
          UNIQUE(payment_id, fee_id),
          FOREIGN KEY(payment_id) REFERENCES fee_payments(payment_id),
          FOREIGN KEY(fee_id) REFERENCES fee_charges(fee_id)
        )
      ''');
    },
  ),
);

void main() {
  setUpAll(sqfliteFfiInit);

  test('allocations are immutable and cannot exceed the receipt amount', () async {
    final database = await _createDatabase();
    addTearDown(database.close);

    await database.insert('fee_charges', {
      'fee_id': 'fee-current',
      'student_id': 'student-1',
    });
    await database.insert('fee_charges', {
      'fee_id': 'fee-arrears',
      'student_id': 'student-1',
    });
    await database.insert('fee_charges', {
      'fee_id': 'fee-other-student',
      'student_id': 'student-2',
    });
    await database.insert('fee_payments', {
      'payment_id': 'receipt-1',
      'fee_id': 'fee-current',
      'amount': 150,
    });

    await createFeePaymentAllocationGuards(database);

    await database.insert('fee_payment_allocations', {
      'allocation_id': 'allocation-1',
      'payment_id': 'receipt-1',
      'fee_id': 'fee-arrears',
      'amount': 100,
    });

    await expectLater(
      database.insert('fee_payment_allocations', {
        'allocation_id': 'allocation-over',
        'payment_id': 'receipt-1',
        'fee_id': 'fee-current',
        'amount': 51,
      }),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      database.insert('fee_payment_allocations', {
        'allocation_id': 'allocation-wrong-student',
        'payment_id': 'receipt-1',
        'fee_id': 'fee-other-student',
        'amount': 50,
      }),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      database.update(
        'fee_payment_allocations',
        {'amount': 50},
        where: 'allocation_id = ?',
        whereArgs: ['allocation-1'],
      ),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      database.delete(
        'fee_payment_allocations',
        where: 'allocation_id = ?',
        whereArgs: ['allocation-1'],
      ),
      throwsA(isA<DatabaseException>()),
    );

    final saved = await database.query('fee_payment_allocations');
    expect(saved, hasLength(1));
    expect(saved.single['amount'], 100);
  });

  test('multiple allocations for the same student may split one receipt', () async {
    final database = await _createDatabase();
    addTearDown(database.close);

    for (final fee in ['fee-one', 'fee-two']) {
      await database.insert('fee_charges', {
        'fee_id': fee,
        'student_id': 'student-1',
      });
    }
    await database.insert('fee_payments', {
      'payment_id': 'receipt-split',
      'fee_id': 'fee-one',
      'amount': 150,
    });

    await createFeePaymentAllocationGuards(database);
    await database.insert('fee_payment_allocations', {
      'allocation_id': 'split-one',
      'payment_id': 'receipt-split',
      'fee_id': 'fee-one',
      'amount': 100,
    });
    await database.insert('fee_payment_allocations', {
      'allocation_id': 'split-two',
      'payment_id': 'receipt-split',
      'fee_id': 'fee-two',
      'amount': 50,
    });

    final rows = await database.query('fee_payment_allocations');
    expect(rows, hasLength(2));
    expect(
      rows.fold<double>(
        0,
        (total, row) => total + (row['amount']! as num).toDouble(),
      ),
      150,
    );
  });
}
