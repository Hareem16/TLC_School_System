import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/auth/app_user.dart';
import 'package:tlc_school_system/auth/auth_repository.dart';

void main() {
  test(
    'passwords use unique salted hashes and reject incorrect passwords',
    () async {
      const password = 'school-test-password';
      final first = await PasswordHasher.create(password);
      final second = await PasswordHasher.create(password);

      expect(first.salt, isNot(second.salt));
      expect(first.hash, isNot(password));
      expect(
        await PasswordHasher.verify(
          password,
          salt: first.salt,
          expectedHash: first.hash,
        ),
        isTrue,
      );
      expect(
        await PasswordHasher.verify(
          'incorrect-password',
          salt: first.salt,
          expectedHash: first.hash,
        ),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('role templates have separate access scopes', () {
    final teacher = AppUser(
      id: 'teacher',
      fullName: 'Teacher',
      username: 'teacher',
      role: AppRoles.teacher,
      permissions: AppRoles.defaultPermissions(AppRoles.teacher),
      isActive: true,
    );
    final accountant = AppUser(
      id: 'accountant',
      fullName: 'Accountant',
      username: 'accountant',
      role: AppRoles.frontDeskOfficer,
      permissions: AppRoles.defaultPermissions(AppRoles.frontDeskOfficer),
      isActive: true,
    );

    expect(teacher.canAccess('Attendance'), isTrue);
    expect(teacher.canAccess('Fees & Vouchers'), isFalse);
    expect(accountant.canAccess('Fees & Vouchers'), isTrue);
    expect(accountant.canAccess('Attendance'), isFalse);
    expect(accountant.canAccess('Users & Roles'), isFalse);
    expect(teacher.canAccess('Complaints'), isFalse);
    expect(teacher.canAccess('Payroll'), isFalse);
    final parent = AppUser(
      id: 'parent',
      fullName: 'Parent',
      username: 'parent',
      role: AppRoles.parent,
      permissions: AppRoles.defaultPermissions(AppRoles.parent),
      isActive: true,
    );
    expect(parent.canAccess('Complaints'), isTrue);
    expect(parent.canAccess('Notices'), isTrue);
    expect(parent.canAccess('Payroll'), isFalse);
  });
}
