import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';

const _items = [
  PayrollUnitItemDraft(
    id: 'hour',
    section: PayrollItemSection.earning,
    unit: PayrollItemUnit.hour,
    name: '時間手当',
    rate: '1200',
  ),
  PayrollUnitItemDraft(
    id: 'day',
    section: PayrollItemSection.deduction,
    unit: PayrollItemUnit.day,
    name: '日割控除',
    rate: '500',
  ),
  PayrollUnitItemDraft(
    id: 'month',
    section: PayrollItemSection.earning,
    unit: PayrollItemUnit.month,
    name: '月手当',
    rate: '10000',
  ),
];

Future<void> _mount(
  WidgetTester tester, {
  List<PayrollUnitItemDraft> items = _items,
  bool canEdit = true,
  Future<void> Function(List<PayrollUnitItemDraft>)? register,
}) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Scaffold(
        body: PayrollUnitItemEditor(
          initialItems: items,
          canEdit: canEdit,
          onRegister: register,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'tabs preserve edits and register includes both sections and all units',
    (tester) async {
      List<PayrollUnitItemDraft>? saved;
      await _mount(tester, register: (items) async => saved = items);
      await tester.enterText(
        find.byKey(const ValueKey('hour-name')),
        '編集した時間手当',
      );
      await tester.enterText(find.byKey(const ValueKey('hour-rate')), '1500');
      await tester.tap(find.byType(Checkbox));
      await tester.tap(find.text('控除'));
      await tester.tap(find.text('日にち単位'));
      await tester.pumpAndSettle();
      expect(find.text('日割控除'), findsOneWidget);
      await tester.tap(find.text('支給'));
      await tester.tap(find.text('月単位'));
      await tester.pumpAndSettle();
      expect(find.text('月手当'), findsOneWidget);
      await tester.tap(find.text('時間単位'));
      await tester.pumpAndSettle();
      expect(find.text('編集した時間手当'), findsOneWidget);
      await tester.tap(find.text('登録'));
      await tester.pumpAndSettle();
      expect(saved!.map((item) => item.id), ['hour', 'day', 'month']);
      expect(saved!.first.rate, '1500');
      expect(saved!.first.showInDailyReport, isTrue);
      expect(saved![1].section, PayrollItemSection.deduction);
      expect(saved![1].unit, PayrollItemUnit.day);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('add targets selected group and delete does not restore it', (
    tester,
  ) async {
    List<PayrollUnitItemDraft>? saved;
    await _mount(
      tester,
      items: const [],
      register: (items) async => saved = items,
    );
    await tester.tap(find.text('控除'));
    await tester.tap(find.text('月単位'));
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-unit-item-0-name')),
      '月控除',
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-unit-item-0-rate')),
      '300',
    );
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect(saved!.single.section, PayrollItemSection.deduction);
    expect(saved!.single.unit, PayrollItemUnit.month);
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('時間単位'));
    await tester.tap(find.text('月単位'));
    await tester.pumpAndSettle();
    expect(find.text('項目はありません'), findsOneWidget);
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hidden invalid group is shown and failed register retains input',
    (tester) async {
      var calls = 0;
      await _mount(
        tester,
        register: (_) async {
          calls++;
          throw StateError('offline');
        },
      );
      await tester.enterText(find.byKey(const ValueKey('hour-rate')), '-1');
      await tester.tap(find.text('月単位'));
      await tester.tap(find.text('登録'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('単価は0以上の整数で入力してください'), findsOneWidget);
      expect(find.byKey(const ValueKey('hour-rate')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('hour-rate')), '1600');
      await tester.tap(find.text('登録'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('登録できませんでした。入力内容を保持しています'), findsOneWidget);
      expect(find.text('1600'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('read only and unconnected storage cannot register', (
    tester,
  ) async {
    var calls = 0;
    await _mount(
      tester,
      canEdit: false,
      register: (_) async {
        calls++;
      },
    );
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('hour-name'))).enabled,
      isFalse,
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '登録'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '追加'))
          .onPressed,
      isNull,
    );
    expect(calls, 0);
    await _mount(tester, items: const []);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '登録'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
