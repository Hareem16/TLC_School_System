import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../auth/app_user.dart';
import 'app_database.dart';
import 'record_id.dart';

int _toCents(double amount) => (amount * 100).round();

bool _hasCentPrecision(double amount) =>
    (amount * 100 - _toCents(amount)).abs() < 0.000001;

class SchoolSalaryPayment {
  final String staffId;
  final String monthKey;
  final double baseSalary;
  final double allowances;
  final double deductions;
  final DateTime paidAt;
  final String paymentMethod;
  final String notes;

  const SchoolSalaryPayment({
    required this.staffId,
    required this.monthKey,
    required this.baseSalary,
    required this.allowances,
    required this.deductions,
    required this.paidAt,
    required this.paymentMethod,
    required this.notes,
  });

  double get netSalary => baseSalary + allowances - deductions;

  factory SchoolSalaryPayment.fromDatabaseMap(Map<String, Object?> row) =>
      SchoolSalaryPayment(
        staffId: row['staff_id']! as String,
        monthKey: row['month_key']! as String,
        baseSalary: (row['base_salary']! as num).toDouble(),
        allowances: (row['allowances']! as num).toDouble(),
        deductions: (row['deductions']! as num).toDouble(),
        paidAt: DateTime.parse(row['paid_at']! as String),
        paymentMethod: row['payment_method']! as String,
        notes: row['notes']! as String,
      );
}

class SchoolAccountMonth {
  final String monthKey;
  final double feeReceipts;
  final double feeReversals;
  final double salaryPayments;
  final double netMovement;
  final double closingBalance;

  const SchoolAccountMonth({
    required this.monthKey,
    required this.feeReceipts,
    required this.feeReversals,
    required this.salaryPayments,
    required this.netMovement,
    required this.closingBalance,
  });
}

class SchoolAccountSummary {
  final double openingBalance;
  final DateTime openingBalanceDate;
  final double currentBalance;
  final List<SchoolAccountMonth> months;

  const SchoolAccountSummary({
    required this.openingBalance,
    required this.openingBalanceDate,
    required this.currentBalance,
    required this.months,
  });
}

class SchoolFinanceRepository {
  final AppDatabase _database;

  SchoolFinanceRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  Future<Map<String, SchoolSalaryPayment>> getSalaryPayments(
    String monthKey,
  ) async {
    if (!_validMonthKey(monthKey)) {
      throw ArgumentError.value(monthKey, 'monthKey');
    }
    final database = await _database.database;
    final rows = await database.query(
      'staff_salary_records',
      where: 'month_key = ? AND status = ?',
      whereArgs: [monthKey, 'paid'],
    );
    return {
      for (final row in rows)
        row['staff_id']! as String: SchoolSalaryPayment.fromDatabaseMap(row),
    };
  }

  Future<SchoolSalaryPayment> recordSalaryPayment({
    required String staffId,
    required String monthKey,
    required double deductions,
    required String paymentMethod,
    required String notes,
    required AppUser actor,
    double allowances = 0,
    DateTime? paidAt,
  }) async {
    _requireFullAccess(actor);
    if (!_validMonthKey(monthKey)) {
      throw ArgumentError.value(monthKey, 'monthKey');
    }
    if (!deductions.isFinite ||
        deductions < 0 ||
        !allowances.isFinite ||
        allowances < 0 ||
        !_hasCentPrecision(deductions) ||
        !_hasCentPrecision(allowances)) {
      throw ArgumentError('Salary amounts must be valid and use two decimals.');
    }
    final method = paymentMethod.trim();
    if (method.isEmpty) {
      throw ArgumentError.value(
        paymentMethod,
        'paymentMethod',
        'A payment method is required.',
      );
    }
    final date = (paidAt ?? DateTime.now()).toIso8601String();
    final database = await _database.database;

    return database.transaction((transaction) async {
      final staffRows = await transaction.query(
        'staff',
        columns: ['monthly_salary'],
        where: 'staff_id = ?',
        whereArgs: [staffId],
        limit: 1,
      );
      if (staffRows.isEmpty) {
        throw StateError('The staff member no longer exists.');
      }
      final baseSalary = (staffRows.single['monthly_salary']! as num)
          .toDouble();
      if (!baseSalary.isFinite ||
          baseSalary < 0 ||
          !_hasCentPrecision(baseSalary)) {
        throw StateError('The staff member has an invalid monthly salary.');
      }
      final netCents =
          _toCents(baseSalary) + _toCents(allowances) - _toCents(deductions);
      if (netCents < 0) {
        throw ArgumentError('Salary deductions cannot exceed the net salary.');
      }
      final existing = await transaction.query(
        'staff_salary_records',
        where: 'staff_id = ? AND month_key = ?',
        whereArgs: [staffId, monthKey],
        limit: 1,
      );
      if (existing.isNotEmpty && existing.single['status'] == 'paid') {
        throw StateError('This salary has already been recorded as paid.');
      }

      final values = <String, Object?>{
        'base_salary': baseSalary,
        'allowances': allowances,
        'deductions': deductions,
        'status': 'paid',
        'paid_at': date,
        'payment_method': method,
        'notes': notes.trim(),
      };
      if (existing.isEmpty) {
        await transaction.insert('staff_salary_records', {
          'salary_id': newRecordId(),
          'staff_id': staffId,
          'month_key': monthKey,
          ...values,
          'created_at': date,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      } else {
        await transaction.update(
          'staff_salary_records',
          values,
          where: 'salary_id = ?',
          whereArgs: [existing.single['salary_id']],
        );
      }

      return SchoolSalaryPayment(
        staffId: staffId,
        monthKey: monthKey,
        baseSalary: baseSalary,
        allowances: allowances,
        deductions: deductions,
        paidAt: DateTime.parse(date),
        paymentMethod: method,
        notes: notes.trim(),
      );
    });
  }

  Future<SchoolAccountSummary> getAccountSummary({DateTime? throughDate}) async {
    final database = await _database.database;
    final settings = await database.query(
      'school_account_settings',
      where: 'setting_id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (settings.isEmpty) {
      throw StateError('The school account opening balance is not configured.');
    }
    final openingBalance = (settings.single['opening_balance']! as num)
        .toDouble();
    final openingDate = DateTime.parse(
      settings.single['opening_balance_date']! as String,
    );
    final endDate = throughDate ?? DateTime.now();
    if (endDate.isBefore(openingDate)) {
      throw ArgumentError.value(
        endDate,
        'throughDate',
        'Cannot precede the opening balance date.',
      );
    }
    final startDateText = _dateKey(openingDate);
    final endDateText = _dateKey(endDate);

    final receipts = await database.rawQuery(
      '''
      SELECT substr(paid_at, 1, 7) AS month_key, SUM(amount) AS total
      FROM fee_payments
      WHERE date(paid_at) >= ? AND date(paid_at) <= ?
      GROUP BY substr(paid_at, 1, 7)
      ''',
      [startDateText, endDateText],
    );
    final reversals = await database.rawQuery(
      '''
      SELECT substr(reversed_at, 1, 7) AS month_key, SUM(amount) AS total
      FROM fee_payment_reversals
      WHERE date(reversed_at) >= ? AND date(reversed_at) <= ?
      GROUP BY substr(reversed_at, 1, 7)
      ''',
      [startDateText, endDateText],
    );
    final salaries = await database.rawQuery(
      '''
      SELECT substr(paid_at, 1, 7) AS month_key,
             SUM(base_salary + allowances - deductions) AS total
      FROM staff_salary_records
      WHERE status = 'paid'
        AND paid_at IS NOT NULL
        AND date(paid_at) >= ? AND date(paid_at) <= ?
      GROUP BY substr(paid_at, 1, 7)
      ''',
      [startDateText, endDateText],
    );
    final receiptTotals = _groupedTotals(receipts);
    final reversalTotals = _groupedTotals(reversals);
    final salaryTotals = _groupedTotals(salaries);
    final months = <SchoolAccountMonth>[];
    var balanceCents = _toCents(openingBalance);
    var cursor = DateTime(openingDate.year, openingDate.month);
    final lastMonth = DateTime(endDate.year, endDate.month);
    while (!cursor.isAfter(lastMonth)) {
      final key = _monthKey(cursor);
      final feeReceiptsCents = _toCents(receiptTotals[key] ?? 0);
      final feeReversalsCents = _toCents(reversalTotals[key] ?? 0);
      final salaryPaymentsCents = _toCents(salaryTotals[key] ?? 0);
      final movementCents =
          feeReceiptsCents - feeReversalsCents - salaryPaymentsCents;
      balanceCents += movementCents;
      months.add(
        SchoolAccountMonth(
          monthKey: key,
          feeReceipts: feeReceiptsCents / 100,
          feeReversals: feeReversalsCents / 100,
          salaryPayments: salaryPaymentsCents / 100,
          netMovement: movementCents / 100,
          closingBalance: balanceCents / 100,
        ),
      );
      cursor = DateTime(cursor.year, cursor.month + 1);
    }

    return SchoolAccountSummary(
      openingBalance: openingBalance,
      openingBalanceDate: openingDate,
      currentBalance: balanceCents / 100,
      months: months,
    );
  }

  Future<void> setOpeningBalance({
    required double amount,
    required DateTime date,
    required AppUser actor,
  }) async {
    _requireFullAccess(actor);
    if (!amount.isFinite ||
        amount < 0 ||
        !_hasCentPrecision(amount) ||
        date.isAfter(DateTime.now())) {
      throw ArgumentError(
        'Opening balance must be non-negative, use two decimals, and have a date no later than today.',
      );
    }
    final database = await _database.database;
    final count = await database.update(
      'school_account_settings',
      {
        'opening_balance': amount,
        'opening_balance_date': _dateKey(date),
      },
      where: 'setting_id = ?',
      whereArgs: [1],
    );
    if (count != 1) {
      throw StateError('The school account settings could not be updated.');
    }
  }

  static void _requireFullAccess(AppUser actor) {
    if (!AppRoles.fullAccessRoles.contains(actor.role)) {
      throw StateError('Only administrators and the principal may do this.');
    }
  }

  static bool _validMonthKey(String value) =>
      RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(value);

  static Map<String, double> _groupedTotals(
    List<Map<String, Object?>> rows,
  ) => {
    for (final row in rows)
      row['month_key']! as String: (row['total']! as num).toDouble(),
  };

  static String _monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
