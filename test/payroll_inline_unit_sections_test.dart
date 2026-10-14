import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_page.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_repository.dart';

class _Units implements PayrollUnitConditionsRepository {
  final gate = Completer<PayrollUnitConditions>();
  String? savedWorker, savedMonth;
  @override
  Future<bool> available() async => true;
  @override
  Future<PayrollUnitConditions> load(String company, String worker, String month) async =>
    PayrollUnitConditions(version: 0, month: month, canEdit: true, items: [
      PayrollUnitItemDraft(id: worker, section: PayrollItemSection.earning,
        unit: PayrollItemUnit.hour, name: '${worker}条件', rate: '100', quantity: '2'),
    ]);
  @override
  Future<PayrollUnitConditions> save(String company, String worker,
      PayrollUnitConditions current, List<PayrollUnitItemDraft> items) {
    savedWorker = worker; savedMonth = current.month;
    return gate.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected operation');
}

void main() {
  testWidgets('late save from previous employee cannot replace current employee conditions', (tester) async {
    final repository = _Units();
    Widget page(String worker) => MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: PayrollUnitConditionsPage(
        key: const ValueKey('shared-unit-panel'), repository: repository,
        companyId: 'company', workerId: worker, embedded: true,
        section: PayrollItemSection.earning, unit: PayrollItemUnit.hour,
      ))));
    await tester.pumpWidget(page('A'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('登録'));
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect(repository.savedWorker, 'A');
    await tester.pumpWidget(page('B'));
    await tester.pumpAndSettle();
    expect(find.text('B条件'), findsOneWidget);
    repository.gate.complete(PayrollUnitConditions(
      version: 1, month: repository.savedMonth!, canEdit: true, items: [
        const PayrollUnitItemDraft(id: 'A', section: PayrollItemSection.earning,
          unit: PayrollItemUnit.hour, name: 'A条件', rate: '100', quantity: '2'),
      ]));
    await tester.pumpAndSettle();
    expect(find.text('B条件'), findsOneWidget);
    expect(find.text('A条件'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline unit switches retain both sections and register all month/day/hour values', (tester) async {
    const items = [
      PayrollUnitItemDraft(id: 'em', section: PayrollItemSection.earning,
        unit: PayrollItemUnit.month, name: '月額支給', rate: '1000'),
      PayrollUnitItemDraft(id: 'eh', section: PayrollItemSection.earning,
        unit: PayrollItemUnit.hour, name: '時間支給', rate: '100', quantity: '2'),
      PayrollUnitItemDraft(id: 'dm', section: PayrollItemSection.deduction,
        unit: PayrollItemUnit.month, name: '月額控除', rate: '200'),
    ];
    List<PayrollUnitItemDraft>? saved;
    Widget page(PayrollItemSection section, PayrollItemUnit unit) =>
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PayrollUnitItemEditor(
        key: const ValueKey('shared-inline-editor'), embedded: true,
        section: section, unit: unit, initialItems: items, canEdit: true,
        enableQuantitySources: true, showDailyReportOption: false,
        onRegister: (values) async => saved = values,
      ))));
    await tester.pumpWidget(page(PayrollItemSection.earning, PayrollItemUnit.month));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('em-rate')), '1500');
    await tester.pumpWidget(page(PayrollItemSection.earning, PayrollItemUnit.hour));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('em-rate')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('eh-quantity')), '3');
    await tester.pumpWidget(page(PayrollItemSection.deduction, PayrollItemUnit.month));
    await tester.pumpAndSettle();
    expect(find.text('月額控除'), findsOneWidget);
    await tester.ensureVisible(find.text('登録'));
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(3));
    expect(saved!.singleWhere((i) => i.id == 'em').rate, '1500');
    expect(saved!.singleWhere((i) => i.id == 'eh').quantity, '3');
    expect(saved!.singleWhere((i) => i.id == 'dm').rate, '200');
    expect(tester.takeException(), isNull);
  });
}
