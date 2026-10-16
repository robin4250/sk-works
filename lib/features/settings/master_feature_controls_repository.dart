import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/operation_reauthentication_repository.dart';
import 'master_feature_availability.dart';
export 'master_feature_availability.dart';

class MasterFeatureControlsRepository {
  MasterFeatureControlsRepository._(this._client);

  MasterFeatureControlsRepository.forTesting(this._client);

  static const supportedFeatures = {
    'vehicle_management', 'route_assignment', 'traffic_nearest_station',
    'traffic_train_transfer', 'traffic_bus_stop',
  };

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

  Future<bool> reauthenticationRequired() async {
    final actor = actorId;
    if (actor == null) throw StateError('ログイン情報を確認してください。');
    final flags = await OperationReauthenticationRepository(_client).capabilities();
    if (actorId != actor) throw StateError('ログイン状態が変わりました。');
    return flags['master_feature'] == true;
  }

  Future<MasterFeatureAvailability> setEnabled({
    required String featureKey,
    required bool enabled,
    String? proof,
    String? expectedActor,
  }) async {
    final session = _client.auth.currentSession;
    final actor = actorId;
    if (session == null || actor == null || (expectedActor != null && actor != expectedActor)) {
      throw StateError('ログイン状態を確認してください。');
    }
    if (!supportedFeatures.contains(featureKey) ||
        (proof != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(proof))) {
      throw ArgumentError('対応していない機能変更です。');
    }
    // Bind this request to the captured actor even if the SDK's asynchronous
    // token lookup observes another account before dispatch. Never fall back
    // from a rejected proof operation to the legacy setter.
    final raw = await _client.rpc(
      proof == null ? 'set_master_feature_enabled' : 'set_master_feature_enabled_with_proof',
      params: {'p_feature_key': featureKey, 'p_enabled': enabled,
        if (proof != null) 'p_proof': proof},
    ).setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (actorId != actor) throw StateError('ログイン状態が変わりました。');
    if (raw is! Map) {
      throw StateError('マスター機能設定を更新できません。');
    }
    return MasterFeatureAvailability.fromJson(Map<String, dynamic>.from(raw));
  }
}
