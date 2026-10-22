import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/company_seal_snapshot.dart';
import '../invoices/invoice_order_acceptance_pdf.dart';
import '../payroll/payment_order_pdf.dart';
import 'company_seal_pdf.dart';
import 'trade_document_attachment.dart';
import 'trade_document_confirmation_model.dart';

/// This renderer is explicitly supported; an unknown contract cannot silently
/// regenerate an opponent's mark with the company's current settings.
const tradeConfirmationRendererContract = 'company-seal-pdf@2853e2d8d530f3fc65ce74ef307a1c63b21b0496';

class TradeConfirmationPdf {
  static Map<String, dynamic> _payload(Map body, Map seal, String kind) {
    final originalSnapshot = seal['snapshot'] ?? seal['seal_snapshot'];
    final snapshot = originalSnapshot is Map ? Map<String, dynamic>.from(originalSnapshot) : originalSnapshot;
    if (snapshot is Map && snapshot['style'] == 'uploaded_png' && snapshot['png_base64'] is String) {
      // PostgreSQL's base64 transport wraps lines. Removing only CR/LF changes
      // no image bytes; the registered SHA256, CRC and dimensions remain strict.
      snapshot['png_base64'] = (snapshot['png_base64'] as String).replaceAll(RegExp(r'[\r\n]'), '');
    }
    if (seal['renderer_contract'] != tradeConfirmationRendererContract || snapshot is! Map ||
        body['kind'] != (kind == 'invoice' ? 'acceptance' : 'order') || body['issuer'] is! Map ||
        !tradeConfirmationUuid(body['issuer_company_id']) || !tradeConfirmationUuid(body['counterparty_company_id']) ||
        body['issuer_company_id'] == body['counterparty_company_id']) {
      throw const FormatException('承認済み書類の印影形式を確認できません');
    }
    final parsed = CompanySealSnapshot.fromJson(snapshot);
    if (parsed.name != (body['issuer'] as Map)['name'] || parsed.name.isEmpty ||
        parsed.companyId != null && parsed.companyId != body['issuer_company_id']) {
      throw const FormatException('書類の発行会社と登録印影が一致しません');
    }
    return {...Map<String, dynamic>.from(body), 'company_seal_snapshot': snapshot, 'company_seal_enabled': true};
  }

  static Future<Uint8List> _build(Map<String, dynamic> payload, String kind) async {
    final attachment = TradeDocumentAttachment.fromJson({'version': 1, 'payload': payload});
    final font = await CompanySealPdf.loadFont();
    final document = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
    if (kind == 'invoice') {
      await InvoiceOrderAcceptancePdf.append(document, attachment, regularFont: font, boldFont: font);
    } else if (kind == 'payment_certificate') {
      await PaymentOrderPdf.append(document, attachment, regularFont: font, boldFont: font);
    } else { throw const FormatException('書類の種類が一致しません'); }
    return document.save();
  }

  /// Own-company pre-approval display only. Callers must disable OS printing
  /// and sharing until an approved evidence response is fetched separately.
  static Future<Uint8List> ownPreview(TradeConfirmationPreview preview) {
    final e = preview.expected, d = preview.display;
    final body = d['body'] as Map, seal = d['own_seal'] as Map;
    if (body['issuer_company_id'] != e.companyId || d['body_hash'] != e.value['body_hash']) {
      throw const FormatException('確認する自社の書類が一致しません');
    }
    return _build(_payload(body, seal, e.kind), e.kind);
  }

  static TradeDocumentAttachment approvedAttachment(Map<String, dynamic> raw, Map<String, dynamic> scope,
      String actor, {bool archive = false}) {
    if (raw['contract_version'] is! int || raw['contract_version'] != 1 || raw['company_id'] != scope['p_company_id'] || raw['actor_id'] != actor ||
        raw['kind'] != scope['p_kind'] || raw['local_document_id'] != scope['p_local_document_id'] ||
        raw['document_revision'] != scope['p_document_revision'] || !tradeConfirmationUuid(raw['document_id']) ||
        raw['local_document_id'] == raw['document_id'] || raw['archive'] != archive ||
        !const {'issued', 'received'}.contains(raw['side']) || raw['evidence'] is! Map) {
      throw const FormatException('承認済み書類の対象が一致しません');
    }
    final evidence = raw['evidence'] as Map;
    if (evidence['document_id'] != raw['document_id'] || evidence['revision'] != raw['document_revision'] ||
        evidence['body'] is! Map || evidence['seals'] is! List || (evidence['seals'] as List).length != 1 ||
        evidence['consents'] is! List || (evidence['consents'] as List).length != 1 ||
        evidence['body_hash'] is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(evidence['body_hash'] as String) ||
        evidence['render_hash'] is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(evidence['render_hash'] as String)) {
      throw const FormatException('承認済み書類の証拠を確認できません');
    }
    final body = evidence['body'] as Map;
    final seal = (evidence['seals'] as List).single;
    final consent = (evidence['consents'] as List).single;
    if (seal is! Map || consent is! Map || seal['company_id'] != body['issuer_company_id'] ||
        consent['company_id'] != body['issuer_company_id'] || seal['seal_hash'] != consent['seal_hash'] ||
        seal['version_key'] != consent['version_key'] || seal['seal_hash'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(seal['seal_hash'] as String) ||
        evidence['render_seal_company_id'] != body['issuer_company_id'] ||
        evidence['transaction_id'] != body['transaction_id'] ||
        (raw['side'] == 'issued' ? body['issuer_company_id'] : body['counterparty_company_id']) != raw['company_id']) {
      throw const FormatException('発行会社の角印承認が一致しません');
    }
    final snapshot = seal['seal_snapshot'];
    if (snapshot is! Map || (snapshot['style'] == 'uploaded_png'
        ? seal['asset_hash'] != snapshot['png_sha256'] || seal['seal_version_id'] != snapshot['png_version_id'] ||
          seal['version_key'] != 'png:${snapshot['png_version_id']}'
        : seal['version_key'] != 'snapshot-v1:${seal['seal_hash']}')) {
      throw const FormatException('承認された角印の版が一致しません');
    }
    return TradeDocumentAttachment.fromJson({'version': 1, 'payload': _payload(body, seal, raw['kind'] as String)});
  }
  static Future<Uint8List> approved(Map<String, dynamic> raw, Map<String, dynamic> scope,
      String actor, {bool archive = false}) {
    final attachment = approvedAttachment(raw, scope, actor, archive: archive);
    return _build(attachment.payload, raw['kind'] as String);
  }
}
