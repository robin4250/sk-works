import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only platform fake for SharedPreferencesAsync used by report stores.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:sk_works/features/daily_reports/daily_report_page.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';
import 'package:sk_works/features/attendance/group_checkout_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_allowance_name_field.dart';
import 'package:sk_works/features/daily_reports/daily_report_company_allowance_selection.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/group_daily_report_roster.dart';
import 'package:sk_works/features/shared/company_allowance_label_repository.dart';

CompanyAllowanceLabel registered(int number, String name, {String unit = 'day',
    String payrollType = 'all', String origin = 'company_legacy', bool ready = true}) =>
  CompanyAllowanceLabel(id: ready ? '10000000-0000-0000-0000-${number.toString().padLeft(12, '0')}' : null,
    name: name, unit: unit, generation: origin == 'company_legacy' && ready ? 1 : null,
    registrationVersion: ready ? 7 : null, origin: origin, payrollType: payrollType,
    displayUnit: unit == 'hour' ? '時間' : unit == 'month' ? '月' : '日');

final class _EmptyAsyncPreferences extends SharedPreferencesAsyncPlatform {
  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('Unexpected preference operation: ${invocation.memberName}');
}

class _CheckoutFlowRepository implements DailyReportRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('Unexpected repository operation: ${invocation.memberName}');
  DailyReportRecord? saved;
  final saves = <List<DailyReportWorkerDraft>>[];
  int eligibilityReads = 0, labelReads = 0;
  @override
  String? get currentActorId => 'synthetic-actor';
  @override
  String? get notificationRetryUserId => null;
  @override
  Future<List<DailyReportSiteGroup>> loadClockedInGroups(DateTime date) async => [
    DailyReportSiteGroup(siteId: 'site', siteName: '合成現場', workers: [
      DailyReportWorkerDraft(workerId: 'worker', workerName: '合成社員')])];
  @override
  Future<DailyReportRecord?> loadReport({required DateTime date, String? siteId,
    String? routeAssignmentId, String? vehicleClockInAnchorId, String? reportId}) async => saved;
  @override
  Future<List<DailyReportEvidenceRecord>> loadAttendanceEvidence({String? reportId,
    required DateTime date, String? siteId, String? routeAssignmentId}) async => [];
  @override
  Future<bool> vehicleMeterEnabledForAnchor(String? anchor) async => false;
  @override
  Future<CompanyAllowanceLabelSnapshot> loadCompanyAllowanceLabels({
    required Iterable<String> workerIds, String? expectedCompanyId}) async {
    labelReads++;
    return CompanyAllowanceLabelSnapshot(companyId: 'own', version: 1, items: [registered(1, 'PC手当')]);
  }
  @override
  Future<Map<String, Set<String>>> loadCompanyAllowanceEligibility({required String reportId,
    required Iterable<String> workerIds, required CompanyAllowanceLabelSnapshot snapshot}) async {
    eligibilityReads++;
    return {'worker': {'company_legacy/${snapshot.items.single.id}'}};
  }
  @override
  Future<String> saveDraft({String? reportId, String? siteId, String? routeAssignmentId,
    required DateTime date, required String workDescription,
    required List<DailyReportWorkerDraft> workers, String? groupClockInAnchorId,
    String? vehicleClockInAnchorId}) async {
    final copy = [for (final worker in workers) DailyReportWorkerDraft(
      workerId: worker.workerId, workerName: worker.workerName,
      allowanceLabel: worker.allowanceLabel, companyAllowanceSelections: worker.companyAllowanceSelections)];
    saves.add(copy);
    saved = DailyReportRecord(id: 'report', companyId: 'own', siteId: 'site',
      siteName: '合成現場', date: date, workDescription: workDescription, status: 'draft', workers: copy);
    return 'report';
  }
}

void main() {
  testWidgets('first draft save stays on report and selected allowance is saved before signature page', (tester) async {
    final previousPreferences = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = _EmptyAsyncPreferences();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previousPreferences);
    final repository = _CheckoutFlowRepository();
    await tester.pumpWidget(MaterialApp(home: DailyReportPage(
      initialDate: DateTime(2026, 10, 1), initialSiteId: 'site', repositoryForTesting: repository)));
    await tester.pumpAndSettle();
    expect(repository.eligibilityReads, 0);
    expect(repository.labelReads, 1);
    await tester.enterText(find.byKey(const ValueKey('daily-report-work-description')), '合成の作業内容');
    final reportScroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    final member = find.descendant(of: find.byType(ExpansionTile), matching: find.text('合成社員'));
    await tester.scrollUntilVisible(member, 250, scrollable: reportScroll);
    await tester.ensureVisible(member);
    await tester.pumpAndSettle();
    await tester.tap(member); await tester.pumpAndSettle();
    expect(find.byType(DailyReportAllowanceNameField), findsOneWidget,
      reason: tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | '));
    expect(tester.widget<DailyReportAllowanceNameField>(find.byType(DailyReportAllowanceNameField)).registeredItems, hasLength(1));
    await tester.scrollUntilVisible(find.widgetWithText(FilterChip, 'PC手当'), 250, scrollable: reportScroll);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'PC手当')).onSelected, isNull);
    final register = find.text('登録');
    await tester.scrollUntilVisible(register, 250, scrollable: reportScroll);
    await tester.ensureVisible(register); await tester.pumpAndSettle();
    await tester.tap(register); await tester.pumpAndSettle();
    expect(find.byType(DailyReportPage), findsOneWidget);
    expect(repository.saves, hasLength(1));
    expect(repository.eligibilityReads, 1);
    final chip = find.widgetWithText(FilterChip, 'PC手当');
    await tester.scrollUntilVisible(chip, -250, scrollable: reportScroll);
    await tester.ensureVisible(chip); await tester.pumpAndSettle();
    await tester.tap(chip); await tester.pumpAndSettle();
    final reporter = find.text('報告者サイン').first;
    await tester.scrollUntilVisible(reporter, 250, scrollable: reportScroll);
    await tester.ensureVisible(reporter); await tester.pumpAndSettle();
    await tester.tap(reporter); await tester.pumpAndSettle();
    expect(repository.saves, hasLength(2));
    expect(repository.saves.last.single.allowanceLabel, 'PC手当');
    expect(repository.saves.last.single.companyAllowanceSelections!.items.single.nameSnapshot, 'PC手当');
    expect(find.byType(SignatureCapturePage), findsOneWidget);
    await tester.pageBack(); await tester.pumpAndSettle();
  });

  test('labels use every selected worker and report company, never first membership', () {
    expect(dailyReportAllowanceCompanyScope([
      {'id': 'two', 'company_id': 'own'}, {'id': 'one', 'company_id': 'own'},
    ], workerIds: ['one', 'two'], expectedCompanyId: 'own'), 'own');
    for (final rows in [
      [{'id': 'one', 'company_id': 'own'}],
      [{'id': 'one', 'company_id': 'own'}, {'id': 'one', 'company_id': 'own'}],
      [{'id': 'one', 'company_id': 'own'}, {'id': 'other', 'company_id': 'own'}],
      [{'id': 'one', 'company_id': 'own'}, {'id': 'two', 'company_id': 'other'}],
      [{'id': 'one', 'company_id': 'own'}, {'id': 'two', 'company_id': null}],
    ]) {
      expect(() => dailyReportAllowanceCompanyScope(rows,
        workerIds: ['one', 'two'], expectedCompanyId: 'own'), throwsStateError);
    }
    expect(() => dailyReportAllowanceCompanyScope([
      {'id': 'one', 'company_id': 'other'},
    ], workerIds: ['one'], expectedCompanyId: 'own'), throwsStateError);
    expect(() => dailyReportAllowanceCompanyScope([], workerIds: []), throwsStateError);
  });

  test('typed selection preserves identities and original units, never price or quantity', () {
    final day = DailyReportCompanyAllowanceSelection.registered(registered(1, 'PC手当'));
    final hour = DailyReportCompanyAllowanceSelection.registered(registered(2, '時間手当',
      unit: 'hour', origin: 'company_common', payrollType: 'daily'));
    final selected = DailyReportCompanyAllowanceSelections([hour, day]);
    final wire = selected.toJson();
    expect(DailyReportCompanyAllowanceSelections.fromJson(wire).toJson(), wire);
    final rows = wire['items'] as List;
    expect(rows.every((row) => !(row as Map).containsKey('amount_yen') && !row.containsKey('quantity')), isTrue);
    expect(selected.items.map((item) => item.unit).toSet(), {'day', 'hour'});
    expect(() => DailyReportCompanyAllowanceSelections([day, day]), throwsFormatException);
    expect(() => DailyReportCompanyAllowanceSelection.registered(registered(3, '月固定',
      unit: 'month', origin: 'company_common', payrollType: 'monthly')), throwsFormatException);
    expect(() => DailyReportCompanyAllowanceSelection.registered(registered(4, '未準備', ready: false)), throwsFormatException);
    expect(() => DailyReportCompanyAllowanceSelection.fromJson({...day.toJson(), 'amount_yen': 999}), throwsFormatException);
    expect(() => DailyReportCompanyAllowanceSelection.fromJson({...day.toJson(), 'unit': 'month'}), throwsFormatException);
    final worker = DailyReportWorkerDraft(workerId: 'one', workerName: '合成社員');
    expect(worker.toRpcJson().containsKey('company_allowance_selections'), isFalse);
    worker.companyAllowanceSelections = DailyReportCompanyAllowanceSelections([]);
    expect(worker.toRpcJson()['company_allowance_selections'], {'contract_version': 1, 'items': []});
  });

  test('anchored roster preserves typed choices and existing text without adding amounts', () {
    final selected = DailyReportCompanyAllowanceSelections([
      DailyReportCompanyAllowanceSelection.registered(registered(1, 'PC手当'))]);
    final saved = DailyReportWorkerDraft(workerId: 'one', workerName: '合成社員',
      allowanceLabel: 'PC手当\n保存済み個別名', companyAllowanceSelections: selected);
    final merged = mergeAnchoredGroupRoster(existing: [saved], fallback: [], candidates: [
      GroupCheckoutCandidate(sourceId: 'source', workerId: 'one', name: '合成社員', workDate: DateTime(2026, 10, 1))],
      allowNewMembers: false);
    expect(merged.single.companyAllowanceSelections!.toJson(), selected.toJson());
    expect(merged.single.allowanceLabel, saved.allowanceLabel);
    expect(merged.single.allowanceAmount, 0);
    expect(dailyReportRpcValueEqual({'items': [{'name': 'PC', 'unit': 'day'}]},
      {'items': [{'unit': 'day', 'name': 'PC'}]}), isTrue);
  });

  Future<void> showField(WidgetTester tester, TextEditingController controller,
      {List<CompanyAllowanceLabel>? items, bool enabled = true, bool unavailable = false,
      DailyReportCompanyAllowanceSelections? initial, bool eligibilityKnown = true, bool needsSavedReport = false, Set<String>? allowedKeys,
      ValueChanged<DailyReportCompanyAllowanceSelections>? onChanged}) async {
    var selected = initial;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, change) => DailyReportAllowanceNameField(controller: controller,
        enabled: enabled, registeredItems: items ?? [registered(1, '鉄骨手当'), registered(2, 'PC手当')],
        eligibleKeys: eligibilityKnown ? allowedKeys ?? (items ?? [registered(1, '鉄骨手当'), registered(2, 'PC手当')])
            .where((item) => item.id != null).map((item) => '${item.origin}/${item.id}').toSet() : null,
        needsSavedReport: needsSavedReport,
        selections: selected, unavailable: unavailable,
        onSelectionsChanged: (value) { change(() => selected = value); onChanged?.call(value); })))));
  }

  testWidgets('unsaved choices enable only after verified saved-report eligibility', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await showField(tester, controller, eligibilityKnown: false, needsSavedReport: true);
    expect(find.text('日報を保存すると、各メンバーに適用できる手当を選択できます。'), findsOneWidget);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'PC手当')).onSelected, isNull);
    expect(controller.text, isEmpty);
    await showField(tester, controller);
    await tester.tap(find.widgetWithText(FilterChip, 'PC手当')); await tester.pump();
    expect(controller.text, 'PC手当');
  });

  testWidgets('known inapplicable company items cannot be selected', (tester) async {
    final controller = TextEditingController(text: '過去名');
    addTearDown(controller.dispose);
    await showField(tester, controller, allowedKeys: {});
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'PC手当')).onSelected, isNull);
    expect(controller.text, '過去名');
  });

  test('report eligibility requires matching company, worker and both registration versions', () {
    final item = registered(1, 'PC手当');
    final snapshot = CompanyAllowanceLabelSnapshot(companyId: 'own', version: 7,
      legacyVersion: 3, items: [item]);
    Map<String, Object?> response() => {'contract_version': 1, 'report_id': 'report',
      'company_id': 'own', 'source_versions': {'legacy_version': 3, 'common_version': 7},
      'workers': [{'worker_id': 'one', 'items': [{'origin': item.origin, 'id': item.id,
        'generation': item.generation, 'registration_version': item.registrationVersion}]}]};
    expect(dailyReportCompanyAllowanceEligibility(response(), reportId: 'report',
      workerIds: ['one'], snapshot: snapshot)['one'], {'${item.origin}/${item.id}'});
    for (final invalid in [response()..['company_id'] = 'other',
      response()..['source_versions'] = {'legacy_version': 3, 'common_version': 8},
      response()..['workers'] = [], response()..['rate'] = 100]) {
      expect(() => dailyReportCompanyAllowanceEligibility(invalid, reportId: 'report',
        workerIds: ['one'], snapshot: snapshot), throwsFormatException);
    }
  });

  testWidgets('registered company choices never preselect or replace existing text', (tester) async {
    final controller = TextEditingController(text: '  保存済み個別名  ');
    addTearDown(controller.dispose);
    var changes = 0;
    DailyReportCompanyAllowanceSelections? saved;
    controller.addListener(() => changes++);
    await showField(tester, controller, onChanged: (value) => saved = value);
    expect(find.text('現在の会社共通手当'), findsOneWidget);
    expect(find.text('鉄骨手当'), findsOneWidget);
    expect(find.text('PC手当'), findsOneWidget);
    expect(controller.text, '  保存済み個別名  ');
    expect(changes, 0);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    await tester.tap(find.widgetWithText(FilterChip, 'PC手当')); await tester.pump();
    expect(controller.text, '  保存済み個別名  \nPC手当');
    expect(saved!.items.single.id, registered(2, 'PC手当').id);
    await tester.tap(find.widgetWithText(FilterChip, '鉄骨手当')); await tester.pump();
    expect(controller.text, '  保存済み個別名  \nPC手当\n鉄骨手当');
    await tester.tap(find.widgetWithText(FilterChip, 'PC手当')); await tester.pump();
    expect(controller.text, '  保存済み個別名  \n鉄骨手当');
    expect(saved!.items.single.nameSnapshot, '鉄骨手当');
  });

  testWidgets('a saved name is not silently adopted into a current ID', (tester) async {
    final controller = TextEditingController(text: 'PC手当\n保存済み個別名');
    addTearDown(controller.dispose);
    DailyReportCompanyAllowanceSelections? saved;
    await showField(tester, controller, onChanged: (value) => saved = value);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'PC手当')).selected, isFalse);
    expect(saved, isNull);
    await tester.tap(find.widgetWithText(FilterChip, 'PC手当')); await tester.pump();
    expect(controller.text, 'PC手当\n保存済み個別名');
    expect(saved!.items.single.nameSnapshot, 'PC手当');
    await tester.tap(find.widgetWithText(FilterChip, 'PC手当')); await tester.pump();
    expect(controller.text, '保存済み個別名');
    expect(saved!.items, isEmpty);
  });

  testWidgets('month unit is absent while daily allowance for monthly-paid worker remains', (tester) async {
    final controller = TextEditingController(); addTearDown(controller.dispose);
    await showField(tester, controller, items: [
      registered(1, '月固定', unit: 'month', origin: 'company_common', payrollType: 'monthly'),
      registered(2, '月給者の日手当', unit: 'day', origin: 'company_common', payrollType: 'monthly'),
      registered(3, '時間手当', unit: 'hour', origin: 'company_common', payrollType: 'daily'),
    ]);
    expect(find.text('月固定'), findsNothing);
    expect(find.text('月給者の日手当'), findsOneWidget);
    expect(find.text('時間手当'), findsOneWidget);
  });

  testWidgets('changed registration is not silently adopted and retired selection stays removable', (tester) async {
    final old = registered(1, '旧会社名');
    final changed = CompanyAllowanceLabel(id: old.id, name: '新会社名', unit: 'day',
      generation: 1, registrationVersion: 8);
    final controller = TextEditingController(text: '旧会社名\n保存済み個別名');
    addTearDown(controller.dispose);
    var captured = DailyReportCompanyAllowanceSelections([
      DailyReportCompanyAllowanceSelection.registered(old)]);
    await showField(tester, controller, items: [changed], initial: captured,
      onChanged: (value) => captured = value);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '新会社名')).selected, isFalse);
    expect(controller.text, '旧会社名\n保存済み個別名');
    expect(captured.items.single.registrationVersion, 7);
    await tester.tap(find.widgetWithText(FilterChip, '新会社名')); await tester.pump();
    expect(controller.text, '保存済み個別名\n新会社名');
    expect(captured.items.single.registrationVersion, 8);
    await showField(tester, controller, items: [], initial: captured,
      onChanged: (value) => captured = value);
    expect(controller.text, '保存済み個別名\n新会社名');
    final oldChip = tester.widget<InputChip>(find.byType(InputChip));
    oldChip.onDeleted!(); await tester.pump();
    expect(controller.text, '保存済み個別名');
    expect(captured.items, isEmpty);
  });

  testWidgets('locked controls and unprepared identities keep saved raw values', (tester) async {
    final controller = TextEditingController(text: '保存した旧名'); addTearDown(controller.dispose);
    await showField(tester, controller, enabled: false);
    for (final chip in tester.widgetList<FilterChip>(find.byType(FilterChip))) { expect(chip.onSelected, isNull); }
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    final duplicate = registered(1, '重複ID');
    await showField(tester, controller, items: [duplicate, duplicate,
      registered(2, '未準備', ready: false), registered(3, '改行\n手当'), registered(4, '明確な手当')]);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '重複ID')).onSelected, isNull);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '未準備')).onSelected, isNull);
    expect(find.text('改行\n手当'), findsNothing);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '明確な手当')).onSelected, isNotNull);
    expect(controller.text, '保存した旧名');
    await showField(tester, controller, items: [], unavailable: true);
    expect(find.text('会社共通手当の候補を確認できません。保存済みの手当名は保持しています。'), findsOneWidget);
    expect(controller.text, '保存した旧名');
  });
}

