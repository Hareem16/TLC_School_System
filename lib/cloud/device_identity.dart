import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  final String deviceKey;
  final String deviceName;
  final String platform;

  const DeviceIdentity({
    required this.deviceKey,
    required this.deviceName,
    required this.platform,
  });
}

class DeviceIdentityService {
  DeviceIdentityService._();

  static const String _keyPreference = 'tlc_cloud_device_key';
  static const String _namePreference = 'tlc_cloud_device_name';
  static const String _platformPreference = 'tlc_cloud_device_platform';

  static Future<DeviceIdentity> getOrCreate() async {
    final preferences = await SharedPreferences.getInstance();

    final savedKey = preferences.getString(_keyPreference);
    final savedName = preferences.getString(_namePreference);
    final savedPlatform = preferences.getString(_platformPreference);

    if (savedKey != null && savedName != null && savedPlatform != null) {
      return DeviceIdentity(
        deviceKey: savedKey,
        deviceName: savedName,
        platform: savedPlatform,
      );
    }

    final deviceInfo = DeviceInfoPlugin();

    late String deviceName;
    late final String platform;

    if (Platform.isWindows) {
      final info = await deviceInfo.windowsInfo;
      platform = 'windows';

      final computerName = info.computerName.trim();
      deviceName = computerName.isEmpty
          ? 'Windows PC'
          : 'Windows PC - $computerName';
    } else if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      platform = 'android';

      final manufacturer = info.manufacturer.trim();
      final model = info.model.trim();

      deviceName = [
        manufacturer,
        model,
      ].where((part) => part.isNotEmpty).join(' ');

      if (deviceName.isEmpty) {
        deviceName = 'Android device';
      }
    } else {
      throw UnsupportedError(
        'TLC cloud device registration currently supports Windows and Android.',
      );
    }

    final deviceKey = _generateUuidV4();

    await preferences.setString(_keyPreference, deviceKey);
    await preferences.setString(_namePreference, deviceName);
    await preferences.setString(_platformPreference, platform);

    return DeviceIdentity(
      deviceKey: deviceKey,
      deviceName: deviceName,
      platform: platform,
    );
  }

  static String _generateUuidV4() {
    final random = Random.secure();

    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    // UUID version 4.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;

    // UUID variant.
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
