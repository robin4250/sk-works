import 'dart:async';
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

  testWidgets('会社切替中に前の会社の予定や遅い応答を表示しない', (tester) async {
    final first = Completer<Object?>();
    final second = Completer<Object?>();
    var calls = 0;
    final gateway = OwnPublishedShiftGateway((_, args) {
      calls++;
      return args['p_company'] == 'companyA' ? first.future : second.future;
    });
    Widget page(String company) => MaterialApp(home: Scaffold(body: OwnPublishedShiftView(
      gateway: gateway, companyId: company, month: DateTime(2026, 10),
      siteNames: const {'site': '旧会社の現場'},
    )));
    await tester.pumpWidget(page('companyA'));
    await tester.pumpWidget(page('companyA'));
    expect(calls, 1);
    await tester.pumpWidget(page('companyB'));
    expect(calls, 2);
    first.complete([{'work_date': '2026-10-25', 'revision': 1, 'plan': {
      'site_id': 'site', 'holiday': false, 'night': true, 'check_late': true,
      'check_early': true, 'start_minute': 1200, 'end_minute': 300,
    }}]);
    await tester.pump();
    expect(find.textContaining('旧会社の現場'), findsNothing);
    expect(find.text('確定シフト（予定）'), findsNothing);
    second.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('公開されたシフトはありません。'), findsOneWidget);
  });

  testWidgets('失敗後の明示再読み込みで回復できる', (tester) async {
    var calls = 0;
    final gateway = OwnPublishedShiftGateway((_, __) async {
      if (++calls == 1) throw Exception('network');
      return [];
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OwnPublishedShiftView(
      gateway: gateway, companyId: 'company', month: DateTime(2026, 10), siteNames: const {},
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('公開されたシフトはありません。'), findsOneWidget);
  });
}
