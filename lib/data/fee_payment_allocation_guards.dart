import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Installs database-level safeguards for permanent fee payment allocations.
///
/// A receipt may be split across several fee months, but its allocations must
/// never exceed the receipt amount or be assigned to a different student.
/// Once inserted, allocations are append-only so historical receipt coverage
/// cannot be silently rewritten.
Future<void> createFeePaymentAllocationGuards(
  DatabaseExecutor database,
) async {
  await database.execute('''
    CREATE TRIGGER IF NOT EXISTS fee_payment_allocations_validate_insert
    BEFORE INSERT ON fee_payment_allocations
    WHEN
      NOT EXISTS (
        SELECT 1
        FROM fee_payments p
        JOIN fee_charges source_fee ON source_fee.fee_id = p.fee_id
        JOIN fee_charges target_fee ON target_fee.fee_id = NEW.fee_id
        WHERE p.payment_id = NEW.payment_id
          AND source_fee.student_id = target_fee.student_id
          AND COALESCE((
            SELECT SUM(existing.amount)
            FROM fee_payment_allocations existing
            WHERE existing.payment_id = NEW.payment_id
          ), 0) + NEW.amount <= p.amount
      )
    BEGIN
      SELECT RAISE(
        ABORT,
        'Payment allocation must belong to the receipt student and cannot exceed the receipt amount.'
      );
    END
  ''');
  await database.execute('''
    CREATE TRIGGER IF NOT EXISTS fee_payment_allocations_prevent_update
    BEFORE UPDATE ON fee_payment_allocations
    BEGIN
      SELECT RAISE(
        ABORT,
        'Fee payment allocations are permanent and cannot be edited.'
      );
    END
  ''');
  await database.execute('''
    CREATE TRIGGER IF NOT EXISTS fee_payment_allocations_prevent_delete
    BEFORE DELETE ON fee_payment_allocations
    BEGIN
      SELECT RAISE(
        ABORT,
        'Fee payment allocations are permanent and cannot be deleted.'
      );
    END
  ''');
}
