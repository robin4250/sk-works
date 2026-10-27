import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shifts/own_published_shift_gateway.dart';
import 'package:sk_works/features/shifts/own_published_shift_view.dart';

void main() {
  testWidgets('公開された夜勤を予定として示す', (tester) async {
    final gateway = OwnPublishedShiftGateway((_, __) async => [
      {'work_date': '2026-10-25', 'revision': 1, 'plan': {
        'site_id': 'site', 'holiday': false, 'night': true,
        'check_late': true, 'check_early': true, 'start_minute': 1200, 'end_minute': 300,
      }}
    ]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OwnPublishedShiftView(
      gateway: gateway, companyId: 'company', month: DateTime(2026, 10), siteNames: const {'site': '現場A'},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('確定シフト（予定）'), findsOneWidget);
    expect(find.textContaining('10月25日　夜勤'), findsOneWidget);
    expect(find.textContaining('20:00 〜 05:00（翌日）'), findsOneWidget);
  });

  testWidgets('取得失敗を予定なしと表示しない', (tester) async {
    final gateway = OwnPublishedShiftGateway((_, __) async => throw Exception('network'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OwnPublishedShiftView(
      gateway: gateway, companyId: 'company', month: DateTime(2026, 10), siteNames: const {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('シフトを確認できません。もう一度開いてください。'), findsOneWidget);
    expect(find.text('公開されたシフトはありません。'), findsNothing);
  });
}
