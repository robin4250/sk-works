import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/r18_defaults.dart';

void main() {
  Map<String, dynamic> initial(Map<String,dynamic> payload,
      {Map<String,dynamic> defaults=const {}, bool saved=false,
       String kind='payment_certificate'}) => r18InitialValues(payload:payload,
        sourceDefaults:defaults,hasSavedAttachment:saved,subjectKind:kind);

  test('new order uses prior month 15 including year boundary and leap month', () {
    for(final pair in {'2026-10':'2026-09-15','2026-01':'2025-12-15',
      '2024-03':'2024-02-15','2024-02':'2024-01-15'}.entries) {
      expect(initial({'month':pair.key})['issue_date'],pair.value);
    }
  });
  test('acceptance defaults order date but never invents acceptance issue date', () {
    final value=initial({'month':'2026-10'},kind:'invoice');
    expect(value['order_date'],'2026-09-15');
    expect(value.containsKey('issue_date'),isFalse);
  });
  test('explicit source dates and subjects are preserved ahead of generated dates', () {
    final defaults={'issue_date':'2026-10-15','work_name':'既存工事名',
      'invoice_subject':'請求書の正式件名'};
    final value=initial({'month':'2026-10'},defaults:defaults);
    expect(value['issue_date'],'2026-10-15');
    expect(value['work_name'],'既存工事名');
  });
  test('nonempty draft and template choices keep priority over source fallback', () {
    final payload={'month':'2026-10','issue_date':'2026-10-20','work_name':'利用者の指定'};
    expect(initial(payload,defaults:{'issue_date':'2026-09-15',
      'invoice_subject':'別の表示値'}),payload);
  });
  test('authorized exact subject only fills blank work name without inventing it', () {
    expect(initial({'month':'2026-10','work_name':''},
      defaults:{'invoice_subject':' 鳶工・安全設備 '})['work_name'],' 鳶工・安全設備 ');
    expect(initial({'month':'2026-10'}).containsKey('work_name'),isFalse);
  });
  test('saved empty or explicit fields never acquire defaults on reopen', () {
    for(final payload in [<String,dynamic>{'month':'2026-10','issue_date':''},
      <String,dynamic>{'month':'2026-10','issue_date':'2026-10-15'}]) {
      expect(initial(payload,saved:true,defaults:{'invoice_subject':'new'}),payload);
      expect(initial(initial(payload,saved:true),saved:true),payload);
    }
  });
  test('all source periods totals rates and nested payload remain unchanged', () {
    final payload={'month':'2024-02','period_start':'2024-02-01',
      'period_end':'2024-02-29','total_amount_yen':110000,'tax_amount_yen':10000,
      'rate_unit':'hour','unit_rate_yen':3000,'issuer':{'name':'自社'}};
    final before=Map<String,dynamic>.from(payload);
    final value=initial(payload);
    expect(payload,before);
    for(final key in before.keys) { expect(value[key],before[key]); }
    expect(initial(value),value);
  });
  test('invalid month refuses calendar normalization when date is required', () {
    for(final month in ['2026-13','2026-00','2026-1','0000-01','0001-01','bad']) {
      expect(()=>initial({'month':month}),throwsFormatException);
    }
  });
}
