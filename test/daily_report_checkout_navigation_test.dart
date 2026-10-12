import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/daily_report_checkout_navigation.dart';

void main() {
  bool finished({bool signed = true, bool visit = false,
    String? route = 'route-1', String? initialRoute = 'route-1',
    String? source = 'saved-clock-in', DateTime? date, DateTime? initialDate}) =>
      shouldFinishCheckoutReport(
        signed: signed, isVisitReport: visit, reportRouteId: route,
        checkoutRouteId: initialRoute, checkoutSourceId: source,
        reportDate: date ?? DateTime(2026, 10, 12),
        checkoutDate: initialDate ?? DateTime(2026, 10, 12),
      );

  test('signed checkout route returns immediately to existing quantity step', () {
    expect(finished(), isTrue);
    expect(finished(signed: false), isFalse);
  });
  test('independently viewed or changed reports stay open for viewing and print', () {
    expect(finished(source: null), isFalse);
    expect(finished(initialRoute: null), isFalse);
    expect(finished(route: 'another-route'), isFalse);
    expect(finished(date: DateTime(2026, 10, 13)), isFalse);
    expect(finished(route: null, initialRoute: null), isFalse);
  });
  test('signed visit report still proceeds to next site', () {
    expect(finished(visit: true, source: null, initialRoute: null), isTrue);
    expect(finished(visit: true, signed: false), isFalse);
  });
}
