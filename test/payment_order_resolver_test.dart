import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payment_order_resolver.dart';

void main() {
  Map<String, dynamic> workspace() => {
    'source_locked': false,
    'source_blocked': false,
    'source_changed': false,
    'attachment': null,
    'defaults': <String, dynamic>{
      'version': 1,
      'kind': 'order',
      'month': '2026-01',
      'issuer': {'name': '発注会社'},
      'counterparty': {'name': '受注会社'},
      'company_seal_snapshot': {
        'version': 1,
        'style': 'legacy',
        'name': '発注会社',
      },
      'company_seal_enabled': false,
      'total_amount_yen': 110000,
      'tax_amount_yen': 10000,
      'invoice_subject': '対象工事',
    },
    'template': <String, dynamic>{
      'notes': '編集済み特記事項',
      'payment_conditions': '翌月末払い',
      'issuer': {'name': '別会社'},
      'total_amount_yen': 1,
      'month': '2000-01',
      'company_seal_enabled': true,
    },
  };

  test('fresh order uses exact v2 defaults without changing source financial values',(){
    final data=workspace()..['form_fields_schema_version']=2;
    final result=PaymentOrderResolver.resolve(data)!;
    final fields=result.payload['form_fields'];
    expect(fields['schema'],2);expect(fields['progress_cutoff_day'],'month_end');
    expect(fields['payments']['advance']['choice'],'no');expect(fields['cash_ratio_percent'],'100');
    expect(fields['rows'][0]['quantity'],'1');expect(fields['rows'][0]['unit'],'人日');
    expect(fields['rows'][0]['unit_price_yen'],isNull);expect(fields['rows'][0]['amount_yen'],isNull);
    expect(result.payload['total_amount_yen'],110000);expect(result.payload['tax_amount_yen'],10000);
    expect(result.payload['notes'],'編集済み特記事項');
    expect((data['defaults'] as Map).containsKey('form_fields'),isFalse);
    data['auto_generate']=false;expect(PaymentOrderResolver.resolve(data),isNull);
  });

  test(
    'unsaved order uses source parties amounts month seal and prose only',
    () {
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
    },
  );

  test('configured work name and location reach the automatic order', () {
    final data = workspace();
    (data['template'] as Map).addAll(<String, dynamic>{
      'work_name': '設定した工事',
      'work_address': '設定した場所',
    });
    final result = PaymentOrderResolver.resolve(data)!;
    expect(result.payload['work_name'], '設定した工事');
    expect(result.payload['work_address'], '設定した場所');
    data['attachment'] = {'version': 2, 'payload': result.payload};
    (data['template'] as Map)['work_name'] = '後日の変更';
    expect(PaymentOrderResolver.resolve(data)!.payload['work_name'], '設定した工事');
  });

  test('blank configured text preserves authorized source values', () {
    final data = workspace();
    (data['defaults'] as Map)['work_address'] = '元帳票の場所';
    (data['template'] as Map).addAll(<String, dynamic>{'work_name': ' ', 'work_address': ''});
    final result = PaymentOrderResolver.resolve(data)!;
    expect(result.payload['work_name'], '対象工事');
    expect(result.payload['work_address'], '元帳票の場所');
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

  test('missing source tax cannot be replaced with an assumed zero', () {
    final data = workspace();
    (data['defaults'] as Map)['tax_amount_yen'] = null;
    expect(() => PaymentOrderResolver.resolve(data), throwsStateError);
  });

  test('changed blocked unknown readiness and wrong kind cannot generate', () {
    for (final key in ['source_changed', 'source_blocked']) {
      expect(
        () => PaymentOrderResolver.resolve(workspace()..[key] = true),
        throwsStateError,
      );
    }
    expect(
      () => PaymentOrderResolver.resolve(workspace()..remove('source_locked')),
      throwsStateError,
    );
    final data = workspace();
    (data['defaults'] as Map)['kind'] = 'acceptance';
    expect(() => PaymentOrderResolver.resolve(data), throwsStateError);
  });
  test('automatic OFF preserves saved appendices and suppresses only a new one', () {
    final data = workspace();
    final saved = PaymentOrderResolver.resolve(data)!;
    data['template'] = {'auto_generate': false};
    expect(PaymentOrderResolver.resolve(data), isNull);
    data['attachment'] = {'version': 7, 'payload': saved.payload};
    final retained = PaymentOrderResolver.resolve(data)!;
    expect(retained.version, 7);
    expect(retained.payload, saved.payload);
  });

  test('read-only workspace auto flag suppresses only unsaved generation without prose access', () {
    final data = workspace();
    final saved = PaymentOrderResolver.resolve(data)!;
    data['template'] = <String, dynamic>{}; data['auto_generate'] = false;
    expect(PaymentOrderResolver.resolve(data), isNull);
    data['attachment'] = {'version': 7, 'payload': saved.payload};
    expect(PaymentOrderResolver.resolve(data)!.version, 7);
  });

}

