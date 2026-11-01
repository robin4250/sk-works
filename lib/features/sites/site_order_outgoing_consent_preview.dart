import 'dart:convert';
import 'dart:typed_data';

import '../../domain/company_seal_snapshot.dart';
import '../../domain/trade_document_terms_snapshot.dart';
import '../shared/trade_document_form_renderer.dart';

/// RAM-only rendering of an authenticated server's unsigned review envelope.
/// Parsing does not authorize consent, original registration or delivery.
class SiteOrderOutgoingConsentPreview {
  SiteOrderOutgoingConsentPreview._(
    this._payload,
    this.previewId,
    this.operationId,
    this.documentId,
    this.bodyHash,
  );

  static const rendererContract = 'sko-original-form-20261029-v1';
  final Map<String, dynamic> _payload;
  final String previewId, operationId, documentId, bodyHash;
  String get recipientCompanyId =>
      _payload['counterparty_company_id'] as String;

  factory SiteOrderOutgoingConsentPreview.fromServerEnvelope(
    Map<String, dynamic> envelope,
  ) {
    const keys = {
      'purpose',
      'preview_only',
      'can_register',
      'can_send',
      'preview_id',
      'operation_id',
      'document_id',
      'revision',
      'body_hash',
      'source_hash',
      'seal_hash',
      'renderer_contract',
      'body',
      'own_seal',
    };
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );
    final hash = RegExp(r'^[0-9a-f]{64}$');
    if (envelope.length != keys.length ||
        !envelope.keys.every(keys.contains) ||
        envelope['purpose'] != 'unsigned_review' ||
        envelope['preview_only'] != true ||
        envelope['can_register'] != false ||
        envelope['can_send'] != false ||
        envelope['revision'] != 1 ||
        envelope['renderer_contract'] != rendererContract ||
        !['preview_id', 'operation_id', 'document_id'].every(
          (key) => envelope[key] is String && uuid.hasMatch(envelope[key]),
        ) ||
        !['body_hash', 'source_hash', 'seal_hash'].every(
          (key) => envelope[key] is String && hash.hasMatch(envelope[key]),
        ) ||
        envelope['body'] is! Map ||
        envelope['own_seal'] is! Map) {
      throw const FormatException('Unsigned review envelope rejected.');
    }
    // Detach nested issuer, terms and stamp data from caller-owned RAM.
    final body = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(envelope['body'])) as Map,
    );
    final seal = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(envelope['own_seal'])) as Map,
    );
    final issuer = body['issuer_company_id'];
    if (issuer is! String ||
        !uuid.hasMatch(issuer) ||
        issuer == body['counterparty_company_id'] ||
        seal['company_id'] != issuer ||
        seal['seal_hash'] != envelope['seal_hash'] ||
        body.containsKey('company_seal_snapshot') ||
        body.containsKey('company_seal_enabled')) {
      throw const FormatException('Unsigned review issuer binding rejected.');
    }
    TradeDocumentTermsSnapshot.fromJson(body['contract_terms']);
    final snapshot = CompanySealSnapshot.fromJson(seal['seal_snapshot']);
    if (snapshot.registeredName('') != (body['issuer'] as Map?)?['name']) {
      throw const FormatException('Unsigned review issuer name rejected.');
    }
    return SiteOrderOutgoingConsentPreview._(
      {
        ...body,
        'company_seal_snapshot': seal['seal_snapshot'],
        'company_seal_enabled': true,
      },
      envelope['preview_id'] as String,
      envelope['operation_id'] as String,
      envelope['document_id'] as String,
      envelope['body_hash'] as String,
    );
  }

  /// Exact semantic comparison with the RAM input acknowledged by prepare.
  /// The server seal is checked independently and never accepted from input.
  bool matchesPreparedBody(Map<String, dynamic> input) {
    if (input.containsKey('company_seal_snapshot') ||
        input.containsKey('company_seal_enabled')) {
      return false;
    }
    Object? ordered(Object? value) {
      if (value is Map) {
        final keys = value.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: ordered(value[key])};
      }
      if (value is List) return value.map(ordered).toList(growable: false);
      return value;
    }

    final body = Map<String, dynamic>.from(_payload)
      ..remove('company_seal_snapshot')
      ..remove('company_seal_enabled');
    return jsonEncode(ordered(body)) == jsonEncode(ordered(input));
  }

  Future<Uint8List> render() => TradeDocumentFormRenderer.canonical(_payload);
}
