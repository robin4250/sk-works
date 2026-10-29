import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/secondary_reset_session_guard.dart';

/// Local lifetime only; every RPC still uses the server's existing protections.
class MasterDeviceSession {
  MasterDeviceSession({required this.currentSession, required Stream<AuthState> changes, this.onInvalidated}) {
    _session = currentSession();
    _identity = SecondaryResetSessionGuard.identityOf(_session);
    if (_identity == null) throw StateError('ログイン状態を確認してください。');
    var first = true;
    _subscription = changes.listen((event) {
      // The SDK replays its last state. Only the first exact Session object
      // may be a signedIn replay; any subsequent login is a new lifetime.
      final replay = first && identical(event.session, _session);
      first = false;
      if (event.event == AuthChangeEvent.signedOut ||
          (event.event == AuthChangeEvent.signedIn && !replay) ||
          SecondaryResetSessionGuard.identityOf(event.session) != _identity || !isCurrent) {
        _invalidate();
      }
    }, onError: (Object _) => _invalidate(), onDone: _invalidate);
  }
  final Session? Function() currentSession;
  final void Function()? onInvalidated;
  late final Session? _session;
  late final String? _identity;
  StreamSubscription<AuthState>? _subscription;
  bool _invalidated = false, _closed = false;
  String get actor => _session!.user.id;
  String get accessToken => _session!.accessToken;
  bool get isCurrent => !_closed && !_invalidated &&
    _session?.isExpired == false &&
    SecondaryResetSessionGuard.identityOf(currentSession()) == _identity;
  void _invalidate() {
    if (_invalidated || _closed) return;
    _invalidated = true; onInvalidated?.call();
  }
  Future<void> check() async {
    if (!isCurrent) { _invalidate(); throw StateError('ログイン状態が変わりました。画面を開き直してください。'); }
    await Future<void>.delayed(Duration.zero);
    if (!isCurrent) { _invalidate(); throw StateError('ログイン状態が変わりました。画面を開き直してください。'); }
  }
  Future<void> close() async { _closed = true; await _subscription?.cancel(); }
}


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

  MasterDeviceRepository.forTesting(this._client);

  final SupabaseClient _client;

  MasterDeviceSession beginSession({void Function()? onInvalidated}) => MasterDeviceSession(
    currentSession: () => _client.auth.currentSession, changes: _client.auth.onAuthStateChange,
    onInvalidated: onInvalidated);

  String? get currentUserId => _client.auth.currentUser?.id;

  static MasterDeviceRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return MasterDeviceRepository._(client);
  }

  Future<bool> isMasterAdmin({String? accessToken, MasterDeviceSession? session}) async {
    if (accessToken != null && accessToken.isEmpty) throw StateError('Missing captured session');
    await session?.check();
    accessToken = session?.accessToken ?? accessToken;
    final request = _client.rpc('current_master_admin_status');
    final raw = await (accessToken == null ? request : request.setHeader('Authorization', 'Bearer $accessToken'));
    await session?.check();
    if (raw is Map) {
      return raw['is_master_admin'] == true;
    }
    return false;
  }

  Future<List<MasterDeviceRecord>> loadDevices({MasterDeviceSession? session}) async {
    await session?.check();
    final request = _client.rpc('master_device_rows');
    final rows = await (session == null ? request : request.setHeader('Authorization', 'Bearer ${session.accessToken}'));
    await session?.check();
    return [
      for (final raw in (rows as List<dynamic>))
        _fromRow(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  Future<bool> lockReauthenticationRequired({MasterDeviceSession? session}) async {
    await session?.check();
    dynamic raw;
    try {
      final request = _client.rpc('master_device_lock_capability');
      raw = await (session == null ? request : request.setHeader('Authorization', 'Bearer ${session.accessToken}'));
      await session?.check();
    } on PostgrestException catch (error) {
      await session?.check();
      if (error.code == 'PGRST202') return false;
      rethrow;
    }
    if (raw is! Map || raw['protocol'] != 'sko-master-device-lock-v1' || raw['enabled'] is! bool) {
      throw StateError('端末変更の本人確認設定を確認できませんでした。');
    }
    return raw['enabled'] == true;
  }

  Future<void> setLocked({
    required String deviceId,
    required bool locked,
    String? proof,
    MasterDeviceSession? session,
  }) async {
    await session?.check();
    final request = _client.rpc(
      proof == null ? 'set_master_device_locked' : 'set_master_device_locked_with_proof',
      params: {
        'p_device_id': deviceId,
        'p_locked': locked,
        if (proof != null) 'p_proof': proof,
      },
    );
    await (session == null ? request : request.setHeader('Authorization', 'Bearer ${session.accessToken}'));
    await session?.check();
  }

  Future<void> revoke(String deviceId, {MasterDeviceSession? session}) async {
    await session?.check();
    final request = _client.rpc(
      'revoke_master_device',
      params: {'p_device_id': deviceId},
    );
    await (session == null ? request : request.setHeader('Authorization', 'Bearer ${session.accessToken}'));
    await session?.check();
  }

  Future<String?> currentStoredDeviceKey() async {
    final userId = currentUserId;
    if (userId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('sko_master_device_key_$userId');
    if (value == null || value.length < 32) return null;
    return value;
  }

  Future<Map<String, dynamic>> currentDeviceStatus(String deviceKey, {String? accessToken}) async {
    if (accessToken != null && accessToken.isEmpty) throw StateError('Missing captured session');
    final request = _client.rpc(
      'current_master_device_status',
      params: {'p_device_key': deviceKey},
    );
    final raw = await (accessToken == null ? request : request.setHeader('Authorization', 'Bearer $accessToken'));
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  Future<void> bootstrapFirstDevice({
    required String deviceKey,
    required String deviceName,
    required String deviceType,
    String? platform,
    String? accessToken,
  }) async {
    if (accessToken != null && accessToken.isEmpty) throw StateError('Missing captured session');
    final request = _client.rpc(
      'bootstrap_first_master_device',
      params: {
        'p_device_key': deviceKey,
        'p_device_name': deviceName,
        'p_device_type': deviceType,
        'p_platform': platform,
      },
    );
    await (accessToken == null ? request : request.setHeader('Authorization', 'Bearer $accessToken'));
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
