import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/auth/app_user.dart';
import 'package:tlc_school_system/data/fee_repository.dart';

void main() {
  const frontDeskOfficer = AppUser(
    id: 'fdo-1',
    fullName: 'Front Desk Officer',
    username: 'fdo',
    role: AppRoles.frontDeskOfficer,
    permissions: ['Fees & Vouchers'],
    isActive: true,
  );
  const administrator = AppUser(
    id: 'admin-1',
    fullName: 'School Administrator',
    username: 'admin',
    role: AppRoles.administrator,
    permissions: AppRoles.modules,
    isActive: true,
  );

  test('only an Administrator can reverse a fee payment', () async {
    await expectLater(
      FeeRepository().reversePayment(
        paymentId: 'payment-1',
        actor: frontDeskOfficer,
        reason: 'Testing',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('a fee payment reversal requires a reason', () async {
    await expectLater(
      FeeRepository().reversePayment(
        paymentId: 'payment-1',
        actor: administrator,
        reason: '  ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
