import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_user.dart';
import '../data/app_database.dart';

abstract interface class AuthRepository {
  Future<bool> hasAccounts();

  Future<String?> rememberedUsername();

  Future<void> rememberUsername(String? username);

  Future<void> createInitialAdministrator({
    required String fullName,
    required String username,
    required String password,
  });

  Future<AppUser?> authenticate(String username, String password);

  Future<void> submitAccountRequest({
    required String fullName,
    required String username,
    required String contact,
    required String requestedRole,
    required String password,
  });

  Future<List<AccountRequest>> getPendingAccountRequests();

  Future<void> approveAccountRequest({
    required String requestId,
    required String reviewerUserId,
    required List<String> assignedClassSections,
    required List<String> linkedStudentIds,
  });

  Future<void> rejectAccountRequest({
    required String requestId,
    required String reviewerUserId,
  });

  Future<List<AdminAuditRecord>> getAdminAuditRecords({int limit = 100});

  Future<void> emergencyResetPassword({
    required AppUser actor,
    required String actorPassword,
    required String targetUserId,
    required String newPassword,
  });

  Future<void> emergencyUnlockAccount({
    required AppUser actor,
    required String actorPassword,
    required String targetUserId,
  });

  Future<List<AppUser>> getUsers();

  Future<void> createUser({
    required String fullName,
    required String username,
    required String password,
    required String role,
    required List<String> permissions,
    required List<String> assignedClassSections,
    required List<String> linkedStudentIds,
    String? actorUserId,
  });

  Future<void> updateUser({
    required AppUser user,
    String? newPassword,
    String? actorUserId,
  });
}

class AccountRequest {
  const AccountRequest({
    required this.id,
    required this.fullName,
    required this.username,
    required this.contact,
    required this.requestedRole,
    required this.createdAt,
  });

  final String id;
  final String fullName;
  final String username;
  final String contact;
  final String requestedRole;
  final DateTime createdAt;

  factory AccountRequest.fromDatabaseMap(Map<String, Object?> row) =>
      AccountRequest(
        id: row['request_id']! as String,
        fullName: row['full_name']! as String,
        username: row['username']! as String,
        contact: row['contact']! as String,
        requestedRole: row['requested_role']! as String,
        createdAt:
            DateTime.tryParse(row['created_at']! as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class AdminAuditRecord {
  const AdminAuditRecord({
    required this.actorName,
    required this.action,
    required this.target,
    required this.details,
    required this.createdAt,
  });

  final String actorName;
  final String action;
  final String target;
  final String details;
  final DateTime createdAt;

  factory AdminAuditRecord.fromDatabaseMap(Map<String, Object?> row) =>
      AdminAuditRecord(
        actorName: row['actor_name']! as String,
        action: row['action']! as String,
        target: row['target']! as String,
        details: row['details']! as String,
        createdAt:
            DateTime.tryParse(row['created_at']! as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class SqliteAuthRepository implements AuthRepository {
  SqliteAuthRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  @override
  Future<bool> hasAccounts() async {
    final db = await _database.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM user_accounts',
    );
    return (result.single['count']! as int) > 0;
  }

  @override
  Future<String?> rememberedUsername() async {
    final db = await _database.database;
    final rows = await db.query(
      'auth_preferences',
      columns: ['preference_value'],
      where: 'preference_key = ?',
      whereArgs: const ['remembered_username'],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['preference_value'] as String;
  }

  @override
  Future<void> rememberUsername(String? username) async {
    final db = await _database.database;
    final value = username?.trim().toLowerCase() ?? '';
    if (value.isEmpty) {
      await db.delete(
        'auth_preferences',
        where: 'preference_key = ?',
        whereArgs: const ['remembered_username'],
      );
      return;
    }
    await db.insert('auth_preferences', {
      'preference_key': 'remembered_username',
      'preference_value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> createInitialAdministrator({
    required String fullName,
    required String username,
    required String password,
  }) async {
    _validateIdentity(fullName, username, password);
    final db = await _database.database;
    await db.transaction((transaction) async {
      final rows = await transaction.rawQuery(
        'SELECT COUNT(*) AS count FROM user_accounts',
      );
      if ((rows.single['count']! as int) > 0) {
        throw StateError('The initial administrator has already been created.');
      }

      final credentials = await PasswordHasher.create(password);
      await transaction.insert('user_accounts', {
        'account_id': _newId(),
        'full_name': fullName.trim(),
        'username': _normalizeUsername(username),
        'password_salt': credentials.salt,
        'password_hash': credentials.hash,
        'role': AppRoles.administrator,
        'permissions': jsonEncode(
          AppRoles.defaultPermissions(AppRoles.administrator),
        ),
        'assigned_class_sections': jsonEncode(const <String>[]),
        'linked_student_ids': jsonEncode(const <String>[]),
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  @override
  Future<AppUser?> authenticate(String username, String password) async {
    final db = await _database.database;
    final rows = await db.query(
      'user_accounts',
      where: 'username = ?',
      whereArgs: [_normalizeUsername(username)],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.single;
    final matches = await PasswordHasher.verify(
      password,
      salt: row['password_salt']! as String,
      expectedHash: row['password_hash']! as String,
    );
    if (!matches || (row['is_active']! as int) != 1) return null;
    return AppUser.fromDatabaseMap(row);
  }

  @override
  Future<void> submitAccountRequest({
    required String fullName,
    required String username,
    required String contact,
    required String requestedRole,
    required String password,
  }) async {
    _validateIdentity(fullName, username, password);
    if (!AppRoles.requestableRoles.contains(requestedRole)) {
      throw ArgumentError.value(
        requestedRole,
        'requestedRole',
        'Choose a role that requires school approval.',
      );
    }
    final normalized = _normalizeUsername(username);
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      throw ArgumentError.value(
        username,
        'username',
        'Enter a valid school email address.',
      );
    }
    final credentials = await PasswordHasher.create(password);
    final db = await _database.database;
    await db.transaction((transaction) async {
      final accounts = await transaction.query(
        'user_accounts',
        columns: ['account_id'],
        where: 'username = ?',
        whereArgs: [normalized],
        limit: 1,
      );
      final requests = await transaction.query(
        'account_requests',
        columns: ['request_id'],
        where: 'username = ? AND status = ?',
        whereArgs: [normalized, 'Pending'],
        limit: 1,
      );
      if (accounts.isNotEmpty || requests.isNotEmpty) {
        throw StateError(
          'An account or pending request already uses this email.',
        );
      }
      await transaction.insert('account_requests', {
        'request_id': _newId(),
        'full_name': fullName.trim(),
        'username': normalized,
        'contact': contact.trim(),
        'requested_role': requestedRole,
        'password_salt': credentials.salt,
        'password_hash': credentials.hash,
        'status': 'Pending',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  @override
  Future<List<AccountRequest>> getPendingAccountRequests() async {
    final db = await _database.database;
    final rows = await db.query(
      'account_requests',
      where: 'status = ?',
      whereArgs: const ['Pending'],
      orderBy: 'created_at DESC',
    );
    return rows.map(AccountRequest.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<void> approveAccountRequest({
    required String requestId,
    required String reviewerUserId,
    required List<String> assignedClassSections,
    required List<String> linkedStudentIds,
  }) async {
    final db = await _database.database;
    await db.transaction((transaction) async {
      final reviewer = await _getAuthorizedReviewer(
        transaction,
        reviewerUserId,
      );
      final requests = await transaction.query(
        'account_requests',
        where: 'request_id = ? AND status = ?',
        whereArgs: [requestId, 'Pending'],
        limit: 1,
      );
      if (requests.isEmpty) {
        throw StateError('This request is no longer pending.');
      }
      final request = requests.single;
      final role = request['requested_role']! as String;
      final username = request['username']! as String;
      final salt = request['password_salt'] as String?;
      final hash = request['password_hash'] as String?;
      if (salt == null || hash == null) {
        throw StateError(
          'The request no longer has a valid password credential.',
        );
      }
      _validateAccessScope(role, assignedClassSections, linkedStudentIds);
      await transaction.insert('user_accounts', {
        'account_id': _newId(),
        'full_name': request['full_name'],
        'username': username,
        'password_salt': salt,
        'password_hash': hash,
        'role': role,
        'permissions': jsonEncode(AppRoles.defaultPermissions(role)),
        'assigned_class_sections': jsonEncode(assignedClassSections),
        'linked_student_ids': jsonEncode(linkedStudentIds),
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      await transaction.update(
        'account_requests',
        {
          'status': 'Approved',
          'password_salt': null,
          'password_hash': null,
          'reviewed_at': DateTime.now().toIso8601String(),
          'reviewer_user_id': reviewerUserId,
        },
        where: 'request_id = ? AND status = ?',
        whereArgs: [requestId, 'Pending'],
      );
      await _recordAudit(
        transaction,
        reviewerUserId,
        reviewer['full_name']! as String,
        'Approved account request',
        username,
        role,
      );
    });
  }

  @override
  Future<void> rejectAccountRequest({
    required String requestId,
    required String reviewerUserId,
  }) async {
    final db = await _database.database;
    await db.transaction((transaction) async {
      final reviewer = await _getAuthorizedReviewer(
        transaction,
        reviewerUserId,
      );
      final requests = await transaction.query(
        'account_requests',
        columns: ['username', 'requested_role'],
        where: 'request_id = ? AND status = ?',
        whereArgs: [requestId, 'Pending'],
        limit: 1,
      );
      if (requests.isEmpty) {
        throw StateError('This request is no longer pending.');
      }
      final request = requests.single;
      await transaction.update(
        'account_requests',
        {
          'status': 'Rejected',
          'password_salt': null,
          'password_hash': null,
          'reviewed_at': DateTime.now().toIso8601String(),
          'reviewer_user_id': reviewerUserId,
        },
        where: 'request_id = ? AND status = ?',
        whereArgs: [requestId, 'Pending'],
      );
      await _recordAudit(
        transaction,
        reviewerUserId,
        reviewer['full_name']! as String,
        'Rejected account request',
        request['username']! as String,
        request['requested_role']! as String,
      );
    });
  }

  @override
  Future<List<AdminAuditRecord>> getAdminAuditRecords({int limit = 100}) async {
    final db = await _database.database;
    final rows = await db.query(
      'admin_audit_logs',
      orderBy: 'created_at DESC',
      limit: limit.clamp(1, 500),
    );
    return rows.map(AdminAuditRecord.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<void> emergencyResetPassword({
    required AppUser actor,
    required String actorPassword,
    required String targetUserId,
    required String newPassword,
  }) async {
    _validatePassword(newPassword);
    final credentials = await PasswordHasher.create(newPassword);
    final db = await _database.database;
    await db.transaction((transaction) async {
      final reviewer = await _getAuthorizedReviewer(transaction, actor.id);
      if (!await PasswordHasher.verify(
        actorPassword,
        salt: reviewer['password_salt']! as String,
        expectedHash: reviewer['password_hash']! as String,
      )) {
        throw StateError('The administrator password is incorrect.');
      }
      final targets = await transaction.query(
        'user_accounts',
        columns: ['username'],
        where: 'account_id = ?',
        whereArgs: [targetUserId],
        limit: 1,
      );
      if (targets.isEmpty) {
        throw StateError('The target account could not be found.');
      }
      final updated = await transaction.update(
        'user_accounts',
        {'password_salt': credentials.salt, 'password_hash': credentials.hash},
        where: 'account_id = ?',
        whereArgs: [targetUserId],
      );
      if (updated != 1) {
        throw StateError('The target account password could not be reset.');
      }
      await _recordAudit(
        transaction,
        actor.id,
        reviewer['full_name']! as String,
        'Emergency password reset',
        targets.single['username']! as String,
        'Password reset by an administrator.',
      );
    });
  }

  @override
  Future<void> emergencyUnlockAccount({
    required AppUser actor,
    required String actorPassword,
    required String targetUserId,
  }) async {
    final db = await _database.database;
    await db.transaction((transaction) async {
      final reviewer = await _getAuthorizedReviewer(transaction, actor.id);
      if (!await PasswordHasher.verify(
        actorPassword,
        salt: reviewer['password_salt']! as String,
        expectedHash: reviewer['password_hash']! as String,
      )) {
        throw StateError('The administrator password is incorrect.');
      }
      final targets = await transaction.query(
        'user_accounts',
        columns: ['username'],
        where: 'account_id = ?',
        whereArgs: [targetUserId],
        limit: 1,
      );
      if (targets.isEmpty) {
        throw StateError('The target account could not be found.');
      }
      final updated = await transaction.update(
        'user_accounts',
        {'is_active': 1},
        where: 'account_id = ?',
        whereArgs: [targetUserId],
      );
      if (updated != 1) {
        throw StateError('The target account could not be unlocked.');
      }
      await _recordAudit(
        transaction,
        actor.id,
        reviewer['full_name']! as String,
        'Emergency account unlock',
        targets.single['username']! as String,
        'Account reactivated by an administrator.',
      );
    });
  }

  @override
  Future<List<AppUser>> getUsers() async {
    final db = await _database.database;
    final rows = await db.query(
      'user_accounts',
      orderBy: 'full_name COLLATE NOCASE',
    );
    return rows.map(AppUser.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<void> createUser({
    required String fullName,
    required String username,
    required String password,
    required String role,
    required List<String> permissions,
    required List<String> assignedClassSections,
    required List<String> linkedStudentIds,
    String? actorUserId,
  }) async {
    _validateIdentity(fullName, username, password);
    _validateRoleAndPermissions(role, permissions);
    _validateAccessScope(role, assignedClassSections, linkedStudentIds);
    final credentials = await PasswordHasher.create(password);
    final db = await _database.database;
    await db.transaction((transaction) async {
      final reviewer = actorUserId == null
          ? null
          : await _getAuthorizedReviewer(transaction, actorUserId);
      await transaction.insert('user_accounts', {
        'account_id': _newId(),
        'full_name': fullName.trim(),
        'username': _normalizeUsername(username),
        'password_salt': credentials.salt,
        'password_hash': credentials.hash,
        'role': role,
        'permissions': jsonEncode(permissions),
        'assigned_class_sections': jsonEncode(assignedClassSections),
        'linked_student_ids': jsonEncode(linkedStudentIds),
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      if (reviewer != null) {
        await _recordAudit(
          transaction,
          actorUserId!,
          reviewer['full_name']! as String,
          'Created user account',
          _normalizeUsername(username),
          role,
        );
      }
    });
  }

  @override
  Future<void> updateUser({
    required AppUser user,
    String? newPassword,
    String? actorUserId,
  }) async {
    _validateRoleAndPermissions(user.role, user.permissions);
    _validateAccessScope(
      user.role,
      user.assignedClassSections,
      user.linkedStudentIds,
    );
    _validateAccountName(user.fullName, user.username);
    if (newPassword != null && newPassword.isNotEmpty) {
      _validatePassword(newPassword);
    }
    final db = await _database.database;
    await db.transaction((transaction) async {
      final reviewer = actorUserId == null
          ? null
          : await _getAuthorizedReviewer(transaction, actorUserId);
      if (!AppRoles.fullAccessRoles.contains(user.role) || !user.isActive) {
        final administrators = await transaction.rawQuery(
          'SELECT COUNT(*) AS count FROM user_accounts '
          'WHERE role IN (?, ?) AND is_active = 1 AND account_id != ?',
          [AppRoles.administrator, AppRoles.principal, user.id],
        );
        if ((administrators.single['count']! as int) == 0) {
          throw StateError(
            'At least one active administrator or principal must remain.',
          );
        }
      }

      final data = <String, Object?>{
        'full_name': user.fullName.trim(),
        'username': _normalizeUsername(user.username),
        'role': user.role,
        'permissions': jsonEncode(user.permissions),
        'assigned_class_sections': jsonEncode(user.assignedClassSections),
        'linked_student_ids': jsonEncode(user.linkedStudentIds),
        'is_active': user.isActive ? 1 : 0,
      };
      if (newPassword != null && newPassword.isNotEmpty) {
        final credentials = await PasswordHasher.create(newPassword);
        data['password_salt'] = credentials.salt;
        data['password_hash'] = credentials.hash;
      }
      final updated = await transaction.update(
        'user_accounts',
        data,
        where: 'account_id = ?',
        whereArgs: [user.id],
      );
      if (updated != 1) {
        throw StateError('The user account could not be updated.');
      }
      if (reviewer != null) {
        await _recordAudit(
          transaction,
          actorUserId!,
          reviewer['full_name']! as String,
          'Updated user account',
          user.username,
          user.role,
        );
      }
    });
  }

  static Future<Map<String, Object?>> _getAuthorizedReviewer(
    DatabaseExecutor transaction,
    String reviewerUserId,
  ) async {
    final reviewers = await transaction.query(
      'user_accounts',
      where: 'account_id = ?',
      whereArgs: [reviewerUserId],
      limit: 1,
    );
    if (reviewers.isEmpty ||
        (reviewers.single['is_active']! as int) != 1 ||
        !AppRoles.fullAccessRoles.contains(
          reviewers.single['role']! as String,
        )) {
      throw StateError('An active administrator or principal is required.');
    }
    return reviewers.single;
  }

  static Future<void> _recordAudit(
    DatabaseExecutor transaction,
    String actorUserId,
    String actorName,
    String action,
    String target,
    String details,
  ) async {
    await transaction.insert('admin_audit_logs', {
      'log_id': _newId(),
      'actor_user_id': actorUserId,
      'actor_name': actorName,
      'action': action,
      'target': target,
      'details': details,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static void _validateIdentity(
    String fullName,
    String username,
    String password,
  ) {
    _validateAccountName(fullName, username);
    _validatePassword(password);
  }

  static void _validateAccountName(String fullName, String username) {
    if (fullName.trim().isEmpty) {
      throw ArgumentError.value(fullName, 'fullName', 'Enter a full name.');
    }
    if (_normalizeUsername(username).length < 3) {
      throw ArgumentError.value(
        username,
        'username',
        'Username must be at least 3 characters.',
      );
    }
  }

  static void _validatePassword(String password) {
    if (password.length < 10) {
      throw ArgumentError.value(
        password,
        'password',
        'Password must be at least 10 characters.',
      );
    }
  }

  static void _validateRoleAndPermissions(
    String role,
    List<String> permissions,
  ) {
    if (!AppRoles.all.contains(role)) {
      throw ArgumentError.value(role, 'role', 'Choose a supported role.');
    }
    if (permissions.any((module) => !AppRoles.modules.contains(module))) {
      throw ArgumentError.value(
        permissions,
        'permissions',
        'Permissions contain an unsupported module.',
      );
    }
    if (permissions.isEmpty) {
      throw ArgumentError.value(
        permissions,
        'permissions',
        'Select at least one module permission.',
      );
    }
    if (!AppRoles.fullAccessRoles.contains(role) &&
        permissions.contains('Users & Roles')) {
      throw ArgumentError.value(
        permissions,
        'permissions',
        'Only administrators can manage user accounts.',
      );
    }
  }

  static void _validateAccessScope(
    String role,
    List<String> assignedClassSections,
    List<String> linkedStudentIds,
  ) {
    if (role == AppRoles.teacher && assignedClassSections.isEmpty) {
      throw ArgumentError.value(
        assignedClassSections,
        'assignedClassSections',
        'Assign at least one class and section to a teacher.',
      );
    }
    if (role == AppRoles.parent && linkedStudentIds.isEmpty) {
      throw ArgumentError.value(
        linkedStudentIds,
        'linkedStudentIds',
        'Link at least one student to a parent account.',
      );
    }
    if (role == AppRoles.student && linkedStudentIds.length != 1) {
      throw ArgumentError.value(
        linkedStudentIds,
        'linkedStudentIds',
        'A student account must be linked to exactly one student record.',
      );
    }
  }

  static String _normalizeUsername(String username) =>
      username.trim().toLowerCase();

  static String _newId() => List<int>.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class PasswordCredentials {
  const PasswordCredentials({required this.salt, required this.hash});

  final String salt;
  final String hash;
}

class PasswordHasher {
  PasswordHasher._();

  static const int iterations = 600000;
  static const int _keyLength = 32;
  static const int _saltLength = 16;

  static Future<PasswordCredentials> create(String password) async {
    final random = Random.secure();
    final saltBytes = List<int>.generate(
      _saltLength,
      (_) => random.nextInt(256),
    );
    final salt = base64Encode(saltBytes);
    return PasswordCredentials(
      salt: salt,
      hash: await compute(_derivePasswordInBackground, <Object?>[
        password,
        saltBytes,
      ]),
    );
  }

  static Future<bool> verify(
    String password, {
    required String salt,
    required String expectedHash,
  }) async {
    final actual = base64Decode(
      await compute(_derivePasswordInBackground, <Object?>[
        password,
        base64Decode(salt),
      ]),
    );
    final expected = base64Decode(expectedHash);
    if (actual.length != expected.length) return false;

    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual[i] ^ expected[i];
    }
    return difference == 0;
  }
}

String _derivePasswordInBackground(List<Object?> arguments) {
  final password = arguments[0]! as String;
  final salt = arguments[1]! as List<int>;
  final key = utf8.encode(password);
  final hmac = Hmac(sha256, key);
  final block = Uint8List(salt.length + 4)..setRange(0, salt.length, salt);
  block[block.length - 1] = 1;
  var u = hmac.convert(block).bytes;
  final output = Uint8List.fromList(u);

  for (var iteration = 1; iteration < PasswordHasher.iterations; iteration++) {
    u = hmac.convert(u).bytes;
    for (var index = 0; index < output.length; index++) {
      output[index] ^= u[index];
    }
  }
  return base64Encode(output.sublist(0, PasswordHasher._keyLength));
}
