import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class MasterDeviceRecord {
  const MasterDeviceRecord({
    required this.id,
    required this.deviceName,
    required this.deviceType,
    required this.registeredAt,
    required this.isLocked,
    this.platform,
    this.lastUsedAt,
    this.revokedAt,
  });

  final String id;
  final String deviceName;
  final String deviceType;
  final String? platform;
  final DateTime registeredAt;
  final DateTime? lastUsedAt;
  final bool isLocked;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;

  String get typeLabel => switch (deviceType) {
        'iphone' => 'iPhone',
        'ipad' => 'iPad',
        'mac' => 'Mac',
        _ => 'その他',
      };
}

class MasterDeviceRepository {
  MasterDeviceRepository._(this._client);

  final SupabaseClient _client;

  static MasterDeviceRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return MasterDeviceRepository._(client);
  }

  Future<bool> isMasterAdmin() async {
    final raw = await _client.rpc('current_master_admin_status');
    if (raw is Map) {
      return raw['is_master_admin'] == true;
    }
    return false;
  }

  Future<List<MasterDeviceRecord>> loadDevices() async {
    final rows = await _client.rpc('master_device_rows');
    return [
      for (final raw in (rows as List<dynamic>))
        _fromRow(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  Future<void> setLocked({
    required String deviceId,
    required bool locked,
  }) async {
    await _client.rpc(
      'set_master_device_locked',
      params: {
        'p_device_id': deviceId,
        'p_locked': locked,
      },
    );
  }

  Future<void> revoke(String deviceId) async {
    await _client.rpc(
      'revoke_master_device',
      params: {'p_device_id': deviceId},
    );
  }

  MasterDeviceRecord _fromRow(Map<String, dynamic> row) {
    return MasterDeviceRecord(
      id: row['id']?.toString() ?? '',
      deviceName: row['device_name']?.toString() ?? '端末',
      deviceType: row['device_type']?.toString() ?? 'other',
      platform: row['platform']?.toString(),
      registeredAt:
          DateTime.tryParse(row['registered_at']?.toString() ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      lastUsedAt:
          DateTime.tryParse(row['last_used_at']?.toString() ?? '')?.toLocal(),
      isLocked: row['is_locked'] == true,
      revokedAt:
          DateTime.tryParse(row['revoked_at']?.toString() ?? '')?.toLocal(),
    );
  }
}
