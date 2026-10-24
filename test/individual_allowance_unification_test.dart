import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/individual_allowance_rows.dart';
import 'package:sk_works/features/payroll/individual_payroll_settings_page.dart';
import 'package:sk_works/features/payroll/individual_payroll_settings_repository.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_repository.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_page.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';
import 'package:sk_works/features/payroll/resident_tax_capability.dart';
import 'package:sk_works/features/shared/company_allowance_label_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _typed = PayrollUnitItemDraft(id: 'typed-day-item',
  section: PayrollItemSection.earning, unit: PayrollItemUnit.day,
  name: '現場手当', rate: '500');

class _Units extends PayrollUnitConditionsRepository {
  _Units(SupabaseClient client) : super.forTesting(client, () => 'actor-a');
  List<PayrollUnitItemDraft> items = [_typed];
  int saves = 0, version = 1;
  bool fail = false, availableValue = true;
  List<PayrollUnitItemDraft>? submitted;
  @override Future<bool> available() async => availableValue;
  @override Future<PayrollUnitConditions> load(String company, String worker, String month) async {
    expect(company, 'company-a'); expect(worker, 'worker-a');
    return PayrollUnitConditions(version: version, month: month, canEdit: true,
      items: items);
  }
  @override Future<PayrollUnitConditions> save(String company, String worker,
      PayrollUnitConditions current, List<PayrollUnitItemDraft> next) async {
    expect(company, 'company-a'); expect(worker, 'worker-a');
    saves++; submitted = List.of(next);
    if (fail) throw StateError('synthetic transport ambiguity');
    items = List.of(next); version++;
    return load(company, worker, current.month);
  }
}

class _Settings extends IndividualPayrollSettingsRepository {
  _Settings(SupabaseClient client) : units = _Units(client), super.forTesting(client);
  final _Units units;
  int saves = 0;
  bool allowGeneralSave = false, failAfterWorkerSave = false;
  final values = <String, dynamic>{
    'company_id': 'company-a', 'pay_type': 'daily', 'day_daily': 10000,
    'allowance_name_1': 'PC', 'allowance_1': 2500,
    'allowance_name_2': '鉄骨', 'allowance_2': 2500,
    'allowance_name_3': '', 'allowance_3': 0,
    'custom_earnings': <Map<String, dynamic>>[],
    'custom_deductions': <Map<String, dynamic>>[],
  };
  @override PayrollUnitConditionsRepository get unitConditions => units;
  @override Future<IndividualPayrollWorkspace> loadWorkspace() async =>
    const IndividualPayrollWorkspace(canView: true, canEdit: true, isAdmin: true,
      companyId: 'company-a', workers: [IndividualPayrollWorker(id: 'worker-a', name: '社員A')]);
  @override Future<bool> supportsPaidLeaveWages() async => false;
  @override Future<ResidentTaxCapability> residentTaxCapability() async => ResidentTaxCapability.legacy;
  @override Future<IndividualPayrollSetting> loadSetting(String workerId) async =>
    IndividualPayrollSetting(workerId: workerId, values: Map.of(values));
  @override Future<void> saveSetting({required String workerId,
      required Map<String, dynamic> values}) async {
    expect(workerId, 'worker-a'); saves++;
    // A partial old-slot save must not rewrite tax/rates/monthly custom values.
    if (!allowGeneralSave) expect(values.keys.toSet(), {'allowance_name_1', 'allowance_1',
      'allowance_name_2', 'allowance_2', 'allowance_name_3', 'allowance_3'});
    this.values.addAll(values);
    if (failAfterWorkerSave) throw StateError('synthetic worker response unknown');
  }
}

class _Labels implements CompanyAllowanceLabelSource {
  @override Future<CompanyAllowanceLabelSnapshot> read(String company) async =>
    CompanyAllowanceLabelSnapshot(companyId: company, version: 1, legacyVersion: 1, items: const [
      CompanyAllowanceLabel(id: '10000000-0000-0000-0000-000000000001', name: '会社PC',
        unit: 'day', generation: 1, legacySlot: 1, registrationVersion: 1),
      CompanyAllowanceLabel(id: '10000000-0000-0000-0000-000000000002', name: '月額共通',
        unit: 'month', generation: null, origin: 'company_common', payrollType: 'daily',
        registrationVersion: 1),
      CompanyAllowanceLabel(id: '10000000-0000-0000-0000-000000000003', name: '月額共通控除',
        section: 'deduction', unit: 'month', generation: null, origin: 'company_common',
        payrollType: 'daily', registrationVersion: 1),
      CompanyAllowanceLabel(id: '10000000-0000-0000-0000-000000000004', name: '時間共通',
        unit: 'hour', generation: null, origin: 'company_common', payrollType: 'daily',
        registrationVersion: 1),
    ]);
}

Future<void> _mount(WidgetTester tester, _Settings repository) async {
  tester.view.physicalSize = const Size(700, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: IndividualPayrollSettingsPage(repository: repository)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('日単位'));
  await tester.tap(find.text('日単位'));
  await tester.pumpAndSettle();
}

void main() {
  late SupabaseClient client;
  setUp(() => client = SupabaseClient('https://synthetic.invalid', 'synthetic-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false)));
  tearDown(() async => client.dispose());

  test('old slots retain IDs, hide empty third and never enter unit storage', () {
    final old = individualAllowanceRows({'allowance_name_1':'PC','allowance_1':2500,
      'allowance_name_2':'鉄骨','allowance_2':2500,'allowance_name_3':'','allowance_3':0});
    expect(old.map((x) => x.id), ['worker-allowance-slot-1','worker-allowance-slot-2']);
    final split = splitIndividualAllowanceRows([old[1], _typed]);
    expect(split.workerValues['allowance_name_1'], '');
    expect(split.workerValues['allowance_1'], 0);
    expect(split.workerValues['allowance_name_2'], '鉄骨');
    expect(split.workerValues['allowance_2'], 2500);
    expect(split.unitItems.single.id, 'typed-day-item');
    expect(splitIndividualAllowanceRows(individualAllowanceRows(split.workerValues)).workerValues,
      split.workerValues);
    expect(() => splitIndividualAllowanceRows([const PayrollUnitItemDraft(
      id:'worker-allowance-slot-4', section:PayrollItemSection.earning,
      unit:PayrollItemUnit.day,name:'不明',rate:'1')]), throwsFormatException);
  });

  testWidgets('one daily list saves edited old rows and additional rows to their original stores', (t) async {
    final repository = _Settings(client);
    await _mount(t, repository);
    expect(find.text('手当1〜3を登録'), findsNothing);
    expect(find.byKey(const ValueKey('worker-allowance-slot-3-name')), findsNothing);
    final oldRate = find.byKey(const ValueKey('worker-allowance-slot-1-rate'));
    await t.ensureVisible(oldRate); await t.enterText(oldRate, '2600');
    final typedRate = find.byKey(const ValueKey('typed-day-item-rate'));
    await t.ensureVisible(typedRate); await t.enterText(typedRate, '700');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.tap(find.widgetWithText(FilledButton, '登録')); await t.pumpAndSettle();
    expect(repository.saves, 1); expect(repository.units.saves, 1);
    expect(repository.values['allowance_1'], 2600);
    expect(repository.values['allowance_name_2'], '鉄骨');
    expect(repository.values['allowance_2'], 2500);
    expect(repository.units.submitted!.single.id, 'typed-day-item');
    expect(repository.units.submitted!.single.rate, '700');
    expect(repository.units.submitted!.any((x) => individualAllowanceSlot(x.id) != null), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('delete and add keep the remaining old slot and add only a new typed row', (t) async {
    final repository = _Settings(client);
    await _mount(t, repository);
    final oldName = find.byKey(const ValueKey('worker-allowance-slot-1-name'));
    final card = find.ancestor(of: oldName, matching: find.byType(Card)).first;
    final remove = find.descendant(of: card, matching: find.widgetWithText(TextButton, '削除'));
    await t.ensureVisible(remove); await t.tap(remove); await t.pumpAndSettle();
    await t.tap(find.widgetWithText(OutlinedButton, '追加')); await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('new-unit-item-0-name')), '作業手当');
    await t.enterText(find.byKey(const ValueKey('new-unit-item-0-rate')), '300');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.tap(find.widgetWithText(FilledButton, '登録')); await t.pumpAndSettle();
    expect(repository.values['allowance_name_1'], '');
    expect(repository.values['allowance_1'], 0);
    expect(repository.values['allowance_name_2'], '鉄骨');
    expect(repository.units.submitted!.map((x) => x.name), ['現場手当','作業手当']);
    expect(repository.units.submitted!.any((x) => individualAllowanceSlot(x.id) != null), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('all validation precedes saving and an ambiguous second save blocks retries while retaining input', (t) async {
    final repository = _Settings(client);
    await _mount(t, repository);
    final oldRate = find.byKey(const ValueKey('worker-allowance-slot-1-rate'));
    await t.ensureVisible(oldRate); await t.enterText(oldRate, 'invalid');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.tap(find.widgetWithText(FilledButton, '登録')); await t.pumpAndSettle();
    expect(repository.saves, 0); expect(repository.units.saves, 0);
    await t.enterText(oldRate, '2600');
    repository.units.fail = true;
    FocusManager.instance.primaryFocus?.unfocus();
    await t.tap(find.widgetWithText(FilledButton, '登録')); await t.pumpAndSettle();
    expect(repository.saves, 1); expect(repository.units.saves, 1);
    expect(find.textContaining('一部の手当は保存済みです'), findsOneWidget);
    expect(t.widget<TextField>(oldRate).controller!.text, '2600');
    expect(t.widget<TextField>(oldRate).enabled, isFalse);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '登録')).onPressed, isNull);
    expect(t.takeException(), isNull);
  });
  testWidgets('an actor change after the first store prevents the next store write', (t) async {
    final repository = _Settings(client);
    var current = true;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PayrollUnitConditionsPage(
      repository: repository.units, companyId: 'company-a', workerId: 'worker-a',
      individualAllowanceItems: individualAllowanceRows(repository.values),
      canEditIndividualAllowances: true,
      section: PayrollItemSection.earning, unit: PayrollItemUnit.day,
      individualAllowanceScopeCurrent: () => current,
      onSaveIndividualAllowances: (_) async { current = false; return true; },
    ))));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '登録'));
    await t.pumpAndSettle();
    expect(repository.units.saves, 0);
    expect(find.textContaining('一部の手当は保存済みです'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a setting from another company is rejected before the allowance editor opens', (t) async {
    final repository = _Settings(client);
    repository.values['company_id'] = 'other-company';
    await t.pumpWidget(MaterialApp(home: IndividualPayrollSettingsPage(repository: repository)));
    await t.pumpAndSettle();
    expect(find.textContaining('給与設定の会社が一致しません'), findsOneWidget);
    expect(find.byKey(const ValueKey('worker-allowance-slot-1-name')), findsNothing);
    expect(repository.saves, 0); expect(repository.units.saves, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('current company names include monthly earnings and deductions without copying personal values', (t) async {
    final repository = _Settings(client);
    await t.pumpWidget(MaterialApp(home: IndividualPayrollSettingsPage(
      repository: repository, registeredAllowanceSource: _Labels())));
    await t.pumpAndSettle();
    expect(find.text('月額共通'), findsOneWidget);
    expect(repository.saves, 0); expect(repository.units.saves, 0);
    await t.ensureVisible(find.text('日単位')); await t.tap(find.text('日単位'));
    await t.pumpAndSettle();
    final ownName = find.byKey(const ValueKey('worker-allowance-slot-1-name'));
    await t.ensureVisible(ownName);
    expect(t.widget<TextField>(ownName).controller!.text, 'PC');
    expect(t.widget<TextField>(ownName).decoration!.helperText, '会社の登録名：会社PC');
    expect(repository.values['allowance_1'], 2500);
    await t.ensureVisible(find.text('時間単位')); await t.tap(find.text('時間単位'));
    await t.pumpAndSettle();
    expect(find.text('時間共通'), findsOneWidget);
    await t.ensureVisible(find.text('月単位')); await t.tap(find.text('月単位'));
    await t.pumpAndSettle();
    final tabs = find.byType(SegmentedButton<bool>);
    await t.ensureVisible(tabs);
    await t.tap(find.descendant(of: tabs, matching: find.text('控除')));
    await t.pumpAndSettle();
    expect(find.text('月額共通控除'), findsOneWidget);
    expect(repository.saves, 0); expect(repository.units.saves, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('invalid daily input cannot be saved through another unit general register', (t) async {
    final repository = _Settings(client)..allowGeneralSave = true;
    await _mount(t, repository);
    final oldRate = find.byKey(const ValueKey('worker-allowance-slot-1-rate'));
    await t.ensureVisible(oldRate); await t.enterText(oldRate, 'invalid');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.ensureVisible(find.text('月単位')); await t.tap(find.text('月単位'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '登録')); await t.pumpAndSettle();
    expect(repository.saves, 0); expect(repository.units.saves, 0);
    expect(find.text('単価は0以上の整数で入力してください'), findsOneWidget);
    expect(t.widget<TextField>(oldRate).controller!.text, 'invalid');
    expect(find.text('確定して保存'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('monthly general register preserves daily edits and commits the captured typed draft too', (t) async {
    final repository = _Settings(client)..allowGeneralSave = true;
    await _mount(t, repository);
    final oldRate = find.byKey(const ValueKey('worker-allowance-slot-1-rate'));
    await t.ensureVisible(oldRate); await t.enterText(oldRate, '02600');
    final typedRate = find.byKey(const ValueKey('typed-day-item-rate'));
    await t.ensureVisible(typedRate); await t.enterText(typedRate, '00700');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.ensureVisible(find.text('月単位')); await t.tap(find.text('月単位'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(OutlinedButton, '追加')); await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, '支給1 名称'), '月個別');
    await t.enterText(find.widgetWithText(TextFormField, '支給1 金額'), '00300');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.tap(find.widgetWithText(FilledButton, '登録')); await t.pumpAndSettle();
    await t.tap(find.text('確定して保存')); await t.pumpAndSettle();
    expect(repository.saves, 1); expect(repository.units.saves, 1);
    expect(repository.values['allowance_1'], 2600);
    expect(repository.values['allowance_name_2'], '鉄骨');
    expect(repository.values['allowance_2'], 2500);
    expect(repository.values['custom_earnings'], [{'name': '月個別', 'amount_yen': 300}]);
    expect(repository.units.items.single.id, 'typed-day-item');
    expect(repository.units.items.single.rate, '00700');
    expect(repository.units.items.any((x) => individualAllowanceSlot(x.id) != null), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('an unknown general-store result blocks the general footer without sending unit drafts', (t) async {
    final repository = _Settings(client)..allowGeneralSave = true..failAfterWorkerSave = true;
    await _mount(t, repository);
    await t.ensureVisible(find.text('月単位')); await t.tap(find.text('月単位'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '登録')); await t.pumpAndSettle();
    await t.tap(find.text('確定して保存')); await t.pumpAndSettle();
    expect(repository.saves, 1); expect(repository.units.saves, 0);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '登録')).onPressed, isNull);
    expect(find.text('手当の保存結果を確認するまで、保存し直せません。入力を保持しています。'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('an unavailable unit reader keeps old rows without erasing unseen unit records', (t) async {
    final repository = _Settings(client);
    repository.units.availableValue = false;
    await _mount(t, repository);
    final oldRate = find.byKey(const ValueKey('worker-allowance-slot-1-rate'));
    await t.ensureVisible(oldRate); await t.enterText(oldRate, '2600');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.tap(find.widgetWithText(FilledButton, '登録')); await t.pumpAndSettle();
    expect(repository.saves, 1); expect(repository.units.saves, 0);
    expect(repository.values['allowance_1'], 2600);
    expect(repository.units.items.single.id, 'typed-day-item');
    expect(repository.units.items.single.rate, '500');
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '追加')).onPressed, isNull);
    expect(t.takeException(), isNull);
  });

}
