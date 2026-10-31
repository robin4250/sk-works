import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/company_seal_snapshot.dart';
import '../../domain/trade_document_terms_snapshot.dart';
import 'site_order_outgoing_consent.dart';
import 'site_order_outgoing_execution.dart';

/// Immutable approved snapshot for inspecting existing original bytes only.
class SiteOrderOriginalReview {
  SiteOrderOriginalReview._(this.status, this.sameSession, this._body);
  final SiteOrderExecutionObservation status;
  final bool sameSession;
  final Map<String, dynamic> _body;
  Map<String, dynamic> get body =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_body)) as Map);
  factory SiteOrderOriginalReview.decode(
    Object? raw,
    SiteOrderConsentReference reference,
    String companyId, {
    required String jobId,
    required String recipientCompanyId,
  }) {
    const keys = {
      'contract_version',
      'purpose',
      'read_only',
      'same_session',
      'status',
      'evidence',
    };
    if (raw is! Map ||
        raw.length != keys.length ||
        !raw.keys.every(keys.contains) ||
        raw['contract_version'] != 1 ||
        raw['purpose'] != 'persisted_original_review' ||
        raw['read_only'] != true ||
        raw['same_session'] is! bool ||
        raw['evidence'] is! Map) {
      throw StateError('保存原本の確認情報が一致しません。');
    }
    final status = SiteOrderExecutionObservation.decode(
      raw['status'],
      reference,
      companyId,
      jobId: jobId,
      recipientCompanyId: recipientCompanyId,
    );
    final evidence = raw['evidence'] as Map;
    if (!status.originalSaved ||
        evidence['body'] is! Map ||
        evidence['seals'] is! List ||
        evidence['render_hash'] != status.renderHash ||
        evidence['render_seal_company_id'] != companyId) {
      throw StateError('保存原本と押印内容を照合できません。');
    }
    final body = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(evidence['body'])) as Map,
    );
    if (body['transaction_id'] != reference.prepare.documentId ||
        body['kind'] != 'order' ||
        body['issuer_company_id'] != companyId ||
        body['counterparty_company_id'] != recipientCompanyId ||
        body['issuer'] is! Map ||
        body['counterparty'] is! Map ||
        body.containsKey('company_seal_snapshot') ||
        body.containsKey('company_seal_enabled')) {
      throw StateError('保存原本の会社・注文が一致しません。');
    }
    final seals = (evidence['seals'] as List)
        .where((s) => s is Map && s['company_id'] == companyId)
        .toList();
    if (seals.length != 1 || seals.single['seal_snapshot'] is! Map) {
      throw StateError('保存原本の自社角印を確認できません。');
    }
    final snapshot = CompanySealSnapshot.fromJson(
      seals.single['seal_snapshot'],
    );
    if (snapshot.registeredName('') != (body['issuer'] as Map)['name']) {
      throw StateError('保存原本の自社名と角印が一致しません。');
    }
    TradeDocumentTermsSnapshot.fromJson(body['contract_terms']);
    return SiteOrderOriginalReview._(status, raw['same_session'] as bool, body);
  }
  Uint8List verifyBytes(Object? raw) {
    if (raw is! Uint8List ||
        raw.length != status.pdfByteLength ||
        raw.length < 16 ||
        raw.length > 20 * 1024 * 1024 ||
        ascii.decode(raw.sublist(0, 5), allowInvalid: true) != '%PDF-' ||
        sha256.convert(raw).toString() != status.pdfHash) {
      throw StateError('保存原本のPDFが一致しません。共有せず状態を確認してください。');
    }
    return Uint8List.fromList(raw);
  }
}
