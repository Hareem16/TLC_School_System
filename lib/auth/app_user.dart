import 'dart:convert';

class AppUser {
  final String id;
  final String fullName;
  final String username;
  final String role;
  final List<String> permissions;
  final List<String> assignedClassSections;
  final List<String> linkedStudentIds;
  final bool isActive;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
    required this.permissions,
    this.assignedClassSections = const [],
    this.linkedStudentIds = const [],
    required this.isActive,
  });

  bool canAccess(String module) =>
      AppRoles.fullAccessRoles.contains(role) || permissions.contains(module);

  AppUser copyWith({
    String? fullName,
    String? username,
    String? role,
    List<String>? permissions,
    List<String>? assignedClassSections,
    List<String>? linkedStudentIds,
    bool? isActive,
  }) => AppUser(
    id: id,
    fullName: fullName ?? this.fullName,
    username: username ?? this.username,
    role: role ?? this.role,
    permissions: permissions ?? this.permissions,
    assignedClassSections: assignedClassSections ?? this.assignedClassSections,
    linkedStudentIds: linkedStudentIds ?? this.linkedStudentIds,
    isActive: isActive ?? this.isActive,
  );

  factory AppUser.fromDatabaseMap(Map<String, Object?> map) {
    final decodedPermissions = jsonDecode(map['permissions']! as String);
    if (decodedPermissions is! List ||
        decodedPermissions.any((item) => item is! String)) {
      throw const FormatException('Invalid account permissions in database.');
    }
    final decodedClassSections = jsonDecode(
      (map['assigned_class_sections'] as String?) ?? '[]',
    );
    final decodedStudentIds = jsonDecode(
      (map['linked_student_ids'] as String?) ?? '[]',
    );
    if (decodedClassSections is! List ||
        decodedClassSections.any((item) => item is! String) ||
        decodedStudentIds is! List ||
        decodedStudentIds.any((item) => item is! String)) {
      throw const FormatException('Invalid account scope in database.');
    }

    return AppUser(
      id: map['account_id']! as String,
      fullName: map['full_name']! as String,
      username: map['username']! as String,
      role: map['role']! as String,
      permissions: List<String>.unmodifiable(decodedPermissions.cast<String>()),
      assignedClassSections: List<String>.unmodifiable(
        decodedClassSections.cast<String>(),
      ),
      linkedStudentIds: List<String>.unmodifiable(
        decodedStudentIds.cast<String>(),
      ),
      isActive: (map['is_active']! as int) == 1,
    );
  }
}

class AppRoles {
  AppRoles._();

  static const administrator = 'Administrator';
  static const principal = 'Principal';
  static const teacher = 'Teacher';
  static const frontDeskOfficer = 'Front Desk Officer';
  static const parent = 'Parent / Guardian';
  static const student = 'Student';

  static const fullAccessRoles = [administrator, principal];

  static const all = [
    administrator,
    principal,
    teacher,
    frontDeskOfficer,
    parent,
    student,
  ];

  static const requestableRoles = [teacher, frontDeskOfficer, parent, student];

  static const modules = [
    'Dashboard',
    'Students',
    'Teachers & Staff',
    'Payroll',
    'Attendance',
    'Time-Table',
    'Examinations',
    'Results & Report Cards',
    'Fees & Vouchers',
    'Siblings & Families',
    'Inventory',
    'Library',
    'Question Paper Maker',
    'ECE Activities',
    'Notices',
    'Complaints',
    'Reports',
    'School Profile & Settings',
    'Users & Roles',
  ];

  static List<String> defaultPermissions(String role) => switch (role) {
    administrator || principal => modules,
    teacher => [
      'Dashboard',
      'Students',
      'Attendance',
      'Time-Table',
      'Examinations',
      'Results & Report Cards',
      'Notices',
    ],
    frontDeskOfficer => ['Dashboard', 'Fees & Vouchers', 'Reports'],
    parent => ['Dashboard', 'Complaints', 'Notices'],
    student => ['Dashboard'],
    _ => ['Dashboard'],
  };
}
