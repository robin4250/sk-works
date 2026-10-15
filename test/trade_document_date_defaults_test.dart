import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/trade_document_date_defaults.dart';

void main() {
  test('November order pays by December month end', () {
    expect(tradeDocumentDefaultPaymentConditions('2026-11'),
        '工事完了確認後、2026年12月末日までに乙の指定口座に振り込む。');
    expect(tradeDocumentDefaultPaymentConditions('2026-12'),
        '工事完了確認後、2027年1月末日までに乙の指定口座に振り込む。');
    expect(tradeDocumentJapaneseDate('2026-10-15'), '2026年10月15日');
    expect(() => tradeDocumentJapaneseDate('2026-02-30'), throwsFormatException);
  });
  test('October work period uses September 15 contract', () {
    expect(tradeDocumentDateDefaults('2026-10'), {
      'issue_date': '2026-09-15', 'order_date': '2026-09-15',
      'period_start': '2026-10-01', 'period_end': '2026-10-31',
    });
  });
  test('January contract falls in previous year', () {
    expect(tradeDocumentDateDefaults('2026-01')['issue_date'], '2025-12-15');
  });
  test('February last day respects leap years', () {
    expect(tradeDocumentDateDefaults('2028-02')['period_end'], '2028-02-29');
    expect(tradeDocumentDateDefaults('2026-02')['period_end'], '2026-02-28');
  });
  test('invalid months are never silently normalized', () {
    for (final month in ['2026-00', '2026-13', '2026-2', '']) {
      expect(() => tradeDocumentDateDefaults(month), throwsFormatException);
    }
  });
}
