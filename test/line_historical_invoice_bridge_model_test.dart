import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_historical_invoice_bridge_model.dart';
void main() {
  test('past tax and welfare inputs require an explicit percentage', () {
    expect(historicalPercentBps(''), null);
    expect(historicalPercentBps('0'), 0);
    expect(historicalPercentBps('10'), 1000);
    expect(historicalPercentBps('1.25'), 125);
    expect(historicalPercentBps('100.00'), 10000);
    for (final value in ['100.01', '-1', '1.234', '未設定', '10%']) {
      expect(historicalPercentBps(value), null);
    }
  });
}
