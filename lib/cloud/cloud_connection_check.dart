import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

class CloudConnectionCheck {
  CloudConnectionCheck._();

  /// Performs a read-only check against the Stage 1 schools table.
  static Future<void> run() async {
    final client = SupabaseService.client;

    if (client == null) {
      debugPrint(
        'CLOUD CHECK: Supabase is not initialized. '
        'Offline mode remains available.',
      );
      return;
    }

    try {
      final rows = await client.from('schools').select('id').limit(1);

      debugPrint(
        'CLOUD CHECK: Supabase request completed successfully. '
        'Visible school records: ${rows.length}.',
      );
    } catch (error, stackTrace) {
      debugPrint('CLOUD CHECK: Request could not be completed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
