import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_identity.dart';
import 'supabase_service.dart';

class CloudDeviceRegistration {
  final String id;
  final String schoolId;
  final String userId;
  final String deviceKey;
  final String deviceName;
  final String platform;
  final String status;
  final bool alreadyRegistered;

  const CloudDeviceRegistration({
    required this.id,
    required this.schoolId,
    required this.userId,
    required this.deviceKey,
    required this.deviceName,
    required this.platform,
    required this.status,
    required this.alreadyRegistered,
  });

  factory CloudDeviceRegistration.fromMap(
    Map<String, dynamic> map, {
    required bool alreadyRegistered,
  }) {
    return CloudDeviceRegistration(
      id: map['id'] as String,
      schoolId: map['school_id'] as String,
      userId: map['user_id'] as String,
      deviceKey: map['device_key'] as String,
      deviceName: map['device_name'] as String,
      platform: map['platform'] as String,
      status: map['status'] as String,
      alreadyRegistered: alreadyRegistered,
    );
  }
}

class DeviceRegistrationService {
  DeviceRegistrationService._();

  // First configured school.
  // Later, this will come from the selected school profile.
  static const String _schoolId = 'b0d10576-b910-4cd3-8300-c1a727e9d510';

  static const String _deviceColumns =
      'id, school_id, user_id, device_key, '
      'device_name, platform, status';

  static Future<Map<String, dynamic>?> _findDevice(
    SupabaseClient client,
    String deviceKey,
  ) {
    // device_key is unique within a school.
    // Do not filter by user_id here.
    return client
        .from('registered_devices')
        .select(_deviceColumns)
        .eq('school_id', _schoolId)
        .eq('device_key', deviceKey)
        .maybeSingle();
  }

  static CloudDeviceRegistration _validateExistingDevice(
    Map<String, dynamic> existing,
    String currentUserId,
  ) {
    final registeredUserId = existing['user_id'] as String;

    if (registeredUserId != currentUserId) {
      throw StateError(
        'This device is already registered to another school account. '
        'Please contact the Admin or Principal to review the device '
        'registration.',
      );
    }

    return CloudDeviceRegistration.fromMap(existing, alreadyRegistered: true);
  }

  static Future<CloudDeviceRegistration> registerCurrentDevice() async {
    final client = SupabaseService.client;

    if (client == null) {
      throw StateError('Supabase is not initialized.');
    }

    // Require a valid Supabase sign-in session.
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('Please sign in to your approved school account first.');
    }

    // Confirm active school membership.
    final membership = await client
        .from('school_memberships')
        .select('role, is_active')
        .eq('school_id', _schoolId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (membership == null || membership['is_active'] != true) {
      throw StateError(
        'This account does not have active membership in the selected school.',
      );
    }

    // Obtain the permanent identity of this device.
    final identity = await DeviceIdentityService.getOrCreate();

    // Find the device using the school's unique device key.
    final existing = await _findDevice(client, identity.deviceKey);

    if (existing != null) {
      return _validateExistingDevice(existing, user.id);
    }

    // Register as pending.
    // This service never approves or changes device status.
    try {
      final inserted = await client
          .from('registered_devices')
          .insert({
            'school_id': _schoolId,
            'user_id': user.id,
            'device_key': identity.deviceKey,
            'device_name': identity.deviceName,
            'platform': identity.platform,
            'status': 'pending',
          })
          .select(_deviceColumns)
          .single();

      return CloudDeviceRegistration.fromMap(
        inserted,
        alreadyRegistered: false,
      );
    } on PostgrestException catch (error) {
      // Another registration may have inserted the same device
      // at almost the same time. Recheck before reporting failure.
      if (error.code != '23505') {
        rethrow;
      }

      final racedDevice = await _findDevice(client, identity.deviceKey);

      if (racedDevice == null) {
        rethrow;
      }

      return _validateExistingDevice(racedDevice, user.id);
    }
  }
}
