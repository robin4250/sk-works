import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/features/shared/standalone_trade_document.dart';
import 'package:sk_works/features/shared/standalone_trade_document_validation.dart';
import 'package:sk_works/features/shared/trade_document_form_renderer.dart';

TradeDocumentFormDraft acceptance() {
  final payload = standaloneTradeDocument(context: {
    'acceptance': true,
    'issuer': {'name': '合成自社株式会社', 'address': 'Synthetic address', 'representative_name': 'Synthetic representative'},
    'counterparty': {'name': 'Synthetic recipient', 'address': 'Synthetic recipient address', 'representative_name': 'Synthetic recipient representative'},
    'company_seal_enabled': true,
    'company_seal_snapshot': {'version': 1, 'style': 'legacy', 'name': '合成自社株式会社'},
  }, fields: {
    'work_name': 'Synthetic work', 'work_address': 'Synthetic place',
    'issue_date': '2026-10-21', 'order_date': '2026-10-20',
    'acceptance_text': '{order_date}付の注文を承諾します。',
  }).payload;
  return TradeDocumentFormDraft.fromPayload(payload, allowAmountEditing: true, initializeExtendedFields: true, initializeDefaults: true);
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final entry in {
    'issue_date': '承諾日をYYYY-MM-DDで入力してください。',
    'order_date': '注文書の日付をYYYY-MM-DDで入力してください。',
  }.entries) {
    test('${entry.key} blank gets fixed safe guidance before renderer', () async {
      final draft = acceptance().withChanges({entry.key: ''});
      var rendererCalls = 0;
      try {
        validateStandaloneTradeDocumentDraft(draft);
        rendererCalls++;
        await TradeDocumentFormRenderer.canonical(draft.payload);
        fail('Blank date accepted');
      } on StandaloneTradeDateException catch (error) {
        expect(standaloneTradeGenerationMessage(error), entry.value);
      }
      expect(rendererCalls, 0);
    });
  }
  test('valid acceptance dates with no money reaches actual PDF renderer without invented amounts', () async {
    final draft = acceptance();
    validateStandaloneTradeDocumentDraft(draft);
    expect(draft.payload.containsKey('total_amount_yen'), isFalse);
    expect(draft.payload.containsKey('tax_amount_yen'), isFalse);
    final bytes = await TradeDocumentFormRenderer.canonical(draft.payload);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(100));
    expect(draft.payload.containsKey('total_amount_yen'), isFalse);
  });
  test('invalid calendar date uses only allowlisted field guidance', () {
    try {
      final invalid = acceptance().payload..['issue_date'] = '2026-02-30';
      validateStandaloneTradeDocumentDraft(TradeDocumentFormDraft.fromPayload(invalid, allowAmountEditing: true));
      fail('Invalid date accepted');
    } on StandaloneTradeDateException catch (error) {
      expect(standaloneTradeGenerationMessage(error), '承諾日をYYYY-MM-DDで入力してください。');
    }
  });
  test('order blank or absent order_date retains original draft validation behavior', () {
    for (final missing in [false, true]) {
      final payload = acceptance().payload
        ..['kind'] = 'order'
        ..['period_start'] = '2026-10-01'
        ..['period_end'] = '2026-10-31'
        ..['total_amount_yen'] = 100
        ..['tax_amount_yen'] = 0
        ..['payment_conditions'] = 'Synthetic agreed condition';
      if (missing) {
        payload.remove('order_date');
      } else {
        payload['order_date'] = '';
      }
      final draft = TradeDocumentFormDraft.fromPayload(payload, allowAmountEditing: true);
      expect(draft.validateForSave, returnsNormally);
      expect(() => validateStandaloneTradeDocumentDraft(draft), returnsNormally);
      expect(draft.payload.containsKey('order_date'), !missing);
      if (!missing) expect(draft.payload['order_date'], '');
    }
  });
  test('arbitrary validation/font/PDF exception details and raw source never reach UI', () {
    for (final error in [
      const FormatException('Synthetic confidential input', 'synthetic-source-token'),
      StateError('Synthetic font path or private metadata'),
      Exception('Synthetic PDF engine detail'),
    ]) {
      expect(standaloneTradeGenerationMessage(error), '帳票を作成できません。入力内容を確認してください。');
    }
  });
}
