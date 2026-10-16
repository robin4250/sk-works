import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _protocol = 'sko-master-password-v1';
const _rejections = {'disabled', 'denied', 'invalid', 'expired', 'conflict', 'not_verified', 'locked'};
class MasterCredentialRejected implements Exception {
  const MasterCredentialRejected(this.status);
  final String status;
  @override String toString() => 'Master credential request rejected';
}
class MasterCredentialBinding {
  const MasterCredentialBinding(this.actor, this.sessionId, this.token, this.deviceKey);
  final String actor, sessionId, token, deviceKey;
  String get deviceFingerprint => sha256.convert(utf8.encode(deviceKey)).toString();
  bool sameAs(MasterCredentialBinding? other) => sameIdentity(other) && token == other!.token;
  bool sameIdentity(MasterCredentialBinding? other) => other != null && actor == other.actor && sessionId == other.sessionId && deviceKey == other.deviceKey;
}
class MasterCredentialStatus {
  const MasterCredentialStatus({required this.configured, required this.version});
  final bool configured;
  final int version;
}
class MasterCredentialChallenge {
  const MasterCredentialChallenge({required this.id, required this.nonce, required this.expiresAt});
  final String id, nonce;
  final DateTime expiresAt;
}
class MasterCredentialPending {
  const MasterCredentialPending({required this.actor, required this.sessionId, required this.deviceFingerprint, required this.requestId, required this.operation, required this.version});
  final String actor, sessionId, deviceFingerprint, requestId, operation;
  final int version;
  bool belongsTo(MasterCredentialBinding binding) => actor == binding.actor && sessionId == binding.sessionId && deviceFingerprint == binding.deviceFingerprint;
  Map<String, dynamic> toJson() => {'actor': actor, 'session_id': sessionId, 'device_fingerprint': deviceFingerprint, 'request_id': requestId, 'operation': operation, 'version': version};
}
abstract class MasterCredentialAccess {
  MasterCredentialBinding? get binding;
  Stream<void> get changes;
  Future<MasterCredentialStatus> read(MasterCredentialBinding binding);
  Future<MasterCredentialChallenge> begin(MasterCredentialBinding binding, MasterCredentialPending pending);
  Future<void> commit(MasterCredentialBinding binding, MasterCredentialPending pending, MasterCredentialChallenge challenge, {required String verificationPassword, required String newPassword});
  Future<bool> receipt(MasterCredentialBinding binding, MasterCredentialPending pending);
  Future<MasterCredentialPending?> pending(MasterCredentialBinding binding);
  Future<void> remember(MasterCredentialPending pending);
  Future<void> forget(MasterCredentialPending pending);
}
String newMasterCredentialRequestId() {
  final random = Random.secure(); final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
}
final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
Map<String, dynamic> _response(dynamic raw) {
  if (raw is! Map) throw const FormatException('Invalid Master response');
  final value = Map<String, dynamic>.from(raw);
  if (value['protocol'] != _protocol) throw const FormatException('Invalid Master protocol');
  if (_rejections.contains(value['status']) && value.length == 2) throw MasterCredentialRejected(value['status'] as String);
  return value;
}
bool _keys(Map<String, dynamic> value, Set<String> keys) => value.length == keys.length && value.keys.every(keys.contains);
int _version(dynamic raw) { if (raw is! int || raw < 0) throw const FormatException('Invalid credential version'); return raw; }

/// Candidate-only client: no route, provider, role, or existing credential changes.
class MasterCredentialRepository implements MasterCredentialAccess {
  MasterCredentialRepository(this.client, {required this.deviceKey});
  final SupabaseClient client;
  final String deviceKey;
  @override MasterCredentialBinding? get binding {
    final session = client.auth.currentSession;
    if (session == null || deviceKey.length < 32) return null;
    try {
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(session.accessToken.split('.')[1])))) as Map;
      final sid = claims['session_id'];
      if (sid is! String || !_uuid.hasMatch(sid)) return null;
      return MasterCredentialBinding(session.user.id, sid, session.accessToken, deviceKey);
    } catch (_) { return null; }
  }
  @override Stream<void> get changes => client.auth.onAuthStateChange.map((_) {});
  Future<Map<String, dynamic>> _rpc(String name, MasterCredentialBinding captured, Map<String, dynamic> args) async {
    if (!captured.sameAs(binding)) throw const MasterCredentialRejected('denied');
    return _response(await client.rpc(name, params: args).setHeader('Authorization', 'Bearer ${captured.token}'));
  }
  @override Future<MasterCredentialStatus> read(MasterCredentialBinding captured) async {
    final capability = await _rpc('master_password_capability', captured, {});
    if (!_keys(capability, {'protocol','enabled'}) || capability['enabled'] is! bool) throw const FormatException('Invalid Master capability');
    if (capability['enabled'] != true) throw const MasterCredentialRejected('disabled');
    final value = await _rpc('current_master_password_status', captured, {'p_device_key': captured.deviceKey});
    if (!_keys(value, {'protocol','status','configured','credential_version'}) || value['status'] != 'ready' || value['configured'] is! bool) throw const FormatException('Invalid Master status');
    return MasterCredentialStatus(configured: value['configured'] as bool, version: _version(value['credential_version']));
  }
  void _pendingBinding(MasterCredentialBinding captured, MasterCredentialPending pending) {
    if (!pending.belongsTo(captured) || !{'setup','change'}.contains(pending.operation) || pending.version < 0 || !_uuid.hasMatch(pending.requestId)) throw const MasterCredentialRejected('denied');
  }
  @override Future<MasterCredentialChallenge> begin(MasterCredentialBinding captured, MasterCredentialPending pending) async {
    _pendingBinding(captured, pending);
    final value = await _rpc('begin_master_password_operation', captured, {'p_device_key': captured.deviceKey, 'p_operation': pending.operation, 'p_expected_version': pending.version, 'p_request_id': pending.requestId});
    final id = value['challenge_id'], nonce = value['nonce'];
    final expiry = value['expires_at'] is String ? DateTime.tryParse(value['expires_at'] as String) : null;
    if (!_keys(value, {'protocol','status','operation','expected_version','request_id','challenge_id','nonce','expires_at'}) || value['status'] != 'challenge' || value['operation'] != pending.operation || value['expected_version'] != pending.version || value['request_id'] != pending.requestId || id is! String || !_uuid.hasMatch(id) || nonce is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce) || expiry == null || !expiry.isUtc || !expiry.isAfter(DateTime.now()) || expiry.difference(DateTime.now()).inSeconds > 120) throw const FormatException('Invalid Master challenge');
    return MasterCredentialChallenge(id: id, nonce: nonce, expiresAt: expiry);
  }
  void _applied(Map<String, dynamic> value, MasterCredentialPending pending) {
    if (!_keys(value, {'protocol','status','operation','request_id','credential_version','configured'}) || value['status'] != 'applied' || value['operation'] != pending.operation || value['request_id'] != pending.requestId || value['configured'] != true || _version(value['credential_version']) != pending.version + 1) throw const FormatException('Invalid Master result');
  }
  @override Future<void> commit(MasterCredentialBinding captured, MasterCredentialPending pending, MasterCredentialChallenge challenge, {required String verificationPassword, required String newPassword}) async {
    _pendingBinding(captured, pending);
    if (!challenge.expiresAt.isAfter(DateTime.now())) throw const MasterCredentialRejected('expired');
    final value = await _rpc('complete_master_password_operation', captured, {'p_device_key': captured.deviceKey, 'p_challenge_id': challenge.id, 'p_nonce': challenge.nonce, 'p_existing_password': verificationPassword, 'p_new_password': newPassword, 'p_request_id': pending.requestId});
    _applied(value, pending);
  }
  @override Future<bool> receipt(MasterCredentialBinding captured, MasterCredentialPending pending) async {
    _pendingBinding(captured, pending);
    final value = await _rpc('read_master_password_request', captured, {'p_device_key': captured.deviceKey, 'p_request_id': pending.requestId});
    if (value['request_id'] != pending.requestId) throw const FormatException('Invalid Master receipt');
    if (value['status'] == 'not_found' && _keys(value, {'protocol','status','request_id'})) return false;
    if (value['status'] != 'found' || !_keys(value, {'protocol','status','request_id','result'})) throw const FormatException('Invalid Master receipt');
    _applied(_response(value['result']), pending); return true;
  }
  // Operation metadata is memory-only; credentials and nonce are never retained.
  final Map<String, MasterCredentialPending> _pending = {};
  String _journal(String actor, String session) => '${actor}_$session';
  @override Future<void> remember(MasterCredentialPending pending) async {
    final key = _journal(pending.actor, pending.sessionId);
    final previous = _pending[key];
    if (previous != null && previous.requestId != pending.requestId) throw StateError('Unresolved Master operation');
    _pending[key] = pending;
  }
  @override Future<MasterCredentialPending?> pending(MasterCredentialBinding captured) async {
    final value = _pending[_journal(captured.actor, captured.sessionId)];
    if (value != null && !value.belongsTo(captured)) throw const FormatException('Unresolved Master operation');
    return value;
  }
  @override Future<void> forget(MasterCredentialPending pending) async {
    final key = _journal(pending.actor, pending.sessionId);
    final previous = _pending[key];
    if (previous != null && previous.requestId != pending.requestId) throw StateError('Operation identity changed');
    _pending.remove(key);
  }
}
