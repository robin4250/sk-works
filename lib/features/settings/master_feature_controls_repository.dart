import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class MasterFeatureAvailability {
  const MasterFeatureAvailability({
    required this.vehicleManagement,
    required this.routeAssignment,
  });

  final bool vehicleManagement;
  final bool routeAssignment;

  factory MasterFeatureAvailability.fromJson(Map<String, dynamic> json) {
    return MasterFeatureAvailability(
      vehicleManagement: json['vehicle_management'] != false,
      routeAssignment: json['route_assignment'] != false,
    );
  }
}

class MasterFeatureControlsRepository {
  MasterFeatureControlsRepository._(this._client);

  final SupabaseClient _client;

  static MasterFeatureControlsRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return MasterFeatureControlsRepository._(client);
  }

  Future<MasterFeatureAvailability> load() async {
    final raw = await _client.rpc('current_master_feature_flags');
    if (raw is! Map) {
      throw StateError('マスター機能設定を読み込めません。');
    }
    return MasterFeatureAvailability.fromJson(
      Map<String, dynamic>.from(raw),
    );
  }

  Future<MasterFeatureAvailability> setEnabled({
    required String featureKey,
    required bool enabled,
  }) async {
    final raw = await _client.rpc(
      'set_master_feature_enabled',
      params: {
        'p_feature_key': featureKey,
        'p_enabled': enabled,
      },
    );
    if (raw is! Map) {
      throw StateError('マスター機能設定を更新できません。');
    }
    return MasterFeatureAvailability.fromJson(
      Map<String, dynamic>.from(raw),
    );
  }
}
