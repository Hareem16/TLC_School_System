import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../auth/app_user.dart';
import 'app_database.dart';
import 'record_id.dart';

int _toCents(double amount) => (amount * 100).round();

bool _hasCentPrecision(double amount) =>
    (amount * 100 - _toCents(amount)).abs() < 0.000001;

class FeeCharge {
  final String id;
  final String studentId;
  final String admissionNumber;
  final String studentName;
  final String guardianName;
  final String className;
  final String monthKey;
  final String familyNo;
  final double amountDue;
  final double amountPaid;
  final double fees;
  final double annual;
  final double admission;
  final double lab;
  final double copies;
  final double stationery;
  final double extras;
  final double lpc;
  final String remarks;
  final DateTime? createdAt;
  final List<FeeCharge> arrears;

  const FeeCharge({
    required this.id,
    required this.studentId,
    required this.admissionNumber,
    required this.studentName,
    this.guardianName = '',
    required this.className,
    required this.monthKey,
    this.familyNo = '',
    required this.amountDue,
    required this.amountPaid,
    this.fees = 0,
    this.annual = 0,
    this.admission = 0,
    this.lab = 0,
    this.copies = 0,
    this.stationery = 0,
    this.extras = 0,
    this.lpc = 0,
    this.remarks = '',
    this.createdAt,
    this.arrears = const [],
  });

  double get balance {
    final cents = _toCents(amountDue) - _toCents(amountPaid);
    return (cents < 0 ? 0 : cents) / 100;
  }

  double get arrearsBalance =>
      arrears.fold<int>(
        0,
        (total, charge) => total + _toCents(charge.balance),
      ) /
      100;

  double get totalPayable =>
      (_toCents(amountDue) + _toCents(arrearsBalance)) / 100;

  double get totalOutstanding =>
      (_toCents(balance) + _toCents(arrearsBalance)) / 100;

  String get detailsMonths =>
      [...arrears.map((charge) => charge.monthKey), monthKey].join(', ');

  String get status => totalOutstanding == 0
      ? 'Paid'
      : amountPaid > 0 || arrears.any((charge) => charge.amountPaid > 0)
      ? 'Partial'
      : 'Unpaid';

  FeeCharge withArrears(List<FeeCharge> value) => FeeCharge(
    id: id,
    studentId: studentId,
    admissionNumber: admissionNumber,
    studentName: studentName,
    guardianName: guardianName,
    className: className,
    monthKey: monthKey,
    familyNo: familyNo,
    amountDue: amountDue,
    amountPaid: amountPaid,
    fees: fees,
    annual: annual,
    admission: admission,
    lab: lab,
    copies: copies,
    stationery: stationery,
    extras: extras,
    lpc: lpc,
    remarks: remarks,
    createdAt: createdAt,
    arrears: value,
  );

  Map<String, Object?> toDatabaseMap() => {
    'fee_id': id,
    'student_id': studentId,
    'admission_number': admissionNumber,
    'student_name': studentName,
    'guardian_name': guardianName,
    'class_name': className,
    'month_key': monthKey,
    'family_no': familyNo,
    'amount_due': amountDue,
    'amount_paid': amountPaid,
    'fees': fees,
    'annual': annual,
    'admission': admission,
    'lab': lab,
    'copies': copies,
    'stationery': stationery,
    'extras': extras,
    'lpc': lpc,
    'remarks': remarks,
    'created_at': createdAt?.toIso8601String(),
  };

  factory FeeCharge.fromDatabaseMap(Map<String, Object?> row) => FeeCharge(
    id: row['fee_id']! as String,
    studentId: row['student_id']! as String,
    admissionNumber: row['admission_number']! as String,
    studentName:
        (row['student_name'] as String?) ??
        '${row['first_name']! as String} ${row['last_name']! as String}'.trim(),
    guardianName: (row['guardian_name'] as String?) ?? '',
    className: row['class_name']! as String,
    monthKey: row['month_key']! as String,
    familyNo: (row['family_no'] as String?) ?? '',
    amountDue: (row['amount_due']! as num).toDouble(),
    amountPaid: (row['amount_paid']! as num).toDouble(),
    fees:
        (row['fees'] as num?)?.toDouble() ??
        (row['amount_due']! as num).toDouble(),
    annual: (row['annual'] as num?)?.toDouble() ?? 0,
    admission: (row['admission'] as num?)?.toDouble() ?? 0,
    lab: (row['lab'] as num?)?.toDouble() ?? 0,
    copies: (row['copies'] as num?)?.toDouble() ?? 0,
    stationery: (row['stationery'] as num?)?.toDouble() ?? 0,
    extras: (row['extras'] as num?)?.toDouble() ?? 0,
    lpc: (row['lpc'] as num?)?.toDouble() ?? 0,
    remarks: (row['remarks'] as String?) ?? '',
    createdAt: row['created_at'] == null
        ? null
        : DateTime.parse(row['created_at']! as String),
  );

  String get voucherNumber =>
      '$admissionNumber-${monthKey.replaceAll('-', '')}';
}

class FeePayment {
  final String paymentId;
  final String receiptNumber;
  final String studentName;
  final String admissionNumber;
  final String className;
  final String monthKey;
  final double amountDue;
  final double amountPaidThisReceipt;
  final double receiptAmount;
  final double totalPaid;
  final double balance;
  final DateTime paidAt;
  final String paymentMethod;
  final String notes;
  final String receivedByName;
  final String receivedByRole;
  final bool isReversal;
  final bool isReversed;
  final String reversalReason;
  final String reversedByName;
  final List<FeePaymentAllocation> allocations;

  const FeePayment({
    required this.paymentId,
    required this.receiptNumber,
    required this.studentName,
    required this.admissionNumber,
    required this.className,
    required this.monthKey,
    required this.amountDue,
    required this.amountPaidThisReceipt,
    this.receiptAmount = 0,
    required this.totalPaid,
    required this.balance,
    required this.paidAt,
    required this.paymentMethod,
    required this.notes,
    this.receivedByName = '',
    this.receivedByRole = '',
    this.isReversal = false,
    this.isReversed = false,
    this.reversalReason = '',
    this.reversedByName = '',
    this.allocations = const [],
  });
}

class FeePaymentAllocation {
  final String feeId;
  final String monthKey;
  final double amount;

  const FeePaymentAllocation({
    required this.feeId,
    required this.monthKey,
    required this.amount,
  });
}

class FeeRepository {
  final AppDatabase _database;

  FeeRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  Future<int> createMonthlyCharges(String monthKey) async {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(monthKey)) {
      throw ArgumentError.value(monthKey, 'monthKey');
    }
    final database = await _database.database;
    var created = 0;
    await database.transaction((transaction) async {
      final existingRows = await transaction.query(
        'fee_charges',
        columns: ['student_id'],
        where: 'month_key = ?',
        whereArgs: [monthKey],
      );
      final existingStudentIds = existingRows
          .map((row) => row['student_id']! as String)
          .toSet();
      final students = await transaction.query(
        'students',
        columns: ['student_id', 'monthly_fee'],
        where: '(date_of_removal IS NULL OR date_of_removal = ?) AND monthly_fee > 0',
        whereArgs: [''],
      );
      for (final student in students) {
        final studentId = student['student_id']! as String;
        if (existingStudentIds.contains(studentId)) continue;
        final fee = (student['monthly_fee']! as num).toDouble();
        await transaction.insert('fee_charges', {
          'fee_id': newRecordId(),
          'student_id': studentId,
          'month_key': monthKey,
          'amount_due': fee,
          'fees': fee,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        created++;
      }
    });
    return created;
  }

  Future<List<FeeCharge>> getMonthlyCharges(
    String monthKey, {
    String search = '',
    List<String>? studentIds,
  }) async {
    if (studentIds != null && studentIds.isEmpty) return const [];
    final database = await _database.database;
    final normalizedSearch = '%${search.trim()}%';
    final scopeFilter = studentIds == null
        ? ''
        : 'AND s.student_id IN (${List.filled(studentIds.length, '?').join(',')})';
    final arguments = <Object?>[
      monthKey,
      normalizedSearch,
      normalizedSearch,
      normalizedSearch,
      normalizedSearch,
      ...?studentIds,
    ];
    final rows = await database.rawQuery('''
            SELECT f.fee_id, f.student_id, f.month_key, f.amount_due, f.fees,
              f.annual, f.admission, f.lab, f.copies, f.stationery, f.extras,
              f.lpc, f.remarks, f.created_at,
             s.admission_number, s.first_name, s.last_name, s.class_name,
             COALESCE(s.family_no, '') AS family_no,
             COALESCE(s.guardian_name, '') AS guardian_name,
             COALESCE((SELECT SUM(a.amount)
                       FROM fee_payment_allocations a
                       WHERE a.fee_id = f.fee_id
                         AND NOT EXISTS (
                           SELECT 1 FROM fee_payment_reversals r
                           WHERE r.payment_id = a.payment_id
                         )), 0) AS amount_paid
      FROM fee_charges f
      JOIN students s ON s.student_id = f.student_id
      WHERE f.month_key = ?
        AND (? = '%%' OR s.first_name LIKE ? OR s.last_name LIKE ?
             OR s.admission_number LIKE ?)
        $scopeFilter
      ORDER BY s.class_name COLLATE NOCASE, s.first_name COLLATE NOCASE,
               s.last_name COLLATE NOCASE
      ''', arguments);
    return _attachArrears(
      rows.map(FeeCharge.fromDatabaseMap).toList(growable: false),
    );
  }

  Future<List<FeeCharge>> getChargesForMonthRange(
    String startMonthKey,
    String endMonthKey, {
    String search = '',
    List<String>? studentIds,
  }) async {
    const monthPattern = r'^\d{4}-(0[1-9]|1[0-2])$';
    if (!RegExp(monthPattern).hasMatch(startMonthKey) ||
        !RegExp(monthPattern).hasMatch(endMonthKey) ||
        endMonthKey.compareTo(startMonthKey) < 0) {
      throw ArgumentError('A valid, ordered fee-month range is required.');
    }
    if (studentIds != null && studentIds.isEmpty) return const [];
    final database = await _database.database;
    final normalizedSearch = '%${search.trim()}%';
    final scopeFilter = studentIds == null
        ? ''
        : 'AND s.student_id IN (${List.filled(studentIds.length, '?').join(',')})';
    final rows = await database.rawQuery('''
      SELECT f.fee_id, f.student_id, f.month_key, f.amount_due, f.fees,
        f.annual, f.admission, f.lab, f.copies, f.stationery, f.extras,
        f.lpc, f.remarks, f.created_at,
        s.admission_number, s.first_name, s.last_name, s.class_name,
        COALESCE(s.family_no, '') AS family_no,
        COALESCE(s.guardian_name, '') AS guardian_name,
        COALESCE((SELECT SUM(a.amount)
                  FROM fee_payment_allocations a
                  WHERE a.fee_id = f.fee_id
                    AND NOT EXISTS (
                      SELECT 1 FROM fee_payment_reversals r
                      WHERE r.payment_id = a.payment_id
                    )), 0) AS amount_paid
      FROM fee_charges f
      JOIN students s ON s.student_id = f.student_id
      WHERE f.month_key BETWEEN ? AND ?
        AND (? = '%%' OR s.first_name LIKE ? OR s.last_name LIKE ?
             OR s.admission_number LIKE ?)
        $scopeFilter
      ORDER BY f.month_key, s.class_name COLLATE NOCASE,
               s.first_name COLLATE NOCASE, s.last_name COLLATE NOCASE
      ''', [
      startMonthKey,
      endMonthKey,
      normalizedSearch,
      normalizedSearch,
      normalizedSearch,
      normalizedSearch,
      ...?studentIds,
    ]);
    return _attachArrears(
      rows.map(FeeCharge.fromDatabaseMap).toList(growable: false),
    );
  }

  Future<List<FeeCharge>> getChargesCreatedBetween(
    DateTime startDate,
    DateTime endDate, {
    String search = '',
    List<String>? studentIds,
  }) async {
    if (endDate.isBefore(startDate)) {
      throw ArgumentError.value(
        endDate,
        'endDate',
        'Must not precede startDate.',
      );
    }
    if (studentIds != null && studentIds.isEmpty) return const [];
    final database = await _database.database;
    final scopeFilter = studentIds == null
        ? ''
        : 'AND s.student_id IN (${List.filled(studentIds.length, '?').join(',')})';
    final normalizedSearch = '%${search.trim()}%';
    final rows = await database.rawQuery(
      '''
            SELECT f.fee_id, f.student_id, f.month_key, f.amount_due, f.fees,
              f.annual, f.admission, f.lab, f.copies, f.stationery, f.extras,
              f.lpc, f.remarks, f.created_at,
             s.admission_number, s.first_name, s.last_name, s.class_name,
             COALESCE(s.family_no, '') AS family_no,
             COALESCE(s.guardian_name, '') AS guardian_name,
             COALESCE((SELECT SUM(a.amount)
                       FROM fee_payment_allocations a
                       WHERE a.fee_id = f.fee_id
                         AND NOT EXISTS (
                           SELECT 1 FROM fee_payment_reversals r
                           WHERE r.payment_id = a.payment_id
                         )), 0) AS amount_paid
      FROM fee_charges f
      JOIN students s ON s.student_id = f.student_id
      WHERE date(f.created_at) BETWEEN ? AND ?
        AND (? = '%%' OR s.first_name LIKE ? OR s.last_name LIKE ?
             OR s.admission_number LIKE ?)
        $scopeFilter
      ORDER BY f.created_at, s.class_name COLLATE NOCASE,
               s.first_name COLLATE NOCASE, s.last_name COLLATE NOCASE
      ''',
      [
        startDate.toIso8601String().split('T').first,
        endDate.toIso8601String().split('T').first,
        normalizedSearch,
        normalizedSearch,
        normalizedSearch,
        normalizedSearch,
        ...?studentIds,
      ],
    );
    return _attachArrears(
      rows.map(FeeCharge.fromDatabaseMap).toList(growable: false),
    );
  }

  Future<List<FeeCharge>> _attachArrears(List<FeeCharge> charges) async {
    if (charges.isEmpty) return charges;
    final database = await _database.database;
    final latestMonth = charges
        .map((charge) => charge.monthKey)
        .reduce(
          (latest, month) => month.compareTo(latest) > 0 ? month : latest,
        );
    final rows = await database.rawQuery(
      '''
      SELECT f.fee_id, f.student_id, f.month_key, f.amount_due, f.fees,
             f.annual, f.admission, f.lab, f.copies, f.stationery, f.extras,
             f.lpc, f.remarks, f.created_at,
             s.admission_number, s.first_name, s.last_name, s.class_name,
             COALESCE(s.family_no, '') AS family_no,
             COALESCE(s.guardian_name, '') AS guardian_name,
             COALESCE((SELECT SUM(a.amount)
                       FROM fee_payment_allocations a
                       WHERE a.fee_id = f.fee_id
                         AND NOT EXISTS (
                           SELECT 1 FROM fee_payment_reversals r
                           WHERE r.payment_id = a.payment_id
                         )), 0) AS amount_paid
      FROM fee_charges f
      JOIN students s ON s.student_id = f.student_id
      WHERE f.month_key < ?
      ORDER BY f.student_id, f.month_key
      ''',
      [latestMonth],
    );
    final studentIds = charges.map((charge) => charge.studentId).toSet();
    final arrearsByStudent = <String, List<FeeCharge>>{};
    for (final row in rows) {
      final charge = FeeCharge.fromDatabaseMap(row);
      if (!studentIds.contains(charge.studentId) || charge.balance <= 0) {
        continue;
      }
      arrearsByStudent.putIfAbsent(charge.studentId, () => []).add(charge);
    }
    return charges
        .map(
          (charge) => charge.withArrears(
            (arrearsByStudent[charge.studentId] ?? const <FeeCharge>[])
                .where(
                  (arrears) => arrears.monthKey.compareTo(charge.monthKey) < 0,
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  Future<void> updateChargeBreakdown({
    required FeeCharge charge,
    required double fees,
    required double annual,
    required double admission,
    required double lab,
    required double copies,
    required double stationery,
    required double extras,
    required double lpc,
    required String remarks,
    required AppUser actor,
  }) async {
    if (actor.role != AppRoles.frontDeskOfficer &&
        !AppRoles.fullAccessRoles.contains(actor.role)) {
      throw StateError('Your account cannot edit fee charges.');
    }
    final amounts = [
      fees,
      annual,
      admission,
      lab,
      copies,
      stationery,
      extras,
      lpc,
    ];
    if (amounts.any((amount) => !amount.isFinite || amount < 0)) {
      throw ArgumentError('Fee-head amounts must be finite and non-negative.');
    }
    if (amounts.any((amount) => !_hasCentPrecision(amount))) {
      throw ArgumentError('Fee-head amounts must use at most two decimals.');
    }

    final database = await _database.database;
    final amountCents = amounts.map(_toCents).toList(growable: false);
    final total = amountCents.fold<int>(0, (sum, amount) => sum + amount) / 100;
    final now = DateTime.now().toIso8601String();
    await database.transaction((transaction) async {
      final chargeRows = await transaction.query(
        'fee_charges',
        columns: ['fee_id'],
        where: 'fee_id = ?',
        whereArgs: [charge.id],
        limit: 1,
      );
      if (chargeRows.isEmpty) {
        throw StateError('The fee charge no longer exists.');
      }
      final payments = await transaction.query(
        'fee_payment_allocations',
        columns: ['allocation_id'],
        where: 'fee_id = ?',
        whereArgs: [charge.id],
        limit: 1,
      );
      if (payments.isNotEmpty) {
        throw StateError('A charge with recorded payments cannot be edited.');
      }

      await transaction.update(
        'fee_charges',
        {
          'amount_due': total,
          'fees': amountCents[0] / 100,
          'annual': amountCents[1] / 100,
          'admission': amountCents[2] / 100,
          'lab': amountCents[3] / 100,
          'copies': amountCents[4] / 100,
          'stationery': amountCents[5] / 100,
          'extras': amountCents[6] / 100,
          'lpc': amountCents[7] / 100,
          'remarks': remarks.trim(),
        },
        where: 'fee_id = ?',
        whereArgs: [charge.id],
      );
      await transaction.insert('admin_audit_logs', {
        'log_id': newRecordId(),
        'actor_user_id': actor.id,
        'actor_name': actor.fullName,
        'action': 'fee_charge_breakdown_updated',
        'target': charge.voucherNumber,
        'details':
            'Total: PKR ${total.toStringAsFixed(2)}; '
            'remarks: ${remarks.trim()}',
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  Future<FeePayment> recordPayment({
    required FeeCharge charge,
    required double amount,
    String? applyToFeeId,
    required String paymentMethod,
    required String notes,
    required AppUser receivedBy,
  }) async {
    if (!amount.isFinite || amount <= 0 || !_hasCentPrecision(amount)) {
      throw ArgumentError.value(amount, 'amount');
    }
    final amountCents = _toCents(amount);
    if (receivedBy.role != AppRoles.frontDeskOfficer &&
        !AppRoles.fullAccessRoles.contains(receivedBy.role)) {
      throw StateError('Your account cannot record fee payments.');
    }
    final database = await _database.database;
    final now = DateTime.now();
    final receiptNumber =
        'TLC-${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}-'
        '${newRecordId().substring(0, 8).toUpperCase()}';

    return database.transaction((transaction) async {
      final rows = await transaction.rawQuery(
        '''
        SELECT f.fee_id, f.month_key, f.amount_due,
          COALESCE((SELECT SUM(a.amount)
                    FROM fee_payment_allocations a
                    WHERE a.fee_id = f.fee_id
                      AND NOT EXISTS (
                        SELECT 1 FROM fee_payment_reversals r
                        WHERE r.payment_id = a.payment_id
                      )), 0) AS amount_paid
        FROM fee_charges f
        WHERE f.student_id = ? AND f.month_key <= ?
        ORDER BY f.month_key, f.created_at, f.fee_id
        ''',
        [charge.studentId, charge.monthKey],
      );
      if (!rows.any((row) => row['fee_id'] == charge.id)) {
        throw StateError('The fee charge no longer exists.');
      }
      final balanceBeforeCents = rows.fold<int>(0, (total, row) {
        final due = (row['amount_due']! as num).toDouble();
        final paid = (row['amount_paid']! as num).toDouble();
        final balanceCents = _toCents(due) - _toCents(paid);
        return total + (balanceCents < 0 ? 0 : balanceCents);
      });
      final balanceBefore = balanceBeforeCents / 100;
      final allocationRows = applyToFeeId == null
          ? rows
          : rows.where((row) => row['fee_id'] == applyToFeeId).toList();
      if (allocationRows.isEmpty) {
        throw StateError('The selected fee month is no longer available.');
      }
      final allocatableBalanceCents = allocationRows.fold<int>(0, (total, row) {
        final due = (row['amount_due']! as num).toDouble();
        final paid = (row['amount_paid']! as num).toDouble();
        final balanceCents = _toCents(due) - _toCents(paid);
        return total + (balanceCents < 0 ? 0 : balanceCents);
      });
      if (amountCents > allocatableBalanceCents) {
        throw StateError(
          'Payment exceeds the selected remaining balance of PKR '
          '${(allocatableBalanceCents / 100).toStringAsFixed(2)}.',
        );
      }

      final paymentId = newRecordId();
      await transaction.insert('fee_payments', {
        'payment_id': paymentId,
        'fee_id': charge.id,
        'receipt_number': receiptNumber,
        'amount': amount,
        'paid_at': now.toIso8601String(),
        'payment_method': paymentMethod,
        'notes': notes.trim(),
        'received_by_user_id': receivedBy.id,
        'received_by_name': receivedBy.fullName,
        'received_by_role': receivedBy.role,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      var remainingCents = amountCents;
      final allocations = <FeePaymentAllocation>[];
      for (final row in allocationRows) {
        final due = (row['amount_due']! as num).toDouble();
        final paid = (row['amount_paid']! as num).toDouble();
        final balanceCents = _toCents(due) - _toCents(paid);
        final chargeBalanceCents = balanceCents < 0 ? 0 : balanceCents;
        if (chargeBalanceCents == 0 || remainingCents == 0) continue;
        final appliedCents = chargeBalanceCents < remainingCents
            ? chargeBalanceCents
            : remainingCents;
        final applied = appliedCents / 100;
        final feeId = row['fee_id']! as String;
        final monthKey = row['month_key']! as String;
        await transaction.insert('fee_payment_allocations', {
          'allocation_id': newRecordId(),
          'payment_id': paymentId,
          'fee_id': feeId,
          'amount': applied,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        allocations.add(
          FeePaymentAllocation(
            feeId: feeId,
            monthKey: monthKey,
            amount: applied,
          ),
        );
        remainingCents -= appliedCents;
      }

      return FeePayment(
        paymentId: paymentId,
        receiptNumber: receiptNumber,
        studentName: charge.studentName,
        admissionNumber: charge.admissionNumber,
        className: charge.className,
        monthKey: charge.monthKey,
        amountDue: balanceBefore,
        amountPaidThisReceipt: amount,
        receiptAmount: amount,
        totalPaid: amount,
        balance: (balanceBeforeCents - amountCents) / 100,
        paidAt: now,
        paymentMethod: paymentMethod,
        notes: notes.trim(),
        receivedByName: receivedBy.fullName,
        receivedByRole: receivedBy.role,
        allocations: allocations,
      );
    });
  }

  Future<void> reversePayment({
    required String paymentId,
    required AppUser actor,
    required String reason,
  }) async {
    if (actor.role != AppRoles.administrator) {
      throw StateError('Only an Administrator can reverse a fee payment.');
    }
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'A reason is required.');
    }

    final database = await _database.database;
    final now = DateTime.now().toIso8601String();
    await database.transaction((transaction) async {
      final payments = await transaction.query(
        'fee_payments',
        columns: ['amount', 'receipt_number'],
        where: 'payment_id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      if (payments.isEmpty) {
        throw StateError('The fee receipt no longer exists.');
      }
      final alreadyReversed = await transaction.query(
        'fee_payment_reversals',
        columns: ['reversal_id'],
        where: 'payment_id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      if (alreadyReversed.isNotEmpty) {
        throw StateError('This fee receipt has already been reversed.');
      }

      final amount = (payments.single['amount']! as num).toDouble();
      final receiptNumber = payments.single['receipt_number']! as String;
      await transaction.insert('fee_payment_reversals', {
        'reversal_id': newRecordId(),
        'payment_id': paymentId,
        'amount': amount,
        'reason': normalizedReason,
        'reversed_at': now,
        'reversed_by_user_id': actor.id,
        'reversed_by_name': actor.fullName,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      await transaction.insert('admin_audit_logs', {
        'log_id': newRecordId(),
        'actor_user_id': actor.id,
        'actor_name': actor.fullName,
        'action': 'fee_payment_reversed',
        'target': receiptNumber,
        'details':
            'Amount: PKR ${amount.toStringAsFixed(2)}; '
            'reason: $normalizedReason',
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  Future<List<FeePayment>> getPayments(String feeId) async {
    final database = await _database.database;
    final rows = await database.rawQuery(
      '''
      SELECT * FROM (
        SELECT p.payment_id, f.fee_id, p.receipt_number,
               a.amount AS amount, p.amount AS receipt_amount,
               p.paid_at AS event_at, p.payment_method, p.notes,
               p.received_by_name, p.received_by_role,
               CASE WHEN r.reversal_id IS NULL THEN 0 ELSE 1 END AS is_reversed,
               0 AS is_reversal, '' AS reversal_reason,
               '' AS reversed_by_name,
               f.month_key, f.amount_due, s.admission_number, s.first_name,
               s.last_name, s.class_name,
               COALESCE((SELECT SUM(a2.amount)
                         FROM fee_payment_allocations a2
                         WHERE a2.fee_id = f.fee_id
                           AND NOT EXISTS (
                             SELECT 1 FROM fee_payment_reversals r2
                             WHERE r2.payment_id = a2.payment_id
                           )), 0) AS total_paid
        FROM fee_payment_allocations a
        JOIN fee_payments p ON p.payment_id = a.payment_id
        JOIN fee_charges f ON f.fee_id = a.fee_id
        JOIN students s ON s.student_id = f.student_id
        LEFT JOIN fee_payment_reversals r ON r.payment_id = p.payment_id
        WHERE a.fee_id = ?
        UNION ALL
        SELECT p.payment_id, f.fee_id,
               'REVERSAL • ' || p.receipt_number AS receipt_number,
               -a.amount AS amount, p.amount AS receipt_amount,
               r.reversed_at AS event_at,
               'Correction' AS payment_method, r.reason AS notes,
               '' AS received_by_name, '' AS received_by_role,
               1 AS is_reversed, 1 AS is_reversal, r.reason AS reversal_reason,
               r.reversed_by_name,
               f.month_key, f.amount_due, s.admission_number, s.first_name,
               s.last_name, s.class_name,
               COALESCE((SELECT SUM(a2.amount)
                         FROM fee_payment_allocations a2
                         WHERE a2.fee_id = f.fee_id
                           AND NOT EXISTS (
                             SELECT 1 FROM fee_payment_reversals r2
                             WHERE r2.payment_id = a2.payment_id
                           )), 0) AS total_paid
        FROM fee_payment_reversals r
        JOIN fee_payments p ON p.payment_id = r.payment_id
        JOIN fee_payment_allocations a ON a.payment_id = p.payment_id
        JOIN fee_charges f ON f.fee_id = a.fee_id
        JOIN students s ON s.student_id = f.student_id
        WHERE a.fee_id = ?
      )
      ORDER BY event_at DESC
      ''',
      [feeId, feeId],
    );
    return rows
        .map((row) {
          final due = (row['amount_due']! as num).toDouble();
          final isReversal = (row['is_reversal']! as int) == 1;
          final totalPaid = (row['total_paid']! as num).toDouble();
          return FeePayment(
            paymentId: row['payment_id']! as String,
            receiptNumber: row['receipt_number']! as String,
            studentName:
                '${row['first_name']! as String} ${row['last_name']! as String}'
                    .trim(),
            admissionNumber: row['admission_number']! as String,
            className: row['class_name']! as String,
            monthKey: row['month_key']! as String,
            amountDue: due,
            amountPaidThisReceipt: (row['amount']! as num).toDouble(),
            receiptAmount: (row['receipt_amount']! as num).toDouble(),
            totalPaid: totalPaid,
            balance: (due - totalPaid).clamp(0, double.infinity).toDouble(),
            paidAt: DateTime.parse(row['event_at']! as String),
            paymentMethod: row['payment_method']! as String,
            notes: row['notes']! as String,
            receivedByName: row['received_by_name']! as String,
            receivedByRole: row['received_by_role']! as String,
            isReversal: isReversal,
            isReversed: (row['is_reversed']! as int) == 1,
            reversalReason: row['reversal_reason']! as String,
            reversedByName: row['reversed_by_name']! as String,
          );
        })
        .toList(growable: false);
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
