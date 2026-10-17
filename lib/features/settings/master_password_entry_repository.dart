import 'dart:convert';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'master_credential_repository.dart';

abstract class MasterPasswordEntryAccess {
  MasterCredentialBinding? get binding;
  Stream<void> get changes;
  MasterCredentialAccess get settingsAccess;
  Future<MasterCredentialStatus> read(MasterCredentialBinding binding);
  Future<bool> biometricAvailable();
  Future<bool> biometric();
  Future<MasterCredentialChallenge> beginUnlock(MasterCredentialBinding binding, int version, String requestId);
  Future<void> verifyUnlock(MasterCredentialBinding binding, int version, String requestId, MasterCredentialChallenge challenge, String password);
}

/// Dedicated candidate only. Uses existing SDK and the new atomic server API;
/// neither shared-secondary verification nor a local boolean is an API fallback.
class MasterPasswordEntryRepository implements MasterPasswordEntryAccess {
  MasterPasswordEntryRepository(this.client, {required String deviceKey})
      : _settings = MasterCredentialRepository(client, deviceKey: deviceKey);
  final SupabaseClient client;
  final MasterCredentialRepository _settings;
  final _local = LocalAuthentication();
  @override MasterCredentialBinding? get binding => _settings.binding;
  @override Stream<void> get changes => _settings.changes;
  @override MasterCredentialAccess get settingsAccess => _settings;
  @override Future<MasterCredentialStatus> read(MasterCredentialBinding binding) async {
    final status = await _settings.read(binding);
    if (!binding.sameAs(this.binding)) throw const MasterCredentialRejected('denied');
    if (status.configured ? status.version < 1 : status.version != 0) throw const FormatException('Invalid dedicated Master state');
    return status;
  }
  @override Future<bool> biometricAvailable() async => await _local.isDeviceSupported() && await _local.canCheckBiometrics;
  @override Future<bool> biometric() => _local.authenticate(localizedReason: 'Master本人の専用認証を確認します', options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true));
  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  bool _keys(Map<String,dynamic> value, Set<String> keys) => value.length == keys.length && value.keys.every(keys.contains);
  Future<Map<String,dynamic>> _rpc(String name, MasterCredentialBinding captured, Map<String,dynamic> args) async {
    if (!captured.sameAs(binding)) throw const MasterCredentialRejected('denied');
    final raw = await client.rpc(name, params: args).setHeader('Authorization', 'Bearer ${captured.token}');
    if (!captured.sameAs(binding)) throw const MasterCredentialRejected('denied');
    if (raw is! Map) throw const FormatException('Invalid dedicated Master response');
    final value = Map<String,dynamic>.from(raw);
    if (value['protocol'] != 'sko-master-password-v1') throw const FormatException('Invalid dedicated Master protocol');
    if (_keys(value, {'protocol','status'}) && {'denied','disabled','invalid','expired','conflict','not_verified','locked'}.contains(value['status'])) throw MasterCredentialRejected(value['status'] as String);
    return value;
  }
  @override Future<MasterCredentialChallenge> beginUnlock(MasterCredentialBinding captured, int version, String requestId) async {
    if (version < 1 || !_uuid.hasMatch(requestId)) throw const MasterCredentialRejected('invalid');
    final value = await _rpc('begin_master_password_operation', captured, {'p_device_key': captured.deviceKey, 'p_operation': 'unlock', 'p_expected_version': version, 'p_request_id': requestId});
    final id = value['challenge_id'], nonce = value['nonce'];
    final expires = value['expires_at'] is String ? DateTime.tryParse(value['expires_at'] as String) : null;
    if (!_keys(value, {'protocol','status','operation','expected_version','request_id','challenge_id','nonce','expires_at'}) || value['status'] != 'challenge' || value['operation'] != 'unlock' || value['expected_version'] != version || value['request_id'] != requestId || id is! String || !_uuid.hasMatch(id) || nonce is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce) || expires == null || !expires.isUtc || !expires.isAfter(DateTime.now()) || expires.difference(DateTime.now()).inSeconds > 120) throw const FormatException('Invalid dedicated Master challenge');
    return MasterCredentialChallenge(id: id, nonce: nonce, expiresAt: expires);
  }
  @override Future<void> verifyUnlock(MasterCredentialBinding captured, int version, String requestId, MasterCredentialChallenge challenge, String password) async {
    if (!challenge.expiresAt.isAfter(DateTime.now()) || password.isEmpty || utf8.encode(password).length > 72) throw const MasterCredentialRejected('invalid');
    final value = await _rpc('verify_master_password_operation', captured, {'p_device_key': captured.deviceKey, 'p_challenge_id': challenge.id, 'p_nonce': challenge.nonce, 'p_password': password, 'p_request_id': requestId});
    if (!_keys(value, {'protocol','status','operation','request_id','credential_version','configured'}) || value['status'] != 'verified' || value['operation'] != 'unlock' || value['request_id'] != requestId || value['credential_version'] != version || value['configured'] != true) throw const FormatException('Invalid dedicated Master verification');
  }
}
