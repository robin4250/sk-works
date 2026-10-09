import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_draft_keep_alive.dart';
import 'package:sk_works/widgets/rate_formula_editor_card.dart';

void main() {
  for (final type in ['hourly', 'monthly']) {
    testWidgets('unsaved $type selection and input survive a full scroll round trip',
        (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      RateFormulaDraft? draft;
      await tester.pumpWidget(_editorList(
        scroll: scroll,
        worker: 'worker-a',
        onChanged: (value) => draft = value,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(type == 'hourly' ? '時給' : '月給'));
      await tester.pumpAndSettle();
      final label = type == 'hourly' ? '基準時給' : '計算用 1日基本ベース';
      final baseField = find.widgetWithText(TextField, label);
      await tester.enterText(baseField, '01234');
      if (type == 'monthly') {
        await tester.enterText(find.widgetWithText(TextField, '月固定給'), '350000');
      }
      await tester.pumpAndSettle();
      final editorState = tester.state(find.byType(RateFormulaEditorCard));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byType(RateFormulaEditorCard).hitTestable(), findsNothing);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(RateFormulaEditorCard)), same(editorState));
      expect(tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>)).selected, {type});
      expect(tester.widget<TextField>(baseField).controller!.text, '01234');
      expect(draft!.payType, type);
      expect(draft!.baseRateYen, 1234);
      if (type == 'monthly') {
        expect(draft!.monthlySalaryYen, 350000);
      }
    });
  }

  testWidgets('another worker uses their saved pay type and amount', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_editorList(
      scroll: scroll, worker: 'worker-a', onChanged: (_) {},
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('時給'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '基準時給'), '1234');
    RateFormulaDraft? draft;
    await tester.pumpWidget(_editorList(
      scroll: scroll,
      worker: 'worker-b',
      savedType: 'monthly',
      savedBase: 14000,
      savedMonthly: 300000,
      onChanged: (value) => draft = value,
    ));
    await tester.pumpAndSettle();
    expect(draft!.payType, 'monthly');
    expect(draft!.baseRateYen, 14000);
    expect(draft!.monthlySalaryYen, 300000);
    expect(tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>)).selected, {'monthly'});
  });
}

Widget _editorList({
  required ScrollController scroll,
  required String worker,
  required ValueChanged<RateFormulaDraft> onChanged,
  String savedType = 'daily',
  int savedBase = 10000,
  int savedMonthly = 0,
}) => MaterialApp(
  home: Scaffold(
    body: ListView(
      controller: scroll,
      children: [
        PayrollDraftKeepAlive(
          key: ValueKey('payroll-rate-$worker'),
          child: RateFormulaEditorCard(
            title: '勤務単価 自動計算',
            initialBaseRateYen: savedBase,
            initialFormula: const {},
            initialOverrides: const {},
            initialPayType: savedType,
            initialMonthlySalaryYen: savedMonthly,
            enabled: true,
            onChanged: onChanged,
          ),
        ),
        for (var i = 0; i < 30; i++) const SizedBox(height: 200),
      ],
    ),
  ),
);
