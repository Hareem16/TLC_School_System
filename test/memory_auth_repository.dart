import 'package:tlc_school_system/auth/app_user.dart';
import 'package:tlc_school_system/auth/auth_repository.dart';

class MemoryAuthRepository implements AuthRepository {
  final Map<String, AppUser> _users = {};
  final Map<String, String> _passwords = {};
  final Map<String, _MemoryAccountRequest> _requests = {};
  final List<AdminAuditRecord> _auditRecords = [];
  String? _rememberedUsername;

  @override
  Future<bool> hasAccounts() async => _users.isNotEmpty;

  @override
  Future<String?> rememberedUsername() async => _rememberedUsername;

  @override
  Future<void> rememberUsername(String? username) async {
    _rememberedUsername = username?.trim().toLowerCase();
  }

  @override
  Future<void> createInitialAdministrator({
    required String fullName,
    required String username,
    required String password,
  }) async {
    if (_users.isNotEmpty) {
      throw StateError('The initial administrator has already been created.');
    }
    final user = AppUser(
      id: 'admin-id',
      fullName: fullName.trim(),
      username: username.trim().toLowerCase(),
      role: AppRoles.administrator,
      permissions: AppRoles.defaultPermissions(AppRoles.administrator),
      isActive: true,
    );
    _users[user.username] = user;
    _passwords[user.id] = password;
  }

  @override
  Future<AppUser?> authenticate(String username, String password) async {
    final user = _users[username.trim().toLowerCase()];
    if (user == null || !user.isActive || _passwords[user.id] != password) {
      return null;
    }
    return user;
  }

  @override
  Future<void> submitAccountRequest({
    required String fullName,
    required String username,
    required String contact,
    required String requestedRole,
    required String password,
  }) async {
    final id = 'request-${_requests.length}';
    final request = AccountRequest(
      id: id,
      fullName: fullName,
      username: username.trim().toLowerCase(),
      contact: contact,
      requestedRole: requestedRole,
      createdAt: DateTime.now(),
    );
    _requests[id] = _MemoryAccountRequest(request, password);
  }

  @override
  Future<List<AccountRequest>> getPendingAccountRequests() async =>
      _requests.values.map((entry) => entry.request).toList(growable: false);

  @override
  Future<void> approveAccountRequest({
    required String requestId,
    required String reviewerUserId,
    required List<String> assignedClassSections,
    required List<String> linkedStudentIds,
  }) async {
    final reviewer = _requireAdministrator(reviewerUserId);
    final entry = _requests.remove(requestId);
    if (entry == null) throw StateError('This request is no longer pending.');
    final request = entry.request;
    final user = AppUser(
      id: request.username,
      fullName: request.fullName,
      username: request.username,
      role: request.requestedRole,
      permissions: AppRoles.defaultPermissions(request.requestedRole),
      assignedClassSections: assignedClassSections,
      linkedStudentIds: linkedStudentIds,
      isActive: true,
    );
    _users[user.username] = user;
    _passwords[user.id] = entry.password;
    _addAudit(
      reviewer,
      'Approved account request',
      request.username,
      request.requestedRole,
    );
  }

  @override
  Future<void> rejectAccountRequest({
    required String requestId,
    required String reviewerUserId,
  }) async {
    final reviewer = _requireAdministrator(reviewerUserId);
    final entry = _requests.remove(requestId);
    if (entry == null) throw StateError('This request is no longer pending.');
    _addAudit(
      reviewer,
      'Rejected account request',
      entry.request.username,
      entry.request.requestedRole,
    );
  }

  @override
  Future<List<AdminAuditRecord>> getAdminAuditRecords({
    int limit = 100,
  }) async =>
      _auditRecords.reversed.take(limit.clamp(1, 500)).toList(growable: false);

  @override
  Future<void> emergencyResetPassword({
    required AppUser actor,
    required String actorPassword,
    required String targetUserId,
    required String newPassword,
  }) async {
    final reviewer = _requireAdministrator(actor.id);
    if (_passwords[reviewer.id] != actorPassword) {
      throw StateError('The administrator password is incorrect.');
    }
    final target = _findUser(targetUserId);
    _passwords[target.id] = newPassword;
    _addAudit(
      reviewer,
      'Emergency password reset',
      target.username,
      'Password reset by an administrator.',
    );
  }

  @override
  Future<void> emergencyUnlockAccount({
    required AppUser actor,
    required String actorPassword,
    required String targetUserId,
  }) async {
    final reviewer = _requireAdministrator(actor.id);
    if (_passwords[reviewer.id] != actorPassword) {
      throw StateError('The administrator password is incorrect.');
    }
    final target = _findUser(targetUserId);
    _users[target.username] = target.copyWith(isActive: true);
    _addAudit(
      reviewer,
      'Emergency account unlock',
      target.username,
      'Account reactivated by an administrator.',
    );
  }

  @override
  Future<List<AppUser>> getUsers() async => _users.values.toList();

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
    final user = AppUser(
      id: username,
      fullName: fullName,
      username: username.toLowerCase(),
      role: role,
      permissions: permissions,
      assignedClassSections: assignedClassSections,
      linkedStudentIds: linkedStudentIds,
      isActive: true,
    );
    _users[user.username] = user;
    _passwords[user.id] = password;
  }

  @override
  Future<void> updateUser({
    required AppUser user,
    String? newPassword,
    String? actorUserId,
  }) async {
    final existing = _findUser(user.id);
    _users.remove(existing.username);
    _users[user.username] = user;
    if (newPassword != null) _passwords[user.id] = newPassword;
  }

  AppUser _requireAdministrator(String userId) {
    final user = _findUser(userId);
    if (!user.isActive || !AppRoles.fullAccessRoles.contains(user.role)) {
      throw StateError('An active administrator or principal is required.');
    }
    return user;
  }

  AppUser _findUser(String userId) {
    for (final user in _users.values) {
      if (user.id == userId) return user;
    }
    throw StateError('The user account could not be found.');
  }

  void _addAudit(AppUser actor, String action, String target, String details) {
    _auditRecords.add(
      AdminAuditRecord(
        actorName: actor.fullName,
        action: action,
        target: target,
        details: details,
        createdAt: DateTime.now(),
      ),
    );
  }
}

class _MemoryAccountRequest {
  const _MemoryAccountRequest(this.request, this.password);

  final AccountRequest request;
  final String password;
}
