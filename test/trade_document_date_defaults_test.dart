import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/trade_document_date_defaults.dart';

void main() {
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
