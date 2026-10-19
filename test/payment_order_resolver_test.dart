import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payment_order_resolver.dart';

void main() {
  Map<String, dynamic> workspace() => {
    'source_locked': false, 'source_blocked': false, 'source_changed': false,
    'attachment': null,
    'defaults': {
      'version': 1, 'kind': 'order', 'month': '2026-01',
      'issuer': {'name': '発注会社'}, 'counterparty': {'name': '受注会社'},
      'company_seal_snapshot': {'version': 1, 'style': 'legacy', 'name': '発注会社'},
      'company_seal_enabled': false, 'total_amount_yen': 110000,
      'tax_amount_yen': 10000, 'invoice_subject': '対象工事',
    },
    'template': {
      'notes': '編集済み特記事項', 'payment_conditions': '翌月末払い',
      'issuer': {'name': '別会社'}, 'total_amount_yen': 1,
      'month': '2000-01', 'company_seal_enabled': true,
    },
  };

  test('unsaved order uses source parties amounts month seal and prose only', () {
    final data = workspace();
    final result = PaymentOrderResolver.resolve(data)!;
    expect(result.payload['issue_date'], '2025-12-15');
    expect(result.payload['work_name'], '対象工事');
    expect(result.payload['issuer'], {'name': '発注会社'});
    expect(result.payload['total_amount_yen'], 110000);
    expect(result.payload['month'], '2026-01');
    expect(result.payload['company_seal_enabled'], false);
    expect(result.payload['payment_conditions'], '翌月末払い');
    expect(result.payload['notes'], '編集済み特記事項');
    expect((data['defaults'] as Map).containsKey('issue_date'), false);
    expect(data['attachment'], isNull);
  });

  test('saved edited appendix wins including on locked source', () {
    final data = workspace();
    final saved = PaymentOrderResolver.resolve(data)!;
    data['attachment'] = {'version': 7, 'payload': saved.payload};
    data['source_locked'] = true;
    data['template'] = {'notes': '置換不可'};
    final result = PaymentOrderResolver.resolve(data)!;
    expect(result.version, 7);
    expect(result.payload, saved.payload);
  });

  test('locked historical missing appendix is not rewritten', () {
    final data = workspace()..['source_locked'] = true;
    expect(PaymentOrderResolver.resolve(data), isNull);
    expect(data['attachment'], isNull);
  });

  test('changed blocked unknown readiness and wrong kind cannot generate', () {
    for (final key in ['source_changed', 'source_blocked']) {
      expect(() => PaymentOrderResolver.resolve(workspace()..[key] = true), throwsStateError);
    }
    expect(() => PaymentOrderResolver.resolve(workspace()..remove('source_locked')), throwsStateError);
    final data = workspace();
    (data['defaults'] as Map)['kind'] = 'acceptance';
    expect(() => PaymentOrderResolver.resolve(data), throwsStateError);
  });
}
