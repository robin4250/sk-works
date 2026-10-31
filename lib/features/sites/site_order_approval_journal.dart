import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contains identifiers only; never a token, document body, price or seal.
/// A retained entry quarantines approval until the server's serialized barrier
/// confirms an accepted operation or permanently cancels that exact request.
class SiteOrderApprovalJournal {
  SiteOrderApprovalJournal()
    : _preferences = SharedPreferences.getInstance,
      _refusal = false,
      _recovery = false;
  SiteOrderApprovalJournal._forRefusal()
    : _preferences = SharedPreferences.getInstance,
      _refusal = true,
      _recovery = false;
  @visibleForTesting
  SiteOrderApprovalJournal.withPreferences(this._preferences)
    : _refusal = false,
      _recovery = false;
  SiteOrderApprovalJournal.forReplyRecovery()
    : _preferences = SharedPreferences.getInstance,
      _refusal = false,
      _recovery = true;
  @visibleForTesting
  SiteOrderApprovalJournal.replyRecoveryWithPreferences(this._preferences)
    : _refusal = false,
      _recovery = true;
  final bool _recovery;
  final bool _refusal;
  final Future<SharedPreferences> Function() _preferences;
  static Future<void> _tail = Future<void>.value();
  static final _uuid = RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$');

  String _key(String actor, String company, String package) {
    for (final id in [actor, company, package]) {
      if (!_uuid.hasMatch(id)) throw StateError('保存状態の識別情報を確認できません。');
    }
    return 'sko.site_order.${_recovery
        ? 'reply_recovery'
        : _refusal
        ? 'refusal'
        : 'approval'}.v1.$actor.$company.$package';
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await action());
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return done.future;
  }

  Future<Map<String, String>?> read(
    String actor,
    String company,
    String package,
  ) => _serial(() async {
    final prefs = await _preferences();
    await prefs.reload();
    final raw = prefs.getString(_key(actor, company, package));
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map ||
        value.length != (_refusal ? 2 : 3) ||
        value['package_id'] != package ||
        !(_refusal
                ? const ['package_id', 'request_id']
                : const ['package_id', 'preview_id', 'request_id'])
            .every(
              (key) =>
                  value[key] is String && _uuid.hasMatch(value[key] as String),
            )) {
      throw StateError('保存状態を確認できません。');
    }
    return Map<String, String>.from(value);
  });

  Future<void> begin(
    String actor,
    String company,
    String package,
    String preview,
    String request,
  ) => _begin(actor, company, package, preview, request);

  Future<void> _begin(
    String actor,
    String company,
    String package,
    String? preview,
    String request,
  ) => _serial(() async {
    if ((!_refusal && (preview == null || !_uuid.hasMatch(preview))) ||
        !_uuid.hasMatch(request)) {
      throw StateError('保存状態の識別情報を確認できません。');
    }
    final prefs = await _preferences();
    await prefs.reload();
    final key = _key(actor, company, package);
    if (prefs.containsKey(key)) throw StateError('前の承認結果を確認してください。');
    if (!await prefs.setString(
      key,
      jsonEncode({
        'package_id': package,
        if (!_refusal) 'preview_id': preview,
        'request_id': request,
      }),
    )) {
      throw StateError('承認前の保存状態を保持できません。');
    }
  });

  Future<void> resolve(
    String actor,
    String company,
    String package,
    String request,
  ) => _serial(() async {
    final prefs = await _preferences();
    await prefs.reload();
    final key = _key(actor, company, package), raw = prefs.getString(key);
    if (raw == null) return;
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['request_id'] != request ||
        value['package_id'] != package) {
      throw StateError('保存状態が変わりました。');
    }
    if (!await prefs.remove(key)) throw StateError('承認結果を保持できません。');
  });
}

/// Reuses the same serialized identifier-only storage, with a distinct action
/// namespace. Refusal has no fabricated preview/document or signature.
class SiteOrderRefusalJournal {
  final _journal = SiteOrderApprovalJournal._forRefusal();
  Future<Map<String, String>?> read(
    String actor,
    String company,
    String package,
  ) => _journal.read(actor, company, package);
  Future<void> begin(
    String actor,
    String company,
    String package,
    String request,
  ) => _journal._begin(actor, company, package, null, request);
  Future<void> resolve(
    String actor,
    String company,
    String package,
    String request,
  ) => _journal.resolve(actor, company, package, request);
}
