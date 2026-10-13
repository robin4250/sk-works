import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class VehicleNotificationSettings {
  const VehicleNotificationSettings({
    required this.vehicleId,
    required this.canManage,
    required this.enabled,
    required this.configured,
    required this.userIds,
    required this.suggestedUserIds,
    required this.candidates,
  });

  final String vehicleId;
  final bool canManage;
  final bool enabled;
  final bool configured;
  final List<String> userIds;
  final List<String> suggestedUserIds;
  final List<Map<String, dynamic>> candidates;

  factory VehicleNotificationSettings.fromJson(Map<String, dynamic> json) {
    List<String> ids(String key) => json[key] is List
        ? (json[key] as List).whereType<String>().toList(growable: false)
        : const [];
    return VehicleNotificationSettings(
      vehicleId: json['vehicle_id']?.toString() ?? '',
      canManage: json['can_manage'] == true,
      enabled: json['enabled'] == true,
      configured: json['configured'] == true,
      userIds: ids('user_ids'),
      suggestedUserIds: ids('suggested_user_ids'),
      candidates: json['candidates'] is List
          ? (json['candidates'] as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false)
          : const [],
    );
  }

  bool validSelection(Iterable<String> selected) {
    final ids = selected.toList();
    final available = candidates.map((row) => row['user_id']).toSet();
    return ids.isNotEmpty &&
        ids.length <= 3 &&
        ids.toSet().length == ids.length &&
        ids.every(available.contains);
  }

  bool canSave(Iterable<String> selected) =>
      enabled && canManage && validSelection(selected);
}

class VehicleNotificationSettingsRepository {
  VehicleNotificationSettingsRepository._(this._client);
  final SupabaseClient _client;

  static VehicleNotificationSettingsRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return VehicleNotificationSettingsRepository._(client);
  }

  Future<VehicleNotificationSettings> load(String vehicleId) async {
    final raw = await _client.rpc(
      'get_vehicle_notification_settings',
      params: {'p_vehicle_id': vehicleId},
    );
    if (raw is! Map) throw StateError('車両管理者の設定を取得できません。');
    final settings = VehicleNotificationSettings.fromJson(
      Map<String, dynamic>.from(raw),
    );
    if (settings.vehicleId != vehicleId || !settings.canManage) {
      throw StateError('この車両の管理者設定を変更できません。');
    }
    return settings;
  }

  Future<void> save(String vehicleId, List<String> userIds) async {
    // Recheck the exact vehicle and rollout before every explicit save.
    final settings = await load(vehicleId);
    if (!settings.canSave(userIds)) {
      throw StateError('車両通知の利用状況と管理者1〜3名を確認してください。');
    }
    await _client.rpc(
      'set_vehicle_notification_assignees',
      params: {'p_vehicle_id': vehicleId, 'p_user_ids': userIds},
    );
  }
}
