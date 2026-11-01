import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

// One UI-isolate ordering for every outgoing journal begin/read/retirement and
// terminal cleanup. This is not a cross-isolate or database transaction lock.
Future<void> _tail = Future<void>.value();
Future<T> siteOrderJournalSerial<T>(Future<T> Function() action) {
  final result = Completer<T>();
  _tail = _tail.then((_) async {
    try {
      result.complete(await action());
    } catch (error, stack) {
      result.completeError(error, stack);
    }
  });
  return result.future;
}

String siteOrderDeliveryMarkerPrefix(
  String actor,
  String company,
  String site,
) {
  final uuid = RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$');
  if (![actor, company, site].every(uuid.hasMatch)) {
    throw StateError('注文の本人・会社・現場を確認できません。');
  }
  return 'sko.site_order.delivery_recorded.v1.$actor.$company.$site.';
}

String siteOrderDeliveryMarkerKey(
  String actor,
  String company,
  String site,
  String request,
) {
  if (!RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$')
      .hasMatch(request)) {
    throw StateError('注文の保存情報を確認できません。');
  }
  return '${siteOrderDeliveryMarkerPrefix(actor, company, site)}$request';
}

void siteOrderRequireUnrecorded(
  SharedPreferences preferences,
  String actor,
  String company,
  String site,
  String request,
) {
  if (preferences.containsKey(
    siteOrderDeliveryMarkerKey(actor, company, site, request),
  )) {
    throw StateError('この注文の共有結果は保管済みです。再送せず保存状態を確認してください。');
  }
}

const _deliveryKeys = {
  'contract_version',
  'stage',
  'actor_id',
  'company_id',
  'reference',
  'job_id',
  'render_hash',
  'recipient_company_id',
  'original_receipt_id',
  'pdf_sha256',
  'pdf_byte_length',
  'package_id',
  'recipient_approval_state',
  'device_push_confirmed',
  'observation_sha256',
};
const _referenceKeys = {
  'site_id',
  'document_id',
  'local_id',
  'trade_id',
  'request_id',
  'session_id',
  'preview_id',
  'operation_id',
  'decision_id',
  'body_hash',
};
const _prepareKeys = {
  'site_id',
  'document_id',
  'local_id',
  'trade_id',
  'request_id',
  'session_id',
};
Object? _ordered(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _ordered(value[key])};
  }
  if (value is List) {
    return value.map(_ordered).toList();
  }
  return value;
}

bool siteOrderSameJournalJson(String a, String b) {
  try {
    return jsonEncode(_ordered(jsonDecode(a))) ==
        jsonEncode(_ordered(jsonDecode(b)));
  } catch (_) {
    return false;
  }
}

String siteOrderDeliveryObservationDigest(Map<String, dynamic> value) {
  final payload = Map<String, dynamic>.from(value)
    ..remove('observation_sha256');
  return sha256.convert(utf8.encode(jsonEncode(_ordered(payload)))).toString();
}

Map<String, dynamic> siteOrderParseDeliveryMarker(
  Object? raw,
  String actor,
  String company,
  String site,
  String request,
) {
  final uuid = RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$'),
      hash = RegExp(r'^[a-f0-9]{64}$');
  if (raw is! Map ||
      raw.length != _deliveryKeys.length ||
      !raw.keys.every(_deliveryKeys.contains) ||
      raw['contract_version'] != 1 ||
      raw['stage'] != 'sender_delivery_recorded' ||
      raw['actor_id'] != actor ||
      raw['company_id'] != company ||
      raw['recipient_company_id'] == company ||
      raw['recipient_approval_state'] != 'not_checked' ||
      raw['device_push_confirmed'] != false ||
      raw['observation_sha256'] is! String ||
      raw['observation_sha256'] !=
          siteOrderDeliveryObservationDigest(Map<String, dynamic>.from(raw)) ||
      ![
        'actor_id',
        'company_id',
        'job_id',
        'recipient_company_id',
        'original_receipt_id',
        'package_id',
      ].every((key) => raw[key] is String && uuid.hasMatch(raw[key])) ||
      ![
        'render_hash',
        'pdf_sha256',
      ].every((key) => raw[key] is String && hash.hasMatch(raw[key])) ||
      raw['pdf_byte_length'] is! int ||
      raw['pdf_byte_length'] < 16 ||
      raw['pdf_byte_length'] > 20 * 1024 * 1024 ||
      raw['reference'] is! Map) {
    throw StateError('共有結果の保管記録が不明です。原記録を保持して照会してください。');
  }
  final reference = Map<String, dynamic>.from(raw['reference'] as Map);
  if (reference.length != _referenceKeys.length ||
      !reference.keys.every(_referenceKeys.contains) ||
      reference['site_id'] != site ||
      reference['request_id'] != request ||
      !_referenceKeys
          .where((key) => key != 'body_hash')
          .every(
            (key) => reference[key] is String && uuid.hasMatch(reference[key]),
          ) ||
      reference['body_hash'] is! String ||
      !hash.hasMatch(reference['body_hash']) ||
      [
            'document_id',
            'local_id',
            'request_id',
            'preview_id',
            'operation_id',
            'decision_id',
          ].map((key) => reference[key]).toSet().length !=
          6) {
    throw StateError('共有結果と元の注文確認が一致しません。');
  }
  return Map.unmodifiable({
    ...Map<String, dynamic>.from(raw),
    'reference': Map.unmodifiable(reference),
  });
}

Map<String, Map<String, dynamic>> siteOrderDeliveryMarkers(
  SharedPreferences p,
  String actor,
  String company,
  String site,
) {
  final prefix = siteOrderDeliveryMarkerPrefix(actor, company, site),
      result = <String, Map<String, dynamic>>{};
  final keys = p.getKeys().where((key) => key.startsWith(prefix)).toList()
    ..sort();
  for (final key in keys) {
    final request = key.substring(prefix.length);
    if (key != siteOrderDeliveryMarkerKey(actor, company, site, request)) {
      throw StateError('共有結果の識別情報が不明です。');
    }
    final text = p.getString(key);
    if (text == null) {
      throw StateError('共有結果の保管記録が不明です。');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw StateError('共有結果の保管記録が不明です。原記録を保持してください。');
    }
    final marker = siteOrderParseDeliveryMarker(
      decoded,
      actor,
      company,
      site,
      request,
    );
    final reference = Map<String, dynamic>.from(marker['reference'] as Map);
    final expected = {
      'sko.site_order.outgoing.v1.$actor.$company.$site.$request': jsonEncode({
        for (final k in _prepareKeys) k: reference[k],
      }),
      'sko.site_order.consent.v1.$actor.$company.$site.$request': jsonEncode(
        reference,
      ),
    };
    for (final e in expected.entries) {
      final value = p.getString(e.key);
      if (value == null || !siteOrderSameJournalJson(value, e.value)) {
        throw StateError('元の注文記録が不足・不一致です。記録を保持して照会してください。');
      }
    }
    final executionPrefix =
        'sko.site_order.execution.v1.$actor.$company.$site.$request.';
    if (p.getKeys().any(
      (key) =>
          key.startsWith(executionPrefix) &&
          ![
            'original',
            'share',
          ].contains(key.substring(executionPrefix.length)),
    )) {
      throw StateError('不明な共有処理の元記録を保持しています。');
    }
    for (final stage in ['original', 'share']) {
      final key =
          'sko.site_order.execution.v1.$actor.$company.$site.$request.$stage';
      if (p.containsKey(key)) {
        final value = p.getString(key);
        if (value == null ||
            !siteOrderSameJournalJson(value, jsonEncode(reference))) {
          throw StateError('原本・共有の元記録が一致しません。');
        }
      }
    }
    result[request] = marker;
  }
  return Map.unmodifiable(result);
}
