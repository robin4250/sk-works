import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'site_order_outgoing_journal.dart';
import 'site_order_journal_serial.dart';
import 'site_order_outgoing_consent_preview.dart';

/// Durable IDs/digest only. No document body, stamp, amount or PDF is stored.
class SiteOrderConsentReference {
  SiteOrderConsentReference({
    required this.prepare,
    required this.previewId,
    required this.operationId,
    required this.decisionId,
    required this.bodyHash,
  }) {
    if (![
          previewId,
          operationId,
          decisionId,
        ].every(SiteOrderPendingPrepare.validId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(bodyHash) ||
        {
              prepare.documentId,
              prepare.localId,
              prepare.requestId,
              previewId,
              operationId,
              decisionId,
            }.length !=
            6) {
      throw StateError('注文の確認情報を照合できません。');
    }
  }
  factory SiteOrderConsentReference.fromPreview(
    SiteOrderPendingPrepare prepare,
    SiteOrderOutgoingConsentPreview preview,
    String decisionId,
  ) {
    if (prepare.documentId != preview.documentId) {
      throw StateError('注文の確認情報が変わりました。');
    }
    return SiteOrderConsentReference(
      prepare: prepare,
      previewId: preview.previewId,
      operationId: preview.operationId,
      decisionId: decisionId,
      bodyHash: preview.bodyHash,
    );
  }
  final SiteOrderPendingPrepare prepare;
  final String previewId, operationId, decisionId, bodyHash;
  Map<String, dynamic> toJson() => {
    ...prepare.toJson(),
    'preview_id': previewId,
    'operation_id': operationId,
    'decision_id': decisionId,
    'body_hash': bodyHash,
  };
  Map<String, dynamic> command(String action) => {
    ...prepare.command(action),
    'preview_id': previewId,
    'decision_id': decisionId,
  };
  factory SiteOrderConsentReference.fromJson(Object? raw) {
    const own = {'preview_id', 'operation_id', 'decision_id', 'body_hash'};
    if (raw is! Map || raw.length != 10 || !own.every(raw.containsKey)) {
      throw StateError('保存した注文確認を照合できません。');
    }
    final data = Map<String, dynamic>.from(raw);
    final prepare = Map<String, dynamic>.from(data)
      ..removeWhere((k, _) => own.contains(k));
    if (own.any((k) => data[k] is! String)) {
      throw StateError('保存した注文確認を照合できません。');
    }
    return SiteOrderConsentReference(
      prepare: SiteOrderPendingPrepare.fromJson(prepare),
      previewId: data['preview_id'],
      operationId: data['operation_id'],
      decisionId: data['decision_id'],
      bodyHash: data['body_hash'],
    );
  }
}

/// A prepared job is not a stored original, sent order or clearable operation.
class SiteOrderConsentObservation {
  const SiteOrderConsentObservation._(this.jobId);
  final String? jobId;
  bool get observed => jobId != null;
  bool get canSend => false;
  bool get journalClearable => false;
  bool get retryAutomatically => false;
  factory SiteOrderConsentObservation.decode(
    Object? raw,
    SiteOrderConsentReference reference,
    String companyId,
  ) {
    if (raw is! Map ||
        raw['contract_version'] != 1 ||
        raw['retry_automatically'] != false ||
        raw['can_send'] != false ||
        raw['journal_clearable'] != false) {
      throw StateError('注文の結果を確認できません。再送せず状態を確認してください。');
    }
    if (raw['operation_state'] == 'decision_not_observed') {
      const keys = {
        'contract_version',
        'operation_state',
        'retry_automatically',
        'can_send',
        'journal_clearable',
        'read_only',
        'same_session',
      };
      if (raw.length != keys.length ||
          !raw.keys.every(keys.contains) ||
          raw['read_only'] != true ||
          raw['same_session'] is! bool) {
        throw StateError('注文の未確認状態を照合できません。');
      }
      return const SiteOrderConsentObservation._(null);
    }
    const keys = {
      'contract_version',
      'operation_state',
      'decision_request_id',
      'preview_id',
      'operation_id',
      'job_id',
      'company_id',
      'site_id',
      'document_id',
      'local_document_id',
      'trade_company_id',
      'request_id',
      'body_hash',
      'render_hash',
      'original_registered',
      'sent',
      'can_send',
      'journal_clearable',
      'retry_automatically',
    };
    final status =
        raw.containsKey('read_only') || raw.containsKey('same_session');
    final expected = {
      ...keys,
      if (status) ...{'read_only', 'same_session'},
    };
    final p = reference.prepare;
    if (raw.length != expected.length ||
        !raw.keys.every(expected.contains) ||
        (status &&
            (raw['read_only'] != true || raw['same_session'] is! bool)) ||
        raw['operation_state'] != 'decision_job_prepared' ||
        raw['decision_request_id'] != reference.decisionId ||
        raw['preview_id'] != reference.previewId ||
        raw['operation_id'] != reference.operationId ||
        raw['company_id'] != companyId ||
        raw['site_id'] != p.siteId ||
        raw['document_id'] != p.documentId ||
        raw['local_document_id'] != p.localId ||
        raw['trade_company_id'] != p.tradeId ||
        raw['request_id'] != p.requestId ||
        raw['body_hash'] != reference.bodyHash ||
        raw['original_registered'] != false ||
        raw['sent'] != false ||
        !SiteOrderPendingPrepare.validId(raw['job_id']) ||
        raw['render_hash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['render_hash'])) {
      throw StateError('注文の保存結果が一致しません。再送せず状態を確認してください。');
    }
    return SiteOrderConsentObservation._(raw['job_id'] as String);
  }
}

/// Append-only client quarantine. A status read never clears or rewrites IDs.
class SiteOrderConsentJournal {
  SiteOrderConsentJournal({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;
  final Future<SharedPreferences> Function() _preferences;
  String _prefix(String actor, String company, String site) {
    if (![actor, company, site].every(SiteOrderPendingPrepare.validId)) {
      throw StateError('注文の会社・本人・現場を確認できません。');
    }
    return 'sko.site_order.consent.v1.$actor.$company.$site.';
  }

  Future<T> _serial<T>(Future<T> Function() action) =>
      siteOrderJournalSerial(action);

  Future<bool> save(
    String actor,
    String company,
    SiteOrderConsentReference reference,
  ) => _serial(() async {
    final p = await _preferences();
    await p.reload();
    siteOrderDeliveryMarkers(p, actor, company, reference.prepare.siteId);
    siteOrderRequireUnrecorded(
      p,
      actor,
      company,
      reference.prepare.siteId,
      reference.prepare.requestId,
    );
    final key =
        '${_prefix(actor, company, reference.prepare.siteId)}${reference.prepare.requestId}';
    final encoded = jsonEncode(reference.toJson());
    final old = p.getString(key);
    if (old != null && old != encoded) {
      throw StateError('確認中の注文があります。保存状態を確認してください。');
    }
    if (old != null) return false;
    if (!await p.setString(key, encoded)) {
      throw StateError('注文の確認情報を保存できません。');
    }
    return true;
  });
  Future<List<SiteOrderConsentReference>> read(
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
    return List.unmodifiable(
      keys
          .map((key) {
            final reference = SiteOrderConsentReference.fromJson(
              jsonDecode(p.getString(key)!),
            );
            if (reference.prepare.siteId != site ||
                key != '$prefix${reference.prepare.requestId}') {
              throw StateError('保存した注文確認を照合できません。');
            }
            return reference;
          })
          .where(
            (reference) => !archived.containsKey(reference.prepare.requestId),
          ),
    );
  });
}
