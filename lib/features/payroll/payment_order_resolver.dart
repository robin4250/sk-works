import '../shared/r18_defaults.dart';
import '../../domain/trade_document_terms_snapshot.dart';
import '../../domain/trade_document_form_draft.dart';
import '../shared/trade_document_attachment.dart';

/// Selects an appendix without saving or replacing a historical document.
class PaymentOrderResolver {
  const PaymentOrderResolver._();

  static TradeDocumentAttachment? resolve(Map<String, dynamic> workspace) {
    if (workspace['source_changed'] == true) {
      throw StateError('元帳票が更新されています。注文書を確認して保存し直してください。');
    }
    final saved = workspace['attachment'];
    if (saved != null) {
      final attachment = TradeDocumentAttachment.fromJson(
        Map<String, dynamic>.from(saved as Map),
      );
      if (attachment.payload['kind'] != 'order') {
        throw StateError('注文書の種類を確認できません。');
      }
      return attachment;
    }
    // A finalized document must not acquire a new historical appendix silently.
    if (workspace['source_locked'] == true) return null;
    if (workspace['source_locked'] != false ||
        workspace['source_blocked'] != false) {
      throw StateError('注文書の元帳票を確認できません。');
    }
    if (workspace['auto_generate'] == false || (workspace['template'] as Map?)?['auto_generate'] == false) return null;
    final defaults = Map<String, dynamic>.from(workspace['defaults'] as Map);
    for (final key in ['total_amount_yen', 'tax_amount_yen']) {
      final amount = defaults[key];
      if (amount is! int || amount < 0) {
        throw StateError('注文書の請負代金・消費税額を元帳票から確認できません。計算内訳を確認してください。');
      }
    }
    final payload = Map<String, dynamic>.from(defaults);
    final template = workspace['template'];
    if (template is Map) {
      for (final key in [
        'intro_text',
        'notes',
        'payment_conditions',
        'work_name',
        'work_address',
      ]) {
        final value = template[key];
        if (value is String &&
            (!{'work_name', 'work_address'}.contains(key) ||
                value.trim().isNotEmpty)) {
          payload[key] = value;
        }
      }
    }
    payload.putIfAbsent(
      'intro_text',
      () => '発注者（以下「甲」という）は、受注者（以下「乙」という）に対し、下記の通り工事を発注します。',
    );
    payload.putIfAbsent('payment_conditions', () => '工事完了確認後、乙の指定口座に振り込む。');
    payload.putIfAbsent('notes', () => '');
    final result = TradeDocumentAttachment.fromJson({
      'version': 1,
      'payload': TradeDocumentFormDraft.fromPayload(TradeDocumentTermsSnapshot.initialize(r18InitialValues(
        payload: payload,
        sourceDefaults: defaults,
        hasSavedAttachment: false,
        subjectKind: 'payment_certificate',
      )), allowAmountEditing: false, initializeDefaults: true,
        initializeExtendedFields: workspace['form_fields_schema_version'] == 2).payload,
    });
    if (result.payload['kind'] != 'order') {
      throw StateError('注文書の種類を確認できません。');
    }
    return result;
  }
}

