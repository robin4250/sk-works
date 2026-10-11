import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sk_works/features/daily_reports/daily_report_month_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_page.dart';

void main() {
  testWidgets(
    'daily report opens the monthly list through its calendar action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DailyReportPage(initialDate: DateTime(2024, 2, 29))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DailyReportMonthPage), findsNothing);
      await tester.tap(find.byKey(const Key('daily-report-month-list')));
      await tester.pumpAndSettle();
      expect(find.byType(DailyReportMonthPage), findsOneWidget);
      expect(find.text('日報一覧・月まとめ保存'), findsOneWidget);
      expect(find.text('2024年2月'), findsOneWidget);
      // An unauthenticated test still reaches the page and safely keeps export
      // unavailable; navigation never performs a write or invents report data.
      expect(find.text('日報一覧を取得できません。ログイン状態を確認して再読み込みしてください。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
