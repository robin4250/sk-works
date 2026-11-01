import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'site_order_journal_serial.dart';

/// A request quarantine, not an editable order. Only UUIDs are durable.
class SiteOrderPendingPrepare {
  SiteOrderPendingPrepare({
    required this.siteId,
    required this.documentId,
    required this.localId,
    required this.tradeId,
    required this.requestId,
    required this.sessionId,
  }) {
    if (toJson().values.any((v) => !validId(v)) ||
        documentId == localId ||
        requestId == documentId ||
        requestId == localId) {
      throw StateError('注文の識別情報を確認できません。');
    }
  }
  final String siteId, documentId, localId, tradeId, requestId, sessionId;
  static bool validId(Object? value) =>
      value is String &&
      RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$').hasMatch(value);
  Map<String, String> toJson() => {
    'site_id': siteId,
    'document_id': documentId,
    'local_id': localId,
    'trade_id': tradeId,
    'request_id': requestId,
    'session_id': sessionId,
  };
  Map<String, String> command(String action) {
    final ids = toJson()..remove('session_id');
    return {'action': action, ...ids};
  }

  factory SiteOrderPendingPrepare.fromJson(Object? raw) {
    const keys = {
      'site_id',
      'document_id',
      'local_id',
      'trade_id',
      'request_id',
      'session_id',
    };
    if (raw is! Map ||
        raw.length != keys.length ||
        !raw.keys.every(keys.contains) ||
        raw.values.any((v) => !validId(v))) {
      throw StateError('保存された注文の識別情報を確認できません。');
    }
    return SiteOrderPendingPrepare(
      siteId: raw['site_id'] as String,
      documentId: raw['document_id'] as String,
      localId: raw['local_id'] as String,
      tradeId: raw['trade_id'] as String,
      requestId: raw['request_id'] as String,
      sessionId: raw['session_id'] as String,
    );
  }
}

class SiteOrderOutgoingJournal {
  SiteOrderOutgoingJournal({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;
  final Future<SharedPreferences> Function() _preferences;
  String _prefix(String actor, String company, String site) {
    if (![actor, company, site].every(SiteOrderPendingPrepare.validId)) {
      throw StateError('会社・本人・現場を確認できません。');
    }
    return 'sko.site_order.outgoing.v1.$actor.$company.$site.';
  }

  Future<T> _serial<T>(Future<T> Function() action) =>
      siteOrderJournalSerial(action);

  Future<List<SiteOrderPendingPrepare>> read(
    String actor,
    String company,
    String site,
  ) => _serial(() async {
    final p = await _preferences();
    await p.reload();
    final prefix = _prefix(actor, company, site);
    final archived = siteOrderDeliveryMarkers(p, actor, company, site);
    final keys = p.getKeys().where((k) => k.startsWith(prefix)).toList()
      ..sort();
    return keys
        .map((key) {
          final raw = p.getString(key);
          final entry = SiteOrderPendingPrepare.fromJson(jsonDecode(raw!));
          if (entry.siteId != site || key != '$prefix${entry.requestId}') {
            throw StateError('保存状態が変わりました。');
          }
          return entry;
        })
        .where((entry) => !archived.containsKey(entry.requestId))
        .toList(growable: false);
  });

  /// Must succeed before a future prepare request is sent. Existing quarantine
  /// cannot be overwritten or replaced with a fresh request ID.
  Future<void> begin(
    String actor,
    String company,
    SiteOrderPendingPrepare entry,
  ) => _serial(() async {
    final p = await _preferences();
    await p.reload();
    final prefix = _prefix(actor, company, entry.siteId);
    siteOrderRequireUnrecorded(
      p,
      actor,
      company,
      entry.siteId,
      entry.requestId,
    );
    final archived = siteOrderDeliveryMarkers(p, actor, company, entry.siteId);
    for (final key in p.getKeys().where((key) => key.startsWith(prefix))) {
      final existing = SiteOrderPendingPrepare.fromJson(
        jsonDecode(p.getString(key)!),
      );
      if (key != '$prefix${existing.requestId}' ||
          existing.siteId != entry.siteId ||
          !archived.containsKey(existing.requestId)) {
        throw StateError('前の注文の結果を確認してください。');
      }
    }
    if (!await p.setString(
      '$prefix${entry.requestId}',
      jsonEncode(entry.toJson()),
    )) {
      throw StateError('注文前の保存状態を保持できません。');
    }
  });
  Future<void> resolveRetired(
    String actor,
    String company,
    SiteOrderPendingPrepare entry,
  ) => _serial(() async {
    final p = await _preferences();
    await p.reload();
    siteOrderDeliveryMarkers(p, actor, company, entry.siteId);
    siteOrderRequireUnrecorded(
      p,
      actor,
      company,
      entry.siteId,
      entry.requestId,
    );
    final key = '${_prefix(actor, company, entry.siteId)}${entry.requestId}';
    final raw = p.getString(key);
    if (raw == null ||
        jsonEncode(
              SiteOrderPendingPrepare.fromJson(jsonDecode(raw)).toJson(),
            ) !=
            jsonEncode(entry.toJson())) {
      throw StateError('保存状態が変わりました。');
    }
    if (!await p.remove(key)) throw StateError('結果の保存を確認できません。');
  });
}

/// Editor contents never enter SharedPreferences. Scope retirement destroys
/// the draft; a new login cannot silently adopt the old preview or consent.
class SiteOrderRamDraft {
  Map<String, dynamic>? _body;
  bool _retired = false;
  void replace(Map<String, dynamic> body) {
    if (_retired) throw StateError('入力画面を開き直してください。');
    _body = Map<String, dynamic>.from(jsonDecode(jsonEncode(body)) as Map);
  }

  Map<String, dynamic>? get body {
    if (_retired) return null;
    return _body == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(jsonEncode(_body)) as Map);
  }

  void retire() {
    _body = null;
    _retired = true;
  }
}
