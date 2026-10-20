import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sk_works/features/payroll/company_common_payroll_page.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';

void main() {

  testWidgets('keyboard leaves a scrolling editor and compact fixed actions', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    List<PayrollUnitItemDraft>? saved;
    await tester.pumpWidget(MaterialApp(home: CompanyCommonPayrollPage(
      canEdit: true,
      onRegister: (_, items) async { saved = items; },
      initialItems: {
        CompanyPayrollType.hourly: [
          for (var i = 0; i < 3; i++)
            PayrollUnitItemDraft(id: 'scroll-$i', section: PayrollItemSection.earning,
              unit: PayrollItemUnit.hour, name: '手当$i', rate: '100'),
        ],
      },
    )));
    await tester.pumpAndSettle();
    final selector = find.widgetWithText(OutlinedButton, '時給');
    final initialY = tester.getTopLeft(selector).dy;
    final footer = find.byKey(const ValueKey('company-common-fixed-footer'));
    final footerY = tester.getTopLeft(footer).dy;
    expect(tester.getBottomRight(footer).dy, lessThanOrEqualTo(360));
    final field = find.byKey(const ValueKey('scroll-2-rate'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(selector).dy, lessThan(initialY - 100));
    expect(tester.getTopLeft(footer).dy, closeTo(footerY, 1));
    expect(tester.getBottomRight(field).dy, lessThanOrEqualTo(footerY));
    await tester.enterText(field, '250');
    await tester.tap(find.widgetWithText(FilledButton, '登録'));
    await tester.pumpAndSettle();
    expect(saved!.last.rate, '250');
    // Returning to the selectors must not dispose drafts below the viewport.
    await tester.drag(find.byKey(const ValueKey('company-common-scroll')), const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '250');
    expect(tester.takeException(), isNull);
  });

  testWidgets('salary type and section changes retain separate drafts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyCommonPayrollPage(
          canEdit: true,
          onRegister: (_, __) async {},
          initialItems: const {
            CompanyPayrollType.daily: [
              PayrollUnitItemDraft(
                id: 'daily-item',
                section: PayrollItemSection.earning,
                unit: PayrollItemUnit.month,
                name: '日給共通',
                rate: '1000',
              ),
            ],
            CompanyPayrollType.hourly: [
              PayrollUnitItemDraft(
                id: 'hour-item',
                section: PayrollItemSection.earning,
                unit: PayrollItemUnit.month,
                name: '時給共通',
                rate: '2000',
              ),
            ],
          },
        ),
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '日給'));
    await tester.tap(find.widgetWithText(OutlinedButton, '月単位'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('daily-item-name')),
      '編集保持',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '時給'));
    await tester.pump();
    expect(find.byKey(const ValueKey('hour-item-name')), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '日給'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('daily-item-name')))
          .controller!
          .text,
      '編集保持',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '控除'));
    await tester.pump();
    expect(find.text('共通控除'), findsOneWidget);
    expect(find.byKey(const ValueKey('daily-item-name')), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, '支給'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('daily-item-name')))
          .controller!
          .text,
      '編集保持',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unconnected screen never permits writes and fits narrow display',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: CompanyCommonPayrollPage(canEdit: true)),
      );
      expect(find.textContaining('接続準備中'), findsOneWidget);
      for (final editor in tester.widgetList<PayrollUnitItemEditor>(
        find.byType(PayrollUnitItemEditor, skipOffstage: false),
      )) {
        expect(editor.canEdit, isFalse);
        expect(editor.onRegister, isNull);
      }
      final widths = ['日給', '時給', '月給']
          .map(
            (label) => tester
                .getSize(find.widgetWithText(OutlinedButton, label))
                .width,
          )
          .toList();
      expect(widths[0], closeTo(widths[1], .01));
      expect(widths[1], closeTo(widths[2], .01));
      expect(tester.takeException(), isNull);
    },
  );
}
