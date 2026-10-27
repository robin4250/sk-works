import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_save_badge.dart';
void main() {
  testWidgets('saved and signature waiting have solid distinct status with text and icon', (tester) async {
    for (final state in DailyReportSaveState.values) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: DailyReportSaveBadge(state: state))));
      expect(find.text(state.label), findsOneWidget);
      final container = tester.widget<Container>(find.byKey(ValueKey('daily-report-save-badge-${state.name}')));
      final decoration = container.decoration! as BoxDecoration;
      if (state == DailyReportSaveState.saved) {
        expect(decoration.color, Colors.green.shade800);
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
      } else if (state == DailyReportSaveState.supervisorPending) {
        expect(decoration.color, Colors.red.shade900);
        expect(find.byIcon(Icons.pending_actions), findsOneWidget);
      } else {
        expect(decoration.color, isNot(Colors.green.shade800));
        expect(decoration.color, isNot(Colors.red.shade900));
      }
    }
  });
  test('both signatures in draft remain finalization pending, never green', () {
    final row = DailyReportMonthEntry(id:'fixture',date:DateTime(2026,10,25),name:'Synthetic',
      status:'draft', reporterSigned:true, supervisorSigned:true);
    expect(row.saveState,DailyReportSaveState.finalizationPending);
  });
}
