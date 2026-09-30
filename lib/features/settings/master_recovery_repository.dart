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

class MasterRecoveryChallengeState {
  const MasterRecoveryChallengeState({
    required this.challengeId,
    this.expiresAt,
  });

  final String challengeId;
  final DateTime? expiresAt;
}

class MasterRecoveryVerificationState {
  const MasterRecoveryVerificationState({
    required this.primaryVerified,
    required this.secondaryVerified,
    required this.complete,
  });

  final bool primaryVerified;
  final bool secondaryVerified;
  final bool complete;
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

  Future<MasterRecoveryChallengeState> startEmergencyRecovery() async {
    final response = await _client.functions.invoke(
      'send-master-recovery-codes',
      body: const <String, dynamic>{},
    );
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : const <String, dynamic>{};

    final challengeId = data['challengeId']?.toString() ?? '';
    if (challengeId.isEmpty || data['sent'] != true) {
      throw StateError('復旧メールを送信できませんでした。');
    }

    return MasterRecoveryChallengeState(
      challengeId: challengeId,
      expiresAt: DateTime.tryParse(data['expiresAt']?.toString() ?? '')?.toLocal(),
    );
  }

  Future<MasterRecoveryVerificationState> verifyRecoveryCode({
    required String challengeId,
    required String channel,
    required String code,
  }) async {
    final raw = await _client.rpc(
      'verify_master_recovery_code',
      params: {
        'p_challenge_id': challengeId,
        'p_channel': channel,
        'p_code': code.trim(),
      },
    );
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return MasterRecoveryVerificationState(
      primaryVerified: data['primary_verified'] == true,
      secondaryVerified: data['secondary_verified'] == true,
      complete: data['complete'] == true,
    );
  }

  Future<void> consumeRecoveryChallenge({
    required String challengeId,
    required String deviceName,
    required String deviceType,
    String? platform,
  }) async {
    final deviceKey = await _deviceRepository.currentStoredDeviceKey();
    if (deviceKey == null) {
      throw StateError('この端末のMaster端末キーを確認できません。');
    }

    final raw = await _client.rpc(
      'consume_master_recovery_challenge',
      params: {
        'p_challenge_id': challengeId,
        'p_device_key': deviceKey,
        'p_device_name': deviceName,
        'p_device_type': deviceType,
        'p_platform': platform,
      },
    );
    if (raw is! Map || raw['trusted'] != true) {
      throw StateError('この端末を信頼済みに登録できませんでした。');
    }
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
