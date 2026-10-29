import '../../domain/company_seal_snapshot.dart';
import '../../domain/trade_document_terms_snapshot.dart';
import '../shared/r18_defaults.dart';
import '../shared/trade_document_attachment.dart';

/// Read-only appendix selection; never saves or replaces a historical snapshot.
class InvoiceAcceptanceResolver {
  const InvoiceAcceptanceResolver._();

  static TradeDocumentAttachment? resolve(
    Map<String, dynamic> workspace, {
    required DateTime? issueDate,
    CompanySealSnapshot? parentSealSnapshot,
    bool? parentSealEnabled,
    // Retained for caller compatibility. Locked auto-generation is no longer
    // reported as a missing appendix or routed through a manual review notice.
    void Function()? onMissingLockedAcceptance,
  }) {
    if (workspace['source_changed'] == true) {
      throw StateError('元帳票が更新されています。注文請書を確認して保存し直してください。');
    }
    final saved = workspace['attachment'];
    if (saved != null) {
      return TradeDocumentAttachment.fromJson(
        Map<String, dynamic>.from(saved as Map),
      );
    }
    if (workspace['source_locked'] is! bool ||
        workspace['source_blocked'] != false ||
        workspace['source_changed'] != false) {
      throw StateError('注文請書の元帳票を確認できません。');
    }
    if (issueDate == null) throw StateError('請求書の発行日を確認してください。');
    final template = workspace['template'];
    if (template != null && template is! Map) {
      throw StateError('注文請書の初期設定を確認できません。');
    }
    final templateAuto = template is Map ? template['auto_generate'] : null;
    for (final value in [workspace['auto_generate'], templateAuto]) {
      if (value != null && value is! bool) {
        throw StateError('注文請書の自動生成設定を確認できません。');
      }
    }
    if (workspace['auto_generate'] == false || templateAuto == false) return null;
    if ((workspace['source_locked'] == true && parentSealSnapshot == null) ||
        ((parentSealSnapshot == null) != (parentSealEnabled == null))) {
      throw StateError('元の請求書の印影を確認できません。');
    }
    final defaults = Map<String, dynamic>.from(workspace['defaults'] as Map);
    final payload = Map<String, dynamic>.from(defaults);
    // Templates may change prose only, never parties, amounts, month or seal.
    if (template is Map) {
      for (final key in ['acceptance_text', 'notes', 'payment_conditions', 'work_name', 'work_address']) {
        if (template[key] is String) payload[key] = template[key];
      }
    }
    // The workspace supplies current-company defaults, not the frozen source
    // invoice's seal. Mirror the exact seal and enable flag used on page one.
    // A legacy parent with no seal metadata stays legacy; never opt into a new PNG.
    if (parentSealSnapshot != null) {
      if (parentSealSnapshot.companyId != null &&
          workspace['company_id'] != parentSealSnapshot.companyId) {
        throw StateError('元の請求書と印影の会社を確認してください。');
      }
      payload['company_seal_snapshot'] = _parentSealPayload(parentSealSnapshot);
      payload['company_seal_enabled'] = parentSealEnabled;
    }
    // Unsaved source defaults contain the parent invoice's date.
    payload.remove('issue_date');
    final result = r18InitialValues(
      payload: payload,
      sourceDefaults: defaults,
      hasSavedAttachment: false,
      subjectKind: 'invoice',
    );
    final text = result['acceptance_text'];
    if (text is String) {
      result['acceptance_text'] = text.replaceAll(
        '{order_date}',
        result['order_date'].toString(),
      );
    }
    return TradeDocumentAttachment.fromJson({'version': 1, 'payload': workspace['source_locked']==false?TradeDocumentTermsSnapshot.initialize(result):result});
  }

  static Map<String, dynamic>? _parentSealPayload(CompanySealSnapshot seal) {
    if (seal.style == 'legacy' && seal.name.isEmpty) return null;
    final png = seal.uploadedPng;
    final value = <String, dynamic>{
      'version': png == null ? 1 : 2,
      'style': seal.style,
      'name': seal.name,
      if (seal.companyId != null) 'company_id': seal.companyId,
      if (png != null) ...{
        'png_version_id': seal.pngVersionId,
        'png_base64': png.base64,
        'png_sha256': png.sha256,
      },
    };
    CompanySealSnapshot.fromJson(value);
    return value;
  }
}


