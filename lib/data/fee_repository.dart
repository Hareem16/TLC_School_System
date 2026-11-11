import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../auth/app_user.dart';
import 'app_database.dart';
import 'record_id.dart';

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
  });

  double get balance =>
      (amountDue - amountPaid).clamp(0, double.infinity).toDouble();

  String get status => balance == 0
      ? 'Paid'
      : amountPaid > 0
      ? 'Partial'
      : 'Unpaid';

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
  );
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

  const FeePayment({
    required this.paymentId,
    required this.receiptNumber,
    required this.studentName,
    required this.admissionNumber,
    required this.className,
    required this.monthKey,
    required this.amountDue,
    required this.amountPaidThisReceipt,
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
      SELECT f.fee_id, f.student_id, f.month_key, f.amount_due,
             s.admission_number, s.first_name, s.last_name, s.class_name,
             COALESCE(s.family_no, '') AS family_no,
             COALESCE(s.guardian_name, '') AS guardian_name,
             COALESCE((SELECT SUM(p.amount) FROM fee_payments p
                       WHERE p.fee_id = f.fee_id), 0)
             - COALESCE((SELECT SUM(r.amount)
                         FROM fee_payment_reversals r
                         JOIN fee_payments p ON p.payment_id = r.payment_id
                         WHERE p.fee_id = f.fee_id), 0) AS amount_paid
      FROM fee_charges f
      JOIN students s ON s.student_id = f.student_id
      WHERE f.month_key = ?
        AND (? = '%%' OR s.first_name LIKE ? OR s.last_name LIKE ?
             OR s.admission_number LIKE ?)
        $scopeFilter
      ORDER BY s.class_name COLLATE NOCASE, s.first_name COLLATE NOCASE,
               s.last_name COLLATE NOCASE
      ''', arguments);
    return rows.map(FeeCharge.fromDatabaseMap).toList(growable: false);
  }

  Future<FeePayment> recordPayment({
    required FeeCharge charge,
    required double amount,
    required String paymentMethod,
    required String notes,
    required AppUser receivedBy,
  }) async {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount');
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
        SELECT f.amount_due,
          COALESCE((SELECT SUM(p.amount) FROM fee_payments p
                    WHERE p.fee_id = f.fee_id), 0)
          - COALESCE((SELECT SUM(r.amount)
                      FROM fee_payment_reversals r
                      JOIN fee_payments p ON p.payment_id = r.payment_id
                      WHERE p.fee_id = f.fee_id), 0) AS amount_paid
        FROM fee_charges f
        WHERE f.fee_id = ?
        ''',
        [charge.id],
      );
      if (rows.isEmpty) throw StateError('The fee charge no longer exists.');
      final amountDue = (rows.single['amount_due']! as num).toDouble();
      final paidBefore = (rows.single['amount_paid']! as num).toDouble();
      final balanceBefore = amountDue - paidBefore;
      if (amount > balanceBefore) {
        throw StateError(
          'Payment exceeds the remaining balance of PKR ${balanceBefore.toStringAsFixed(2)}.',
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

      return FeePayment(
        paymentId: paymentId,
        receiptNumber: receiptNumber,
        studentName: charge.studentName,
        admissionNumber: charge.admissionNumber,
        className: charge.className,
        monthKey: charge.monthKey,
        amountDue: amountDue,
        amountPaidThisReceipt: amount,
        totalPaid: paidBefore + amount,
        balance: balanceBefore - amount,
        paidAt: now,
        paymentMethod: paymentMethod,
        notes: notes.trim(),
        receivedByName: receivedBy.fullName,
        receivedByRole: receivedBy.role,
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
        'details': 'Amount: PKR ${amount.toStringAsFixed(2)}; '
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
        SELECT p.payment_id, f.fee_id, p.receipt_number, p.amount,
               p.paid_at AS event_at, p.payment_method, p.notes,
               p.received_by_name, p.received_by_role,
               CASE WHEN r.reversal_id IS NULL THEN 0 ELSE 1 END AS is_reversed,
               0 AS is_reversal, '' AS reversal_reason,
               '' AS reversed_by_name,
               f.month_key, f.amount_due, s.admission_number, s.first_name,
               s.last_name, s.class_name,
               COALESCE((SELECT SUM(p2.amount) FROM fee_payments p2
                         WHERE p2.fee_id = f.fee_id), 0)
               - COALESCE((SELECT SUM(r2.amount)
                           FROM fee_payment_reversals r2
                           JOIN fee_payments p2 ON p2.payment_id = r2.payment_id
                           WHERE p2.fee_id = f.fee_id), 0) AS total_paid
        FROM fee_payments p
        JOIN fee_charges f ON f.fee_id = p.fee_id
        JOIN students s ON s.student_id = f.student_id
        LEFT JOIN fee_payment_reversals r ON r.payment_id = p.payment_id
        WHERE f.fee_id = ?
        UNION ALL
        SELECT p.payment_id, f.fee_id,
               'REVERSAL • ' || p.receipt_number AS receipt_number,
               -r.amount AS amount, r.reversed_at AS event_at,
               'Correction' AS payment_method, r.reason AS notes,
               '' AS received_by_name, '' AS received_by_role,
               1 AS is_reversed, 1 AS is_reversal, r.reason AS reversal_reason,
               r.reversed_by_name,
               f.month_key, f.amount_due, s.admission_number, s.first_name,
               s.last_name, s.class_name,
               COALESCE((SELECT SUM(p2.amount) FROM fee_payments p2
                         WHERE p2.fee_id = f.fee_id), 0)
               - COALESCE((SELECT SUM(r2.amount)
                           FROM fee_payment_reversals r2
                           JOIN fee_payments p2 ON p2.payment_id = r2.payment_id
                           WHERE p2.fee_id = f.fee_id), 0) AS total_paid
        FROM fee_payment_reversals r
        JOIN fee_payments p ON p.payment_id = r.payment_id
        JOIN fee_charges f ON f.fee_id = p.fee_id
        JOIN students s ON s.student_id = f.student_id
        WHERE f.fee_id = ?
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
