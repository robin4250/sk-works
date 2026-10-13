import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_historical_invoice_model.dart';
void main() {
  Map<String,dynamic> row(String id) => {'row_id':id,'worker_id':'worker','site_id':'site','work_category':'day','confirmed':true,'man_days':1,'overtime_hours':1,'early_hours':0,'allowance_names':['交通','交通']};
  test('actual people and accumulated man days are independent', () {final groups=historicalGroups([row('1'),row('2')]);expect(groups.single.workers.length,1);expect(groups.single.manDays,2);expect(groups.single.allowances['交通'],2);});
  test('missing quantities and category cannot become zero', () {expect(()=>historicalGroups([{...row('1'),'man_days':null}]),throwsStateError);expect(()=>historicalGroups([{...row('1'),'work_category':null}]),throwsStateError);});
  test('unit rates require explicit integer input', () {expect(historicalUnitRate(''),null);expect(historicalUnitRate('0'),0);expect(historicalUnitRate('-1'),null);expect(historicalUnitRate('100000001'),null);});
}
