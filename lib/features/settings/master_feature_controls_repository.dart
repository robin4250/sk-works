import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'master_feature_availability.dart';
export 'master_feature_availability.dart';

class MasterFeatureControlsRepository {
  MasterFeatureControlsRepository._(this._client);

  final SupabaseClient _client;
  String? get actorId => _client.auth.currentUser?.id;

  static MasterFeatureControlsRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return MasterFeatureControlsRepository._(client);
  }

  static Future<MasterFeatureAvailability> loadForClient(
    SupabaseClient client,
  ) async {
    final actor = client.auth.currentUser?.id;
    if (actor == null) throw StateError('ログイン情報を確認してください。');
    final raw = await client.rpc('current_master_feature_flags');
    if (client.auth.currentUser?.id != actor ||
        raw is! Map ||
        raw['vehicle_management'] is! bool ||
        raw['route_assignment'] is! bool) {
      throw StateError('機能の利用設定を確認できません。再読み込みしてください。');
    }
    return MasterFeatureAvailability.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<MasterFeatureAvailability> load() async {
    final raw = await _client.rpc('current_master_feature_flags');
    if (raw is! Map) {
      throw StateError('マスター機能設定を読み込めません。');
    }
    return MasterFeatureAvailability.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<MasterFeatureAvailability> setEnabled({
    required String featureKey,
    required bool enabled,
  }) async {
    final raw = await _client.rpc(
      'set_master_feature_enabled',
      params: {'p_feature_key': featureKey, 'p_enabled': enabled},
    );
    if (raw is! Map) {
      throw StateError('マスター機能設定を更新できません。');
    }
    return MasterFeatureAvailability.fromJson(Map<String, dynamic>.from(raw));
  }
}
