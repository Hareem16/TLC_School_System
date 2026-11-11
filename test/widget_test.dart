// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tlc_school_system/main.dart';
import 'package:tlc_school_system/school_profile.dart';

import 'memory_auth_repository.dart';

void main() {
  testWidgets('mobile dashboard shows role-aware app tabs and modules', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authRepository = MemoryAuthRepository();
    await authRepository.createInitialAdministrator(
      fullName: 'Mobile Admin',
      username: 'mobile-admin',
      password: 'test-password-123',
    );
    await tester.pumpWidget(TLCSchoolApp(authRepository: authRepository));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      'mobile-admin',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      'test-password-123',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Attendance'), findsWidgets);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('School modules'), findsOneWidget);
    expect(find.text('Complaints'), findsWidgets);
    expect(find.text('Payroll'), findsWidgets);
  });

  testWidgets('first admin setup leads to login and gated dashboard', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authRepository = MemoryAuthRepository();
    await tester.pumpWidget(TLCSchoolApp(authRepository: authRepository));
    await tester.pumpAndSettle();

    expect(find.text('Create the first administrator'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('setup-full-name')),
      'School Admin',
    );
    await tester.enterText(
      find.byKey(const ValueKey('setup-username')),
      'adminuser',
    );
    await tester.enterText(
      find.byKey(const ValueKey('setup-password')),
      'test-password-123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('setup-password-confirmation')),
      'test-password-123',
    );
    await tester.tap(find.text('Create administrator'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      'adminuser',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      'test-password-123',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Admin Dashboard'), findsOneWidget);
    expect(find.text('Student overview'), findsOneWidget);
    expect(find.text('WORKSPACE'), findsOneWidget);
    expect(find.text('Master control panel'), findsOneWidget);
    expect(find.text(SchoolProfile.developerCreditText), findsOneWidget);

    await tester.tap(find.text('Students').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Import Excel'), findsOneWidget);

    await tester.tap(find.text('Dashboard').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Student overview'), findsOneWidget);

    await tester.tap(find.text('Inventory').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('INVENTORY & SUPPLIES'), findsOneWidget);
    expect(find.text('Import Excel'), findsOneWidget);
    expect(find.text('Add item'), findsOneWidget);

    await tester.tap(find.text('Teachers & Staff').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('TEACHERS & STAFF'), findsOneWidget);
    expect(find.text('Import Excel'), findsOneWidget);

    await tester.ensureVisible(find.text('Library').first);
    await tester.pump();
    await tester.tap(find.text('Library').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('LIBRARY & BOOK LISTS'), findsOneWidget);
    expect(find.text('Import Excel'), findsOneWidget);

    await tester.tap(find.text('Complaints').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Complaints Dashboard'), findsOneWidget);
    expect(find.text('Import complaint'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out').last);
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
