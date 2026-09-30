import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'master_device_repository.dart';

class MasterRecoveryContactsState {
  const MasterRecoveryContactsState({
    required this.configured,
    this.primaryMasked,
    this.secondaryMasked,
  });

  final bool configured;
  final String? primaryMasked;
  final String? secondaryMasked;
}

class MasterRecoveryRepository {
  MasterRecoveryRepository._(this._client, this._deviceRepository);

  final SupabaseClient _client;
  final MasterDeviceRepository _deviceRepository;

  static MasterRecoveryRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    final deviceRepository = MasterDeviceRepository.maybeCreate();
    if (client.auth.currentUser == null || deviceRepository == null) return null;
    return MasterRecoveryRepository._(client, deviceRepository);
  }

  Future<MasterRecoveryContactsState> load() async {
    final raw = await _client.rpc('current_master_recovery_contacts');
    final data = raw is Map ? Map<String, dynamic>.from(raw) : const <String,dynamic>{};
    return MasterRecoveryContactsState(
      configured: data['configured'] == true,
      primaryMasked: data['primary_masked']?.toString(),
      secondaryMasked: data['secondary_masked']?.toString(),
    );
  }

  Future<MasterRecoveryContactsState> save({
    required String primaryEmail,
    required String secondaryEmail,
  }) async {
    final deviceKey = await _deviceRepository.currentStoredDeviceKey();
    if (deviceKey == null) {
      throw StateError('信頼済みMaster端末を確認できません。');
    }

    final raw = await _client.rpc(
      'set_master_recovery_contacts',
      params: {
        'p_device_key': deviceKey,
        'p_primary_email': primaryEmail.trim(),
        'p_secondary_email': secondaryEmail.trim(),
      },
    );
    final data = raw is Map ? Map<String, dynamic>.from(raw) : const <String,dynamic>{};
    return MasterRecoveryContactsState(
      configured: data['configured'] == true,
      primaryMasked: data['primary_masked']?.toString(),
      secondaryMasked: data['secondary_masked']?.toString(),
    );
  }
}
