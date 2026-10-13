import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class UsageAnalyticsRepository {
  UsageAnalyticsRepository._(this._client);

  final SupabaseClient _client;

  static UsageAnalyticsRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return UsageAnalyticsRepository._(client);
  }

  Future<void> record({
    required String eventKey,
    String? surfaceKey,
    String? featureKey,
  }) async {
    if (_client.auth.currentUser == null) return;
    try {
      await _client.rpc(
        'record_usage_event',
        params: {
          'p_event_key': eventKey,
          'p_surface_key': surfaceKey,
          'p_feature_key': featureKey,
        },
      );
    } catch (_) {
      // Analytics must never block normal SKO operation.
    }
  }
}
