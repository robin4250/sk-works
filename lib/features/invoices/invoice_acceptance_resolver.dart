import '../shared/r18_defaults.dart';
import '../shared/trade_document_attachment.dart';

/// Read-only appendix selection; never saves or replaces a historical snapshot.
class InvoiceAcceptanceResolver {
  const InvoiceAcceptanceResolver._();

  static TradeDocumentAttachment? resolve(
    Map<String, dynamic> workspace, {
    required DateTime? issueDate,
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
    // Historical documents without an appendix keep their original output.
    if (workspace['source_locked'] == true) {
      onMissingLockedAcceptance?.call();
      return null;
    }
    if (workspace['source_locked'] != false ||
        workspace['source_blocked'] != false) {
      throw StateError('注文請書の元帳票を確認できません。');
    }
    if (issueDate == null) throw StateError('請求書の発行日を確認してください。');
    if ((workspace['template'] as Map?)?['auto_generate'] == false) return null;
    final defaults = Map<String, dynamic>.from(workspace['defaults'] as Map);
    final payload = Map<String, dynamic>.from(defaults);
    // Templates may change prose only, never parties, amounts, month or seal.
    final template = workspace['template'];
    if (template is Map) {
      for (final key in ['acceptance_text', 'notes', 'payment_conditions', 'work_name', 'work_address']) {
        if (template[key] is String) payload[key] = template[key];
      }
    }
    payload['issue_date'] =
        '${issueDate.year.toString().padLeft(4, '0')}-'
        '${issueDate.month.toString().padLeft(2, '0')}-'
        '${issueDate.day.toString().padLeft(2, '0')}';
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
    return TradeDocumentAttachment.fromJson({'version': 1, 'payload': result});
  }
}

