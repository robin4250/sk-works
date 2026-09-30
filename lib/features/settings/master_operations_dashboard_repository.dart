import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class MasterOperationsDashboardRepository {
  MasterOperationsDashboardRepository._(this._client);

  final SupabaseClient _client;

  static MasterOperationsDashboardRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return MasterOperationsDashboardRepository._(client);
  }

  Future<Map<String, dynamic>> load({int usageDays = 30}) async {
    final values = await Future.wait([
      _client.rpc('current_master_admin_status'),
      _client.rpc('get_master_growth_snapshot'),
      _client.rpc('get_master_operations_snapshot'),
      _client.rpc('get_master_storage_snapshot'),
      _client.rpc('get_master_activity_snapshot'),
      _client.rpc(
        'get_master_usage_snapshot',
        params: {'p_days': usageDays},
      ),
    ]);
    final status = values[0];
    if (status is! Map || status['is_master_admin'] != true) {
      throw StateError('マスター管理者権限が必要です。');
    }
    return {
      'growth': values[1] is Map
          ? Map<String, dynamic>.from(values[1] as Map)
          : const <String, dynamic>{},
      'operations': values[2] is Map
          ? Map<String, dynamic>.from(values[2] as Map)
          : const <String, dynamic>{},
      'storage': values[3] is Map
          ? Map<String, dynamic>.from(values[3] as Map)
          : const <String, dynamic>{},
      'activity': values[4] is Map
          ? Map<String, dynamic>.from(values[4] as Map)
          : const <String, dynamic>{},
      'usage': values[5] is Map
          ? Map<String, dynamic>.from(values[5] as Map)
          : const <String, dynamic>{},
    };
  }
}
