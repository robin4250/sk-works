import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_save_badge.dart';
void main() {
  testWidgets('saved and signature waiting have outlined distinct status with text and icon', (tester) async {
    for (final state in DailyReportSaveState.values) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: DailyReportSaveBadge(state: state))));
      expect(find.text(state.label), findsOneWidget);
      final container = tester.widget<Container>(find.byKey(ValueKey('daily-report-save-badge-${state.name}')));
      final decoration = container.decoration! as BoxDecoration;
      final surface = Theme.of(tester.element(find.byType(DailyReportSaveBadge))).colorScheme.surface;
      expect(decoration.color, surface);
      final border = decoration.border! as Border;
      if (state == DailyReportSaveState.saved) {
        expect(border.top.color, Colors.green.shade800);
        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      } else if (state == DailyReportSaveState.supervisorPending) {
        expect(border.top.color, Colors.red.shade900);
        expect(find.byIcon(Icons.pending_actions), findsOneWidget);
      } else {
        expect(border.top.color, isNot(Colors.green.shade800));
        expect(border.top.color, isNot(Colors.red.shade900));
      }
    }
  });
  test('both signatures in draft remain finalization pending, never green', () {
    final row = DailyReportMonthEntry(id:'fixture',date:DateTime(2026,10,25),name:'Synthetic',
      status:'draft', reporterSigned:true, supervisorSigned:true);
    expect(row.saveState,DailyReportSaveState.finalizationPending);
  });
}
