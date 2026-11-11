import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../auth/app_user.dart';
import 'app_database.dart';
import 'record_id.dart';

class ComplaintRecord {
  final String id;
  final String ownerUserId;
  final String reporterName;
  final String reporterRole;
  final String contact;
  final String category;
  final String subject;
  final String description;
  final String priority;
  final String status;
  final String resolutionNotes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ComplaintRecord({
    required this.id,
    required this.ownerUserId,
    required this.reporterName,
    required this.reporterRole,
    required this.contact,
    required this.category,
    required this.subject,
    required this.description,
    required this.priority,
    required this.status,
    required this.resolutionNotes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ComplaintRecord.fromDatabaseMap(Map<String, Object?> row) =>
      ComplaintRecord(
        id: row['complaint_id']! as String,
        ownerUserId: (row['owner_user_id'] as String?) ?? '',
        reporterName: row['reporter_name']! as String,
        reporterRole: row['reporter_role']! as String,
        contact: row['contact']! as String,
        category: row['category']! as String,
        subject: row['subject']! as String,
        description: row['description']! as String,
        priority: row['priority']! as String,
        status: row['status']! as String,
        resolutionNotes: row['resolution_notes']! as String,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );

  Map<String, Object?> toTransferMap() => {
    'format': 'tlc-complaint-v1',
    'complaintId': id,
    'ownerUserId': ownerUserId,
    'reporterName': reporterName,
    'reporterRole': reporterRole,
    'contact': contact,
    'category': category,
    'subject': subject,
    'description': description,
    'priority': priority,
    'status': status,
    'resolutionNotes': resolutionNotes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class ComplaintRepository {
  final Future<Database> Function() _databaseProvider;

  ComplaintRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => AppDatabase.instance.database);

  Future<List<ComplaintRecord>> getAll({
    required AppUser currentUser,
    String search = '',
    String status = 'All statuses',
  }) async {
    final database = await _databaseProvider();
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (AppRoles.fullAccessRoles.contains(currentUser.role)) {
      // Administrators and the principal may review all complaints.
    } else if (currentUser.role == AppRoles.parent) {
      clauses.add('owner_user_id = ?');
      arguments.add(currentUser.id);
    } else {
      throw StateError('Your account cannot view complaints.');
    }
    final normalizedSearch = search.trim();
    if (normalizedSearch.isNotEmpty) {
      final query = '%$normalizedSearch%';
      clauses.add(
        '(reporter_name LIKE ? OR category LIKE ? OR subject LIKE ? OR description LIKE ?)',
      );
      arguments.addAll([query, query, query, query]);
    }
    if (status != 'All statuses') {
      clauses.add('status = ?');
      arguments.add(status);
    }
    final rows = await database.query(
      'complaints',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'created_at DESC',
    );
    return rows.map(ComplaintRecord.fromDatabaseMap).toList(growable: false);
  }

  Future<void> create({
    required AppUser currentUser,
    required String contact,
    required String category,
    required String subject,
    required String description,
    required String priority,
  }) async {
    if (currentUser.role != AppRoles.parent) {
      throw StateError('Only parent accounts may submit complaints.');
    }
    final database = await _databaseProvider();
    final now = DateTime.now().toIso8601String();
    await database.insert('complaints', {
      'complaint_id': newRecordId(),
      'owner_user_id': currentUser.id,
      'reporter_name': currentUser.fullName,
      'reporter_role': currentUser.role,
      'contact': contact.trim(),
      'category': category,
      'subject': subject.trim(),
      'description': description.trim(),
      'priority': priority,
      'status': 'Open',
      'resolution_notes': '',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateStatus({
    required AppUser currentUser,
    required String complaintId,
    required String status,
    required String resolutionNotes,
  }) async {
    if (!AppRoles.fullAccessRoles.contains(currentUser.role)) {
      throw StateError(
        'Only an administrator or principal may resolve complaints.',
      );
    }
    final database = await _databaseProvider();
    final updated = await database.update(
      'complaints',
      {
        'status': status,
        'resolution_notes': resolutionNotes.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'complaint_id = ?',
      whereArgs: [complaintId],
    );
    if (updated != 1) throw StateError('The complaint no longer exists.');
  }

  Future<String> exportSubmissionJson({
    required AppUser currentUser,
    required String complaintId,
  }) async {
    if (currentUser.role != AppRoles.parent) {
      throw StateError('Only parent accounts can export their complaint.');
    }
    final database = await _databaseProvider();
    final rows = await database.query(
      'complaints',
      where: 'complaint_id = ? AND owner_user_id = ?',
      whereArgs: [complaintId, currentUser.id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('That complaint is not available.');
    return const JsonEncoder.withIndent('  ')
        .convert(ComplaintRecord.fromDatabaseMap(rows.single).toTransferMap());
  }

  Future<void> importSubmissionJson({
    required AppUser currentUser,
    required String contents,
  }) async {
    if (!AppRoles.fullAccessRoles.contains(currentUser.role)) {
      throw StateError(
        'Only an administrator or principal can import complaints.',
      );
    }
    final value = jsonDecode(contents);
    if (value is! Map<String, dynamic> ||
        value['format'] != 'tlc-complaint-v1') {
      throw const FormatException('This is not a TLC complaint file.');
    }
    final id = value['complaintId'];
    final owner = value['ownerUserId'];
    final reporter = value['reporterName'];
    final subject = value['subject'];
    final description = value['description'];
    final createdAt = value['createdAt'];
    if ([
      id,
      owner,
      reporter,
      subject,
      description,
      createdAt,
    ].any((field) => field is! String || field.trim().isEmpty)) {
      throw const FormatException('Complaint file is missing required fields.');
    }
    final database = await _databaseProvider();
    await database.insert('complaints', {
      'complaint_id': id,
      'owner_user_id': owner,
      'reporter_name': reporter,
      'reporter_role': (value['reporterRole'] as String?) ?? AppRoles.parent,
      'contact': (value['contact'] as String?) ?? '',
      'category': (value['category'] as String?) ?? 'Other',
      'subject': subject,
      'description': description,
      'priority': (value['priority'] as String?) ?? 'Medium',
      'status': 'Open',
      'resolution_notes': '',
      'created_at': createdAt,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<String> exportResponseJson({
    required AppUser currentUser,
    required String complaintId,
  }) async {
    if (!AppRoles.fullAccessRoles.contains(currentUser.role)) {
      throw StateError(
        'Only an administrator or principal can export responses.',
      );
    }
    final database = await _databaseProvider();
    final rows = await database.query(
      'complaints',
      columns: ['complaint_id', 'status', 'resolution_notes', 'updated_at'],
      where: 'complaint_id = ?',
      whereArgs: [complaintId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('That complaint is not available.');
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'tlc-complaint-response-v1',
      'complaintId': rows.single['complaint_id'],
      'status': rows.single['status'],
      'resolutionNotes': rows.single['resolution_notes'],
      'updatedAt': rows.single['updated_at'],
    });
  }

  Future<void> importResponseJson({
    required AppUser currentUser,
    required String contents,
  }) async {
    if (currentUser.role != AppRoles.parent) {
      throw StateError('Only a parent account can import its response.');
    }
    final value = jsonDecode(contents);
    if (value is! Map<String, dynamic> ||
        value['format'] != 'tlc-complaint-response-v1' ||
        value['complaintId'] is! String ||
        value['status'] is! String ||
        value['resolutionNotes'] is! String) {
      throw const FormatException('This is not a TLC complaint response file.');
    }
    const statuses = ['Open', 'In Progress', 'Resolved', 'Closed'];
    final status = value['status'] as String;
    if (!statuses.contains(status)) {
      throw const FormatException('The response contains an unknown status.');
    }
    final database = await _databaseProvider();
    final updated = await database.update(
      'complaints',
      {
        'status': status,
        'resolution_notes': value['resolutionNotes'],
        'updated_at':
            (value['updatedAt'] as String?) ?? DateTime.now().toIso8601String(),
      },
      where: 'complaint_id = ? AND owner_user_id = ?',
      whereArgs: [value['complaintId'], currentUser.id],
    );
    if (updated != 1) {
      throw StateError('The response does not belong to this parent account.');
    }
  }
}
