import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static const String _supabaseUrl = 'https://nkxirldkwypsrqjkcynx.supabase.co';

  // Publishable key only. Never put a service_role or secret key here.
  static const String _publishableKey =
      'sb_publishable_3x7SSwc-QLBzu6rRehcVRA_eKzxQfxf';

  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static SupabaseClient? get client {
    if (!_initialized) return null;
    return Supabase.instance.client;
  }

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        publishableKey: _publishableKey,
      );

      _initialized = true;
      debugPrint('Supabase client initialized successfully.');
    } catch (error, stackTrace) {
      // Cloud initialization must never prevent offline app startup.
      debugPrint('Supabase initialization unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
