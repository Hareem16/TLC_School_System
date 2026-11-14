import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_user.dart';
import 'device_registration.dart';
import 'supabase_service.dart';

class CloudAccountLinkResult {
  final String cloudUserId;
  final String cloudRole;
  final CloudDeviceRegistration device;

  const CloudAccountLinkResult({
    required this.cloudUserId,
    required this.cloudRole,
    required this.device,
  });
}

/// Links an approved local TLC account to a separately provisioned cloud identity.
/// Local password hashes are never read or uploaded.
class CloudAccountLinkService {
  CloudAccountLinkService._();

  static const String schoolId = 'b0d10576-b910-4cd3-8300-c1a727e9d510';

  static List<String> _allowedCloudRoles(AppUser user) {
    if (user.role == AppRoles.administrator) return const ['owner', 'admin'];
    if (user.role == AppRoles.principal) return const ['principal'];
    if (user.role == AppRoles.frontDeskOfficer) return const ['fdo'];
    if (user.role == AppRoles.teacher) {
      return const ['class_teacher', 'subject_teacher'];
    }
    if (user.role == AppRoles.parent) return const ['parent'];
    if (user.role == AppRoles.student) return const ['student'];
    return const [];
  }

  static Future<CloudAccountLinkResult> link({
    required AppUser localUser,
    required String cloudPassword,
  }) async {
    final client = SupabaseService.client;
    if (client == null) {
      throw StateError('Cloud service is unavailable. Local login still works.');
    }
    if (!localUser.isActive) throw StateError('This local school account is inactive.');

    final email = localUser.username.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw StateError('The local account must use a valid school email address.');
    }
    if (cloudPassword.isEmpty) throw StateError('Enter the cloud account password.');

    final response = await client.auth.signInWithPassword(
      email: email,
      password: cloudPassword,
    );
    final cloudUser = response.user;
    if (cloudUser == null || cloudUser.email?.toLowerCase() != email) {
      await client.auth.signOut();
      throw StateError('The cloud account email does not match this local school account.');
    }

    final membership = await client
        .from('school_memberships')
        .select('role, is_active')
        .eq('school_id', schoolId)
        .eq('user_id', cloudUser.id)
        .maybeSingle();

    if (membership == null || membership['is_active'] != true) {
      await client.auth.signOut();
      throw StateError('This cloud account has no active TLC membership. Ask the Admin to approve it.');
    }

    final cloudRole = membership['role'] as String;
    if (!_allowedCloudRoles(localUser).contains(cloudRole)) {
      await client.auth.signOut();
      throw StateError(
        'The cloud role "$cloudRole" does not match the local role '
        '"\${localUser.role}". Ask the Admin to correct the membership.',
      );
    }

    final device = await DeviceRegistrationService.registerCurrentDevice();
    return CloudAccountLinkResult(
      cloudUserId: cloudUser.id,
      cloudRole: cloudRole,
      device: device,
    );
  }

  static Future<void> disconnect() async {
    final client = SupabaseService.client;
    if (client != null) await client.auth.signOut();
  }

  static bool get isConnected => SupabaseService.client?.auth.currentUser != null;
  static String? get connectedEmail => SupabaseService.client?.auth.currentUser?.email;
}
