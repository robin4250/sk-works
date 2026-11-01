import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'employee_invite_delivery_message.dart';
import 'employee_invite_repository.dart';

class EmployeeDistributionUrlSnapshot {
  const EmployeeDistributionUrlSnapshot(this.url, this.updatedAt, this.canSave);
  final String? url;
  final String? updatedAt;
  final bool canSave;
}

/// V2 only: never falls back to the unbound legacy URL writer.
class EmployeeDistributionUrlRepository {
  EmployeeDistributionUrlRepository(this._client);
  final SupabaseClient _client;
  SharedPreferences? _preferences;
  Map<String, dynamic>? _pending;
  bool _corrupt = false;
  static final Set<String> _active = {};
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  bool get hasUnknownResult => _pending != null || _corrupt;

  static EmployeeDistributionUrlRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    return EmployeeDistributionUrlRepository(SupabaseBackend.client);
  }

  String _key(EmployeeInviteRequest request) =>
      'sko.employee_distribution_url.v2.${request.actorId}.${request.companyId}';

  Future<void> initialize(EmployeeInviteRequest request) async {
    request.check();
    _preferences = await SharedPreferences.getInstance();
    await _preferences!.reload();
    request.check();
    final saved = _preferences!.getString(_key(request));
    if (saved == null) return;
    try {
      final row = jsonDecode(saved);
      if (row is! Map || row.length != 7 || row['version'] != 2 ||
          row['actor'] != request.actorId || row['company'] != request.companyId ||
          !_uuid.hasMatch(row['operation'] as String) ||
          !_uuid.hasMatch(row['original_session'] as String) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['fingerprint'] as String) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['url_hash'] as String)) {
        throw const FormatException();
      }
      _pending = Map<String, dynamic>.from(row);
    } catch (_) {
      _corrupt = true;
    }
  }

  Future<Map<String, dynamic>> _call(
    EmployeeInviteRequest request, String command, {
    String? operation, Map<String, dynamic> payload = const {},
  }) async {
    request.check();
    // The supplied request must belong to this exact SDK's current session.
    final session = _client.auth.currentSession;
    if (session == null || session.user.id != request.actorId ||
        'Bearer ${session.accessToken}' != request.authorization) {
      throw StateError('URL設定のログイン状態を確認できません。');
    }
    final raw = await _client.rpc('employee_distribution_url_context_v2', params: {
      'p_company': request.companyId, 'p_session': request.sessionId,
      'p_command': command, 'p_operation': operation, 'p_payload': payload,
    }).setHeader('Authorization', request.authorization).retry(enabled: false);
    request.check();
    if (raw is! Map || raw['version'] != 2 || raw['actor_id'] != request.actorId ||
        raw['company_id'] != request.companyId || raw['session_id'] != request.sessionId ||
        raw['command'] != command) {
      throw StateError('URL設定の応答を確認できません。再保存せず結果を確認してください。');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<EmployeeDistributionUrlSnapshot> read(EmployeeInviteRequest request) async {
    final raw = await _call(request, 'read');
    if (raw.length != 8 || !raw.keys.toSet().containsAll({'version','actor_id','company_id','session_id','command','can_save','url','updated_at'}) || raw['can_save'] is! bool ||
        (raw['url'] != null && raw['url'] is! String) ||
        (raw['updated_at'] != null && (raw['updated_at'] is! String || DateTime.tryParse(raw['updated_at'] as String) == null))) {
      throw StateError('URL設定の保存前の値を確認できません。');
    }
    return EmployeeDistributionUrlSnapshot(
      raw['url'] as String?, raw['updated_at'] as String?, raw['can_save'] as bool,
    );
  }

  static String _newOperation() {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String _fingerprint(List<String?> values) => sha256.convert(utf8.encode(
    values.map((value) => value == null ? '-:' : '${utf8.encode(value).length}:$value').join(),
  )).toString();

  Future<String> save(EmployeeInviteRequest request,
      EmployeeDistributionUrlSnapshot before, String value) async {
    request.check();
    final url = employeeInviteTestFlightUrl(value);
    if (url == null || !before.canSave) {
      throw StateError('URLを保存できません。設定状態と参加URLを確認してください。');
    }
    if (_preferences == null) throw StateError('URL設定の準備ができていません。');
    await _preferences!.reload();
    request.check();
    final key = _key(request);
    if (hasUnknownResult || _preferences!.getString(key) != null || !_active.add(key)) {
      throw StateError('前の保存結果が未解決です。再保存せず結果を確認してください。');
    }
    try {
      final operation = _newOperation();
      _pending = {'version': 2, 'actor': request.actorId, 'company': request.companyId,
        'operation': operation, 'original_session': request.sessionId,
        'fingerprint': _fingerprint([before.url, before.updatedAt, url]),
        'url_hash': sha256.convert(utf8.encode(url)).toString()};
      // Durable lookup identity only; never persist bearer, password or URL payload.
      if (!await _preferences!.setString(key, jsonEncode(_pending))) {
        throw StateError('保存記録を作成できません。URLは送信していません。');
      }
      request.check();
      final raw = await _call(request, 'save', operation: operation, payload: {
        'before_url': before.url, 'before_updated_at': before.updatedAt, 'url': url,
      });
      return await _accept(request, raw);
    } finally {
      _active.remove(key);
    }
  }

  Future<String> inspectUnknownResult(EmployeeInviteRequest request) async {
    request.check();
    final pending = _pending;
    if (pending == null || _corrupt) throw StateError('保存記録を確認できません。');
    final raw = await _call(request, 'result', operation: pending['operation'] as String,
      payload: {'fingerprint': pending['fingerprint'],
        'original_session_id': pending['original_session']});
    if (raw['state'] == 'unobserved') {
      throw StateError('保存結果をまだ確認できません。再保存しないでください。');
    }
    return _accept(request, raw);
  }

  Future<String> _accept(EmployeeInviteRequest request, Map<String, dynamic> raw) async {
    final pending = _pending;
    final result = raw['result'];
    if (pending == null || raw.length != 10 || raw['state'] != 'committed' ||
        raw['operation_id'] != pending['operation'] ||
        raw['original_session_id'] != pending['original_session'] ||
        raw['fingerprint'] != pending['fingerprint'] || result is! Map ||
        !['saved', 'conflict'].contains(result['status']) ||
        (result['status'] == 'saved' && (result.length != 3 ||
          employeeInviteTestFlightUrl(result['url'] as String?) == null ||
          result['updated_at'] is! String ||
          sha256.convert(utf8.encode(result['url'] as String)).toString() != pending['url_hash'])) ||
        (result['status'] == 'conflict' && result.length != 1)) {
      throw StateError('保存結果が不明です。再保存しないでください。');
    }
    request.check();
    if (!await _preferences!.remove(_key(request))) {
      throw StateError('保存結果の記録を更新できません。再保存しないでください。');
    }
    request.check();
    _pending = null;
    return result['status'] as String;
  }
}
