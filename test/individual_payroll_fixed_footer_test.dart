import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/individual_payroll_settings_page.dart';
import 'package:sk_works/features/payroll/individual_payroll_settings_repository.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_repository.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_page.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';
import 'package:sk_works/features/payroll/resident_tax_capability.dart';

class _Units extends PayrollUnitConditionsRepository {
  _Units(SupabaseClient client, {this.edit = true}) : super.forTesting(client, () => 'actor');
  final bool edit;
  final saved = <List<PayrollUnitItemDraft>>[];
  Completer<void>? pending;
  bool failLoad = false;
  bool includeMonthlyItems = true;
  final loadedWorkers = <String>[];
  @override Future<bool> available() async => true;
  @override Future<PayrollUnitConditions> load(String company, String worker, String month) async {
    loadedWorkers.add(worker);
    if (failLoad) throw StateError('synthetic unavailable');
    return PayrollUnitConditions(version: 1, month: month, canEdit: edit, items: [
        for (final section in PayrollItemSection.values)
          for (final unit in PayrollItemUnit.values)
            if (includeMonthlyItems || unit != PayrollItemUnit.month)
            PayrollUnitItemDraft(id: '${section.name}-${unit.name}', section: section,
                unit: unit, name: '${section.name}-${unit.name}', rate: '100',
                quantity: unit == PayrollItemUnit.hour ? '2' : '',
                source: unit == PayrollItemUnit.hour ? 'manual_hours' :
                    unit == PayrollItemUnit.day ? 'attendance_days' : 'monthly_fixed'),
      ]);
  }
  @override Future<PayrollUnitConditions> save(String company, String worker,
      PayrollUnitConditions current, List<PayrollUnitItemDraft> items) async {
    expect(company, 'company-a'); expect(worker, 'worker-a');
    saved.add(items);
    await pending?.future;
    return PayrollUnitConditions(version: current.version + 1, month: current.month,
        canEdit: edit, items: items);
  }
}
class _Repository extends IndividualPayrollSettingsRepository {
  // Both fixtures share this client; the unit adapter needs it before the
  // explicit named superclass constructor forwards the same instance.
  // ignore: use_super_parameters
  _Repository(SupabaseClient client, {this.edit = true}) : units = _Units(client, edit: edit), super.forTesting(client);
  final bool edit;
  final _Units units;
  int legacySaves = 0;
  @override PayrollUnitConditionsRepository get unitConditions => units;
  @override Future<IndividualPayrollWorkspace> loadWorkspace() async => IndividualPayrollWorkspace(
      companyId: 'company-a', canView: true, canEdit: edit, isAdmin: edit,
      workers: const [IndividualPayrollWorker(id: 'worker-a', name: '社員A'),
        IndividualPayrollWorker(id: 'worker-b', name: '社員B')]);
  @override Future<bool> supportsPaidLeaveWages() async => false;
  @override Future<ResidentTaxCapability> residentTaxCapability() async => ResidentTaxCapability.legacy;
  @override Future<IndividualPayrollSetting> loadSetting(String workerId) async =>
      IndividualPayrollSetting(workerId: workerId, values: {
        'company_id': 'company-a', 'pay_type': 'daily', 'day_daily': 10000,
        'custom_earnings': [{'name': '既存支給', 'amount_yen': 100}],
        'custom_deductions': [{'name': '既存控除', 'amount_yen': 200}],
      });
  @override Future<void> saveSetting({required String workerId, required Map<String, dynamic> values}) async { legacySaves++; }
}
void main() {
  late SupabaseClient client;
  setUp(() => client = SupabaseClient('https://synthetic.invalid', 'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false)));
  tearDown(() async => client.dispose());
  final footer = find.byKey(const ValueKey('individual-payroll-fixed-footer'));
  Finder action(String label) => find.descendant(of: footer, matching: find.text(label));
  Future<void> open(WidgetTester tester, _Repository repository, PayrollItemSection section,
      PayrollItemUnit unit) async {
    await tester.pumpWidget(MaterialApp(home: IndividualPayrollSettingsPage(repository: repository)));
    await tester.pumpAndSettle();
    if (section == PayrollItemSection.deduction) {
      final tabs = find.byType(SegmentedButton<bool>);
      await tester.ensureVisible(tabs);
      await tester.tap(find.descendant(of: tabs, matching: find.text('控除')));
      await tester.pumpAndSettle();
    }
    final label = switch (unit) { PayrollItemUnit.hour => '時間単位', PayrollItemUnit.day => '日単位', PayrollItemUnit.month => '月単位' };
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label)); await tester.pumpAndSettle();
  }
  for (final section in PayrollItemSection.values) {
    for (final unit in PayrollItemUnit.values) {
      testWidgets('fixed footer routes ${section.name}/${unit.name} without changing save contract', (tester) async {
        final repository = _Repository(client);
        await open(tester, repository, section, unit);
        expect(footer, findsOneWidget);
        final before = tester.getRect(footer);
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(tester.getRect(footer), before);
        if (unit != PayrollItemUnit.month) {
          expect(find.text('追加'), findsOneWidget, reason: 'no embedded duplicate actions');
          expect(find.text('登録'), findsOneWidget);
          await tester.tap(action('追加')); await tester.pumpAndSettle();
          final name = find.byKey(const ValueKey('new-unit-item-0-name'));
          expect(name.hitTestable(), findsOneWidget);
          await tester.enterText(name, '追加項目');
          await tester.enterText(find.byKey(const ValueKey('new-unit-item-0-rate')), '123');
          if (unit == PayrollItemUnit.hour) {
            final quantity = find.byKey(const ValueKey('new-unit-item-0-quantity'));
            await tester.ensureVisible(quantity); await tester.enterText(quantity, '1');
          }
          FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
          await tester.tap(action('登録')); await tester.pumpAndSettle();
          expect(repository.legacySaves, 0);
          final added = repository.units.saved.single.last;
          expect(added.section, section); expect(added.unit, unit); expect(added.rate, '123');
        } else {
          await tester.tap(action('登録')); await tester.pumpAndSettle();
          await tester.tap(find.text('確定して保存')); await tester.pumpAndSettle();
          expect(repository.legacySaves, 1); expect(repository.units.saved, isEmpty);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('keyboard completion retains draft and keeps register above keyboard', (tester) async {
    final repository = _Repository(client);
    await open(tester, repository, PayrollItemSection.earning, PayrollItemUnit.day);
    await tester.tap(action('追加')); await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('new-unit-item-0-name'));
    final rate = find.byKey(const ValueKey('new-unit-item-0-rate'));
    await tester.enterText(name, '入力を保持');
    await tester.enterText(rate, '1234');
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final done = find.byKey(const ValueKey('payroll-keyboard-done'));
    expect(done.hitTestable(), findsOneWidget);
    expect(action('登録').hitTestable(), findsOneWidget);
    final logicalKeyboardTop = tester.view.physicalSize.height / tester.view.devicePixelRatio - 260 / tester.view.devicePixelRatio;
    expect(tester.getRect(action('登録')).bottom, lessThanOrEqualTo(logicalKeyboardTop));
    await tester.tap(done); await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(repository.units.saved, isEmpty, reason: 'completion never submits');
    expect(tester.widget<TextField>(rate).controller!.text, '1234');
    tester.view.resetViewInsets(); await tester.pumpAndSettle();
    await tester.tap(action('登録')); await tester.pumpAndSettle();
    expect(repository.units.saved.single.last.name, '入力を保持');
    expect(repository.units.saved.single.last.rate, '1234');
    expect(repository.legacySaves, 0);
    expect(tester.takeException(), isNull);
  });
  for (final section in PayrollItemSection.values) {
    testWidgets('monthly ${section.name} keyboard completion preserves input and submits once', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository(client);
      await open(tester, repository, section, PayrollItemUnit.month);
      final label = section == PayrollItemSection.earning ? '支給1 金額' : '控除1 金額';
      final field = find.byWidgetPredicate((widget) => widget is TextFormField && widget.decoration?.labelText == label);
      await tester.ensureVisible(field);
      await tester.enterText(field, '789');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(action('追加').hitTestable(), findsOneWidget);
      expect(action('登録').hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('payroll-keyboard-done')));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, false);
      expect(tester.widget<TextFormField>(field).controller!.text, '789');
      expect(repository.legacySaves, 0);
      tester.view.resetViewInsets(); await tester.pumpAndSettle();
      await tester.tap(action('登録')); await tester.pumpAndSettle();
      await tester.tap(find.text('確定して保存')); await tester.pumpAndSettle();
      expect(repository.legacySaves, 1);
      expect(repository.units.saved, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('read-only unit footer stays disabled', (tester) async {
    await open(tester, _Repository(client, edit: false), PayrollItemSection.deduction, PayrollItemUnit.day);
    expect(tester.widget<OutlinedButton>(find.descendant(of: footer, matching: find.byType(OutlinedButton))).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.descendant(of: footer, matching: find.byType(FilledButton))).onPressed, isNull);
  });
  testWidgets('pending unit save blocks footer and unit changes', (tester) async {
    final repository = _Repository(client); repository.units.pending = Completer<void>();
    await open(tester, repository, PayrollItemSection.earning, PayrollItemUnit.hour);
    final button = find.descendant(of: footer, matching: find.byType(FilledButton));
    final stale = tester.widget<FilledButton>(button).onPressed!;
    stale(); await tester.pump(); await tester.pump();
    expect(repository.units.saved.length, 1);
    stale(); await tester.pump(); expect(repository.units.saved.length, 1);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '日単位')).onPressed, isNull);
    repository.units.pending!.complete(); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('worker/company reload failure invalidates the old footer binding', (tester) async {
    final repository = _Units(client);
    final controller = PayrollUnitEditorController();
    addTearDown(controller.dispose);
    Widget host(String company, String worker) => MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: PayrollUnitConditionsPage(
        repository: repository, companyId: company, workerId: worker,
        embedded: true, externalFooter: true, editorController: controller,
        section: PayrollItemSection.earning, unit: PayrollItemUnit.day,
      )),
    ));
    await tester.pumpWidget(host('company-a', 'worker-a'));
    await tester.pumpAndSettle();
    expect(controller.canAdd, true);
    final staleAdd = controller.add;
    final staleRegister = controller.register;
    repository.failLoad = true;
    await tester.pumpWidget(host('company-b', 'worker-b'));
    expect(controller.canAdd, false);
    staleAdd(); await staleRegister();
    await tester.pumpAndSettle();
    expect(controller.canRegister, false);
    expect(repository.saved, isEmpty);
    expect(find.textContaining('単位別設定を取得できません'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final failed in [false, true]) {
    for (final monthlyItems in [false, true]) {
      testWidgets('one host footer on monthly view failed=$failed items=$monthlyItems', (tester) async {
        final repository = _Repository(client);
        repository.units.failLoad = failed;
        repository.units.includeMonthlyItems = monthlyItems;
        await open(tester, repository, PayrollItemSection.earning, PayrollItemUnit.month);
        expect(find.text('追加'), findsOneWidget);
        expect(find.text('登録'), findsOneWidget);
        expect(tester.widget<OutlinedButton>(find.descendant(of: footer,
            matching: find.byType(OutlinedButton))).onPressed, isNotNull);
        if (failed) {
          expect(find.textContaining('単位別設定を取得できません'), findsOneWidget);
          for (final label in ['日単位', '時間単位']) {
            await tester.ensureVisible(find.text(label));
            await tester.tap(find.text(label)); await tester.pumpAndSettle();
            expect(find.text('追加'), findsOneWidget);
            expect(find.text('登録'), findsOneWidget);
            expect(tester.widget<OutlinedButton>(find.descendant(of: footer,
                matching: find.byType(OutlinedButton))).onPressed, isNull);
            expect(tester.widget<FilledButton>(find.descendant(of: footer,
                matching: find.byType(FilledButton))).onPressed, isNotNull,
                reason: 'registered worker allowance rows retain their existing save path');
          }
        }
        expect(repository.units.saved, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('same session worker switch retains single host footer and recovers failed units', (tester) async {
    final repository = _Repository(client);
    await open(tester, repository, PayrollItemSection.earning, PayrollItemUnit.month);
    repository.units.failLoad = true;
    final dropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown); await tester.pumpAndSettle();
    await tester.tap(find.text('社員B').last); await tester.pumpAndSettle();
    expect(repository.units.loadedWorkers.last, 'worker-b');
    expect(find.text('追加'), findsOneWidget);
    expect(find.text('登録'), findsOneWidget);
    expect(find.textContaining('単位別設定を取得できません'), findsOneWidget);
    repository.units.failLoad = false;
    final retry = find.text('再読み込み');
    await tester.ensureVisible(retry); await tester.tap(retry); await tester.pumpAndSettle();
    expect(repository.units.loadedWorkers.last, 'worker-b');
    await tester.ensureVisible(find.text('日単位'));
    await tester.tap(find.text('日単位')); await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.descendant(of: footer,
        matching: find.byType(OutlinedButton))).onPressed, isNotNull);
    expect(find.text('追加'), findsOneWidget);
    expect(find.text('登録'), findsOneWidget);
    expect(repository.units.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

}
