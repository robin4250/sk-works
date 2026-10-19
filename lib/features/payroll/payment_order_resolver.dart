import '../shared/r18_defaults.dart';
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
    final defaults = Map<String, dynamic>.from(workspace['defaults'] as Map);
    final payload = Map<String, dynamic>.from(defaults);
    final template = workspace['template'];
    if (template is Map) {
      for (final key in ['intro_text', 'notes', 'payment_conditions']) {
        if (template[key] is String) payload[key] = template[key];
      }
    }
    payload.putIfAbsent('intro_text', () =>
      '発注者（以下「甲」という）は、受注者（以下「乙」という）に対し、下記の通り工事を発注します。');
    payload.putIfAbsent('payment_conditions', () => '工事完了確認後、乙の指定口座に振り込む。');
    payload.putIfAbsent('notes', () => '');
    final result = TradeDocumentAttachment.fromJson({
      'version': 1,
      'payload': r18InitialValues(payload: payload, sourceDefaults: defaults,
        hasSavedAttachment: false, subjectKind: 'payment_certificate'),
    });
    if (result.payload['kind'] != 'order') {
      throw StateError('注文書の種類を確認できません。');
    }
    return result;
  }
}
