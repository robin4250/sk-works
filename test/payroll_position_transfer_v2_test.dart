import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_position_transfer.dart';
void main() {
  for (final type in ['daily', 'hourly', 'monthly']) {
    test('$type reclassifies basic pay and preserves gross and original', () {
      final original = <String,Object?>{'基本給':300000,'残業手当':20000};
      final result = payrollPositionTransfer({'position_transfer_snapshot':{
        'version':2,'enabled':true,'pay_type':type,
        'items':[{'name':'役職手当','amount_yen':100000}],
      }}, original)!;
      expect(result.entries, {'基本給':200000,'残業手当':20000,'役職手当':100000});
      expect(result.entries.values.cast<int>().reduce((a,b)=>a+b),320000);
      expect(original, {'基本給':300000,'残業手当':20000});
      expect(result.rate,isNull);
    });
  }
  test('overdraw refuses instead of changing gross or producing negative basic', () {
    expect(payrollPositionTransfer({'position_transfer_snapshot':{
      'version':2,'enabled':true,'pay_type':'monthly',
      'items':[{'name':'役職手当','amount_yen':300001}],
    }},{'基本給':300000}),isNull);
  });
  test('computed and already paid allowance lines cannot be overwritten', () {
    for (final name in ['残業手当','早出手当','役職手当']) {
      expect(payrollPositionTransfer({'position_transfer_snapshot':{
        'version':2,'enabled':true,'pay_type':'monthly',
        'items':[{'name':name,'amount_yen':100000}],
      }},{'基本給':300000,name:20000}),isNull);
    }
  });

}
