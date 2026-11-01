import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'site_order_outgoing_consent.dart';
import 'site_order_journal_serial.dart';
import 'site_order_outgoing_journal.dart';

/// Authoritative persisted execution evidence. Consent preparation alone does
/// not establish either original storage or delivery to the recipient inbox.
class SiteOrderExecutionObservation {
  const SiteOrderExecutionObservation._({
    required this.reference,
    required this.companyId,
    required this.jobId,
    required this.renderHash,
    required this.recipientCompanyId,
    required this.originalReceiptId,
    required this.pdfHash,
    required this.pdfByteLength,
    required this.sharingState,
    required this.packageId,
  });
  final SiteOrderConsentReference reference;
  final String companyId;
  bool binds(SiteOrderConsentReference other, String company) =>
      companyId == company &&
      jsonEncode(reference.toJson()) == jsonEncode(other.toJson());
  final String jobId, renderHash, recipientCompanyId, sharingState;
  final String? originalReceiptId, pdfHash, packageId;
  final int? pdfByteLength;
  bool get originalSaved => originalReceiptId != null;
  bool get recipientStored => sharingState == 'recipient_stored';
  bool get unresolved => sharingState == 'unresolved';
  bool get retryAutomatically => false;
  bool get journalClearable => false;

  factory SiteOrderExecutionObservation.decode(
    Object? raw,
    SiteOrderConsentReference reference,
    String companyId, {
    required String jobId,
    required String recipientCompanyId,
  }) {
    const keys = {
      'contract_version',
      'operation_id',
      'company_id',
      'site_id',
      'document_id',
      'local_document_id',
      'trade_company_id',
      'request_id',
      'preview_id',
      'decision_id',
      'job_id',
      'body_hash',
      'render_hash',
      'original_saved',
      'original_receipt_id',
      'pdf_sha256',
      'pdf_byte_length',
      'sharing_state',
      'package_id',
      'recipient_company_id',
      'recipient_approval_state',
      'device_push_confirmed',
      'read_only',
      'retry_automatically',
      'journal_clearable',
    };
    final p = reference.prepare;
    bool hash(Object? value) =>
        value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
    if (raw is! Map ||
        raw.length != keys.length ||
        !raw.keys.every(keys.contains) ||
        raw['contract_version'] != 1 ||
        raw['operation_id'] != reference.operationId ||
        raw['company_id'] != companyId ||
        raw['site_id'] != p.siteId ||
        raw['document_id'] != p.documentId ||
        raw['local_document_id'] != p.localId ||
        raw['trade_company_id'] != p.tradeId ||
        raw['request_id'] != p.requestId ||
        raw['preview_id'] != reference.previewId ||
        raw['decision_id'] != reference.decisionId ||
        raw['body_hash'] != reference.bodyHash ||
        !SiteOrderPendingPrepare.validId(jobId) ||
        raw['job_id'] != jobId ||
        !SiteOrderPendingPrepare.validId(recipientCompanyId) ||
        raw['recipient_company_id'] != recipientCompanyId ||
        !hash(raw['render_hash']) ||
        raw['original_saved'] is! bool ||
        raw['recipient_approval_state'] != 'not_checked' ||
        raw['device_push_confirmed'] != false ||
        raw['read_only'] != true ||
        raw['retry_automatically'] != false ||
        raw['journal_clearable'] != false) {
      throw StateError('注文の保存・共有結果を照合できません。再送せず状態を確認してください。');
    }
    final saved = raw['original_saved'] == true;
    final length = raw['pdf_byte_length'];
    if (saved
        ? (!SiteOrderPendingPrepare.validId(raw['original_receipt_id']) ||
              !hash(raw['pdf_sha256']) ||
              length is! int ||
              length < 16 ||
              length > 20 * 1024 * 1024)
        : (raw['original_receipt_id'] != null ||
              raw['pdf_sha256'] != null ||
              length != null)) {
      throw StateError('保存原本の照合情報が一致しません。');
    }
    final sharing = raw['sharing_state'];
    if (!{'not_observed', 'recipient_stored', 'unresolved'}.contains(sharing) ||
        (sharing == 'recipient_stored'
            ? (!saved || !SiteOrderPendingPrepare.validId(raw['package_id']))
            : raw['package_id'] != null)) {
      throw StateError('共有結果が未解決です。再送せず状態を確認してください。');
    }
    return SiteOrderExecutionObservation._(
      reference: reference,
      companyId: companyId,
      jobId: jobId,
      renderHash: raw['render_hash'] as String,
      recipientCompanyId: recipientCompanyId,
      originalReceiptId: raw['original_receipt_id'] as String?,
      pdfHash: raw['pdf_sha256'] as String?,
      pdfByteLength: length as int?,
      sharingState: sharing as String,
      packageId: raw['package_id'] as String?,
    );
  }
}

/// Append-only mutation quarantine; reads never turn absence into retry consent.
class SiteOrderExecutionJournal {
  SiteOrderExecutionJournal({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;
  final Future<SharedPreferences> Function() _preferences;

  Future<bool> begin(
    String actorId,
    String companyId,
    SiteOrderConsentReference reference,
    String stage,
  ) => siteOrderJournalSerial(() async {
    if (![actorId, companyId].every(SiteOrderPendingPrepare.validId) ||
        !{'original', 'share'}.contains(stage)) {
      throw StateError('注文の本人・会社・保存段階を確認できません。');
    }
    final preferences = await _preferences();
    await preferences.reload();
    siteOrderDeliveryMarkers(
      preferences,
      actorId,
      companyId,
      reference.prepare.siteId,
    );
    siteOrderRequireUnrecorded(
      preferences,
      actorId,
      companyId,
      reference.prepare.siteId,
      reference.prepare.requestId,
    );
    final key =
        'sko.site_order.execution.v1.$actorId.$companyId.${reference.prepare.siteId}.${reference.prepare.requestId}.$stage';
    final encoded = jsonEncode(reference.toJson()),
        old = preferences.getString(key);
    if (old != null && old != encoded) {
      throw StateError('保存中の注文が一致しません。再送せず状態を確認してください。');
    }
    if (old != null) {
      return false;
    }
    if (!await preferences.setString(key, encoded)) {
      throw StateError('注文の照合情報を保存できません。');
    }
    return true;
  });
}
