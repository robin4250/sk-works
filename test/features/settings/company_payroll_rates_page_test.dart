import 'dart:async';
import 'dart:io';

import 'package:sk_works/features/settings/company_payroll_rate_pending_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_payroll_rates_page.dart';
import 'package:sk_works/features/settings/company_payroll_rates_repository.dart';

Map<String, dynamic> value(String kind, {int employee = 500000, int employer = 800000}) => {
  'kind': kind, 'label': payrollRateKinds[kind] ?? '追加料率',
  'total': employee + employer, 'employee': employee, 'employer': employer,
  'insurance_month': '2026-10-01', 'payroll_month': '2026-11-01', 'payment_month': '2026-11-01',
  'source': {'publisher': '登録資料', 'url': 'https://example.org/rates',
    'document_hash': 'test-doc', 'applicability': {'business_category': '一般'}},
};

class MemoryPendingStore implements PayrollRatePendingStore {
  PayrollRatePendingWrite? pending;
  bool failWrite = false;
  Completer<void>? clearGate;
  @override
  Future<PayrollRatePendingWrite?> read(String companyId) async => pending?.companyId == companyId ? pending : null;
  @override
  Future<void> write(PayrollRatePendingWrite value) async {
    if (failWrite) throw StateError('disk full');
    pending = value;
  }
  @override
  Future<void> clear(PayrollRatePendingWrite expected) async {
    final gate = clearGate;
    if (gate != null) await gate.future;
    if (pending?.companyId == expected.companyId) pending = null;
  }
}

class FakeRatesRepository implements CompanyPayrollRatesRepository {
  CompanyPayrollRatesData data = const CompanyPayrollRatesData(canEdit: true, items: [], candidates: [], history: []);
  final List<Map<String, dynamic>> scopes = [];
  final List<String> applied = [];
  final List<Map<String, dynamic>> saved = [];
  final pendingStore = MemoryPendingStore();
  bool failRead = false;
  bool failSave = false;
  bool failAfterSend = false;
  bool rejectManual = false;
  int manualAttempts = 0;
  bool unavailable = false;
  int sentVersion = 0;
  void commitSentCustom() {
    final sent = saved.single;
    data = CompanyPayrollRatesData(canEdit: data.canEdit, items: [
      ...data.items, CompanyPayrollRateItem(id: sent['item_id'] as String,
        version: sentVersion + 1, value: sent['value'] as Map<String, dynamic>, origin: 'manual'),
    ], candidates: data.candidates, history: data.history, companyScope: data.companyScope);
  }
  @override
  Future<CompanyPayrollRatesData> read(String companyId) async {
    if (unavailable) throw const PayrollRatesUnavailable();
    if (failRead) throw StateError('offline');
    return data;
  }
  @override
  Future<void> saveScope({required String companyId, required int expectedVersion, required Map<String, dynamic> value}) async {
    if (failSave) throw StateError('conflict');
    scopes.add(value);
    data = CompanyPayrollRatesData(canEdit: true, items: data.items, candidates: data.candidates, history: data.history,
      companyScope: CompanyPayrollRateScope(version: expectedVersion + 1, value: value, updatedBy: 'admin', updatedAt: '2026-10-09'));
    if (failAfterSend) throw TimeoutException('response lost');
  }
  @override
  Future<void> applyCandidate({required String companyId, required String itemId,
    required String candidateId, required int expectedVersion, Map<String, dynamic>? expectedValue}) async {
    if (failSave) throw StateError('conflict');
    applied.add(candidateId);
  }
  @override
  Future<void> saveManual({required String companyId, required String itemId,
    required int expectedVersion, required Map<String, dynamic> value}) async {
    manualAttempts++;
    if (rejectManual) throw const PayrollRateWriteRejected('23505');
    if (failSave) throw StateError('conflict');
    saved.add({'item_id': itemId, 'value': value});
    sentVersion = expectedVersion;
    if (failAfterSend) throw StateError('response lost');
  }
}

Future<void> openPage(WidgetTester tester, FakeRatesRepository repository) async {
  await tester.pumpWidget(MaterialApp(home: CompanyPayrollRatesPage(companyId: 'company', repository: repository, pendingStore: repository.pendingStore)));
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 50);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('candidate returned value must match the confirmed displayed value', () async {
    final repository = SupabaseCompanyPayrollRatesRepository(invoke: (_, _) async => {
      'item_id': 'health_insurance', 'version': 1, 'origin': 'official_candidate',
      'value': value('health_insurance', employee: 600000),
    });
    await expectLater(repository.applyCandidate(companyId: 'company', itemId: 'health_insurance',
      candidateId: 'selected', expectedVersion: 0, expectedValue: value('health_insurance')),
      throwsFormatException);
  });

  testWidgets('child support standard shares need explicit selection and never save automatically', (tester) async {
    final repository = FakeRatesRepository();
    await openPage(tester, repository);
    final label = find.text(payrollRateKinds['child_support']!);
    await reveal(tester, label);
    final card = find.ancestor(of: label, matching: find.byType(Card));
    await tester.tap(find.descendant(of: card, matching: find.text('編集')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(
      find.byKey(const ValueKey('rate-field-employee'))).controller!.text, isEmpty);
    final standard = find.byKey(const ValueKey('child-support-standard-shares'));
    await reveal(tester, standard);
    await tester.tap(standard);
    await tester.pumpAndSettle();
    for (final key in ['employee', 'employer']) {
      expect(tester.widget<TextFormField>(
        find.byKey(ValueKey('rate-field-$key'))).controller!.text, '0.115');
    }
    expect(tester.widget<TextFormField>(
      find.byKey(const ValueKey('rate-field-insurance_month'))).controller!.text, isEmpty);
    expect(repository.saved, isEmpty);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repository.saved, isEmpty);
  });

  for (final entry in <String, Map<String, String>>{
    'health_insurance': {'total': '9.9', 'employee': '4.95', 'employer': '4.95'},
    'nursing_insurance': {'total': '1.62', 'employee': '0.81', 'employer': '0.81'},
    'pension_insurance': {'total': '18.3', 'employee': '9.15', 'employer': '9.15'},
    'employment_insurance': {'total': '1.65', 'employee': '0.6', 'employer': '1.05'},
    'child_support': {'total': '0.23', 'employee': '', 'employer': ''},
  }.entries) {
    testWidgets('new ${entry.key} starts with requested inputs without saving', (tester) async {
      final repository = FakeRatesRepository();
      await openPage(tester, repository);
      final label = find.text(payrollRateKinds[entry.key]!);
      await reveal(tester, label);
      final card = find.ancestor(of: label, matching: find.byType(Card));
      final edit = find.descendant(of: card, matching: find.text('編集'));
      await tester.tap(edit);
      await tester.pumpAndSettle();
      for (final field in entry.value.entries) {
        expect(tester.widget<TextFormField>(
          find.byKey(ValueKey('rate-field-${field.key}'))).controller!.text, field.value);
      }
      for (final key in ['insurance_month', 'payroll_month', 'payment_month', 'publisher', 'url']) {
        expect(tester.widget<TextFormField>(
          find.byKey(ValueKey('rate-field-$key'))).controller!.text, isEmpty);
      }
      expect(repository.saved, isEmpty);
      expect(repository.applied, isEmpty);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(repository.saved, isEmpty);
      expect(repository.data.items, isEmpty);
    });
  }

  testWidgets('editing saved zero rates preserves them instead of requested inputs', (tester) async {
    final repository = FakeRatesRepository();
    final current = value('health_insurance', employee: 0, employer: 0);
    repository.data = CompanyPayrollRatesData(canEdit: true, items: [
      CompanyPayrollRateItem(id: 'health_insurance', version: 3,
        value: current, origin: 'manual'),
    ], candidates: [], history: []);
    await openPage(tester, repository);
    final card = find.ancestor(of: find.text(payrollRateKinds['health_insurance']!),
      matching: find.byType(Card));
    final edit = find.descendant(of: card, matching: find.text('編集'));
    await reveal(tester, edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    for (final key in ['total', 'employee', 'employer']) {
      expect(tester.widget<TextFormField>(
        find.byKey(ValueKey('rate-field-$key'))).controller!.text, '0');
    }
    expect(tester.widget<TextFormField>(
      find.byKey(const ValueKey('rate-field-publisher'))).controller!.text, '登録資料');
    expect(repository.saved, isEmpty);
    expect(current, value('health_insurance', employee: 0, employer: 0));
  });

  test('read-only response accepts redacted actor and missing permission denies editing', () {
    final raw = <String, dynamic>{
      'items': [], 'candidates': [], 'history': [], 'scope_history': [],
      'company_scope': {'version': 1, 'value': {'insurer': 'kyokai',
        'prefecture': '東京都', 'employment_business': 'general'}, 'updated_at': '2026-10-09'},
    };
    final data = CompanyPayrollRatesData.fromJson(raw);
    expect(data.canEdit, isFalse);
    expect(data.companyScope!.updatedBy, isNull);
    expect(CompanyPayrollRatesData.fromJson({...raw, 'can_edit': true}).canEdit, isTrue);
  });

  testWidgets('viewer reads rates and candidates without any editing or PDF registration', (tester) async {
    final repository = FakeRatesRepository();
    repository.data = CompanyPayrollRatesData(items: [
      CompanyPayrollRateItem(id: 'health_insurance', version: 1,
        value: value('health_insurance'), origin: 'manual'),
    ], candidates: [CompanyPayrollRateCandidate(id: 'viewer-candidate',
      itemId: 'health_insurance', value: value('health_insurance', employee: 600000),
      checkedAt: '2026-10-09', scopeVersion: 1)], history: [],
      companyScope: const CompanyPayrollRateScope(version: 1,
        value: {'insurer': 'kyokai', 'prefecture': '東京都', 'employment_business': 'general'},
        updatedBy: null, updatedAt: '2026-10-09'));
    await openPage(tester, repository);
    expect(find.text('閲覧のみ：料率・適用月・情報元を確認できます。'), findsOneWidget);
    expect(find.text('会社の適用条件を編集'), findsNothing);
    expect(find.text('編集'), findsNothing);
    await tester.scrollUntilVisible(find.text('変更あり'), 150,
      scrollable: find.byType(Scrollable).first);
    expect(find.text('変更あり'), findsOneWidget);
    expect(find.byKey(const ValueKey('apply-viewer-candidate')), findsNothing);
    expect(find.text('適用 2026-10'), findsWidgets);
    expect(find.text('情報元 登録資料'), findsWidgets);
    await tester.scrollUntilVisible(find.text('子ども・子育て支援金率'), 250,
      scrollable: find.byType(Scrollable).first);
    expect(find.text('料率項目を追加'), findsNothing);
    expect(find.text('年度・PDF資料を管理'), findsNothing);
    expect(repository.saved, isEmpty);
    expect(repository.applied, isEmpty);
    expect(repository.scopes, isEmpty);
  });

  test('percentages preserve all six decimal digits and reject invalid input', () {
    expect(parsePayrollRatePercent('0.000001'), 1);
    expect(parsePayrollRatePercent('1.234567'), 1234567);
    expect(formatPayrollRatePercent(1234567), '1.234567');
    expect(formatPayrollRatePercent(1000000), '1');
    for (final invalid in ['-1', '100.000001', '0.1234567', '1e2', 'NaN']) {
      expect(() => parsePayrollRatePercent(invalid), throwsFormatException);
    }
  });

  test('manual RPC rejects valid response for wrong item/version/origin/value', () async {
    final requested = value('health_insurance');
    for (final wrong in [
      {'item_id': 'wrong', 'version': 1, 'origin': 'manual', 'value': requested},
      {'item_id': 'health_insurance', 'version': 0, 'origin': 'manual', 'value': requested},
      {'item_id': 'health_insurance', 'version': 1, 'origin': 'official_candidate', 'value': requested},
      {'item_id': 'health_insurance', 'version': 1, 'origin': 'manual', 'value': value('health_insurance', employee: 600000)},
    ]) {
      final repository = SupabaseCompanyPayrollRatesRepository(invoke: (_, parameters) async => wrong);
      await expectLater(repository.saveManual(companyId: 'company', itemId: 'health_insurance', expectedVersion: 0, value: requested), throwsFormatException);
    }
  });

  test('candidate RPC verifies item/version/origin and sends confirmation only once', () async {
    var calls = 0;
    final repository = SupabaseCompanyPayrollRatesRepository(invoke: (name, parameters) async {
      calls++;
      expect(parameters['p_candidate_id'], 'selected');
      expect(parameters['p_confirmed'], true);
      return {'item_id': 'different-item', 'version': 1, 'origin': 'official_candidate', 'value': value('health_insurance')};
    });
    await expectLater(repository.applyCandidate(companyId: 'company', itemId: 'health_insurance', candidateId: 'selected', expectedVersion: 0), throwsFormatException);
    expect(calls, 1);
  });

  testWidgets('missing verified candidates never become zero rate or apply button', (tester) async {
    final repository = FakeRatesRepository();
    await openPage(tester, repository);
    expect(find.text('未設定'), findsWidgets);
    expect(find.text('確認値はまだ登録されていません'), findsWidgets);
    expect(find.text('適用'), findsNothing);
    expect(repository.applied, isEmpty);
  });

  testWidgets('cancel confirmation writes nothing; confirm applies selected candidate only', (tester) async {
    final repository = FakeRatesRepository();
    repository.data = CompanyPayrollRatesData(canEdit: true, items: [], candidates: [
      CompanyPayrollRateCandidate(id: 'first', itemId: 'health_insurance', value: value('health_insurance'), checkedAt: '2026-10-09', scopeVersion: 1),
      CompanyPayrollRateCandidate(id: 'second', itemId: 'employment_insurance', value: value('employment_insurance'), checkedAt: '2026-10-09', scopeVersion: 1),
    ], history: [], companyScope: const CompanyPayrollRateScope(version: 1, value: {'insurer': 'kyokai', 'prefecture': '東京都', 'employment_business': 'general'}, updatedBy: 'admin', updatedAt: '2026-10-09'));
    await openPage(tester, repository);
    await reveal(tester, find.byKey(const ValueKey('apply-first')));
    await tester.tap(find.byKey(const ValueKey('apply-first')));
    await tester.pumpAndSettle();
    expect(find.text(payrollRateConfirmation), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repository.applied, isEmpty);
    await reveal(tester, find.byKey(const ValueKey('apply-second')));
    await tester.tap(find.byKey(const ValueKey('apply-second')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認して適用'));
    await tester.pumpAndSettle();
    expect(repository.applied, ['second']);
  });

  testWidgets('failed candidate save does not announce success', (tester) async {
    final repository = FakeRatesRepository()..failSave = true;
    repository.data = CompanyPayrollRatesData(canEdit: true, items: [], candidates: [
      CompanyPayrollRateCandidate(id: 'one', itemId: 'health_insurance', value: value('health_insurance'), checkedAt: '2026-10-09', scopeVersion: 1),
    ], history: [], companyScope: const CompanyPayrollRateScope(version: 1, value: {'insurer': 'kyokai', 'prefecture': '東京都', 'employment_business': 'general'}, updatedBy: 'admin', updatedAt: '2026-10-09'));
    await openPage(tester, repository);
    await reveal(tester, find.byKey(const ValueKey('apply-one')));
    await tester.tap(find.byKey(const ValueKey('apply-one')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認して適用'));
    await tester.pumpAndSettle();
    expect(repository.applied, isEmpty);
    expect(find.text('選択した項目を適用しました'), findsNothing);
    expect(find.textContaining('適用結果を確認できません'), findsOneWidget);
  });

  testWidgets('failed read shows retry without creating initial zero values', (tester) async {
    final repository = FakeRatesRepository()..failRead = true;
    await openPage(tester, repository);
    expect(find.text('再試行'), findsOneWidget);
    expect(find.text('未設定'), findsNothing);
    expect(find.text('編集'), findsNothing);
    repository.failRead = false;
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();
    expect(find.text('未設定'), findsWidgets);
  });

  testWidgets('stale company scope disables candidate application without changing rates', (tester) async {
    final repository = FakeRatesRepository();
    repository.data = CompanyPayrollRatesData(canEdit: true, items: [], candidates: [
      CompanyPayrollRateCandidate(id: 'stale', itemId: 'health_insurance', value: value('health_insurance'), checkedAt: '2026-10-09', scopeVersion: 1),
    ], history: [], companyScope: const CompanyPayrollRateScope(version: 2,
      value: {'insurer': 'kyokai', 'prefecture': '大阪府', 'employment_business': 'construction'}, updatedBy: 'admin', updatedAt: '2026-10-09'));
    await openPage(tester, repository);
    await reveal(tester, find.byKey(const ValueKey('apply-stale')));
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('apply-stale'))).onPressed, isNull);
    expect(find.text('会社条件が変更されています。再確認が必要'), findsOneWidget);
    expect(repository.applied, isEmpty);
  });

  testWidgets('compact rates keep key values visible and reveal source months and audit on request', (tester) async {
    final repository = FakeRatesRepository();
    final current = value('health_insurance');
    repository.data = CompanyPayrollRatesData(canEdit: true, items: [
      CompanyPayrollRateItem(id: 'health_insurance', version: 1, value: current, origin: 'manual'),
    ], candidates: [], history: [{
      'item_id': 'health_insurance', 'before_value': null, 'after_value': current,
      'actor_id': 'audit-admin', 'changed_at': '2026-10-09T12:00:00Z',
    }]);
    await openPage(tester, repository);
    expect(find.text('全体 1.3%'), findsOneWidget);
    expect(find.text('従業員負担 0.5%'), findsOneWidget);
    expect(find.text('会社負担 0.8%'), findsOneWidget);
    expect(find.text('適用 2026-10'), findsOneWidget);
    expect(find.text('情報元 登録資料'), findsOneWidget);
    expect(find.text('給与対象年月 2026-11'), findsNothing);
    final details = find.byKey(const PageStorageKey('rate-details-health_insurance-current'));
    await reveal(tester, details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text('保険適用年月 2026-10'), findsOneWidget);
    expect(find.text('給与対象年月 2026-11'), findsOneWidget);
    expect(find.text('支払年月 2026-11'), findsOneWidget);
    expect(find.text('情報元を開く'), findsOneWidget);
    expect(find.text('変更者 audit-admin'), findsNothing);
    final history = find.byKey(const PageStorageKey('payroll-rate-history'));
    await reveal(tester, history);
    await tester.tap(history);
    await tester.pumpAndSettle();
    expect(find.text('変更者 audit-admin'), findsOneWidget);
    expect(find.text('変更日時 2026-10-09T12:00:00Z'), findsOneWidget);
  });

  testWidgets('scope remains unregistered after cancel; confirmed save preserves null selections', (tester) async {
    final repository = FakeRatesRepository();
    await openPage(tester, repository);
    expect(find.text('会社条件は未登録です'), findsOneWidget);
    await reveal(tester, find.text('会社の適用条件を編集'));
    await tester.tap(find.text('会社の適用条件を編集'));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final refresh = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,
      '確認値を再読み込み', skipOffstage: false));
    expect(refresh.onPressed, isNull);
    await tester.tap(find.text('会社条件を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repository.scopes, isEmpty);
    await reveal(tester, find.text('会社の適用条件を編集'));
    await tester.tap(find.text('会社の適用条件を編集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('会社条件を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認して保存'));
    await tester.pumpAndSettle();
    expect(repository.scopes.single, {'insurer': 'unconfigured', 'prefecture': null, 'employment_business': null});
    expect(repository.saved, isEmpty);
    expect(repository.applied, isEmpty);
  });

  testWidgets('custom item preserves independent shares and requires manual confirmation', (tester) async {
    final repository = FakeRatesRepository();
    await openPage(tester, repository);
    await reveal(tester, find.text('料率項目を追加'));
    await tester.tap(find.text('料率項目を追加'));
    await tester.pumpAndSettle();
    for (final entry in {
      'label': '会社独自料率', 'total': '1.3', 'employee': '0.5', 'employer': '0.8',
      'insurance_month': '2026-10', 'payroll_month': '2026-11', 'payment_month': '2026-11',
      'publisher': '管理者設定', 'url': 'https://example.org/rates',
    }.entries) {
      final field = find.byKey(ValueKey('rate-field-${entry.key}'));
      await reveal(tester, field);
      await tester.enterText(field, entry.value);
    }
    await reveal(tester, find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('入力内容を確認'));
    await tester.pumpAndSettle();
    expect(repository.saved, isEmpty);
    expect(find.text(payrollRateConfirmation), findsOneWidget);
    await tester.tap(find.text('確認して適用'));
    await tester.pumpAndSettle();
    expect(repository.saved, hasLength(1));
    final saved = repository.saved.single;
    expect(saved['item_id'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(saved['value']['employee'], 500000);
    expect(saved['value']['employer'], 800000);
    expect(saved['value']['total'], 1300000);
    expect(saved['value']['source']['document_hash'], 'admin-manual-entry');
  });
  testWidgets('custom uncertain write stays blocked through old reads until exact committed ID is found', (tester) async {
    final repository = FakeRatesRepository()..failAfterSend = true;
    await openPage(tester, repository);
    await reveal(tester, find.text('料率項目を追加'));
    await tester.tap(find.text('料率項目を追加'));
    await tester.pumpAndSettle();
    for (final entry in {
      'label': '会社独自料率', 'total': '1.3', 'employee': '0.5', 'employer': '0.8',
      'insurance_month': '2026-10', 'payroll_month': '2026-11', 'payment_month': '2026-11',
      'publisher': '管理者設定', 'url': 'https://example.org/rates',
    }.entries) {
      final field = find.byKey(ValueKey('rate-field-${entry.key}'));
      await reveal(tester, field);
      await tester.enterText(field, entry.value);
    }
    await reveal(tester, find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('入力内容を確認'));
    await tester.pumpAndSettle();
    expect(repository.saved, isEmpty);
    expect(find.text(payrollRateConfirmation), findsOneWidget);
    await tester.tap(find.text('確認して適用'));
    await tester.pumpAndSettle();
    expect(repository.saved, hasLength(1));
    final saved = repository.saved.single;
    expect(saved['item_id'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(saved['value']['employee'], 500000);
    expect(saved['value']['employer'], 800000);
    expect(saved['value']['total'], 1300000);
    expect(saved['value']['source']['document_hash'], 'admin-manual-entry');
    Future<void> refresh() async {
      await reveal(tester, find.text('確認値を再読み込み'));
      await tester.tap(find.text('確認値を再読み込み'));
      await tester.pumpAndSettle();
    }
    Future<void> expectBlocked() async {
      await reveal(tester, find.text('料率項目を追加'));
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '料率項目を追加')).onPressed, isNull);
      expect(repository.saved, hasLength(1));
    }
    await expectBlocked();
    await refresh(); // The first mutation has not committed: absence is not rejection.
    await expectBlocked();
    repository.failRead = true;
    await refresh();
    expect(find.text('編集'), findsNothing);
    repository.failRead = false;
    repository.commitSentCustom();
    await refresh();
    expect(find.text('保存済みの設定を確認しました'), findsOneWidget);
    await reveal(tester, find.text('料率項目を追加'));
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '料率項目を追加')).onPressed, isNotNull);
    expect(repository.saved, hasLength(1));
  });

  test('only exact missing read RPC becomes unavailable; permission and network remain errors', () async {
    for (final error in [
      const PostgrestException(message: 'Could not find public.read_company_payroll_rates', code: 'PGRST202'),
      const PostgrestException(message: 'function read_company_payroll_rates does not exist', code: '42883'),
    ]) {
      final repository = SupabaseCompanyPayrollRatesRepository(invoke: (_, _) async => throw error);
      await expectLater(repository.read('company'), throwsA(isA<PayrollRatesUnavailable>()));
    }
    for (final error in [
      const PostgrestException(message: 'read_company_payroll_rates denied', code: '42501'),
      const PostgrestException(message: 'other_function missing', code: 'PGRST202'),
      StateError('offline'),
    ]) {
      final repository = SupabaseCompanyPayrollRatesRepository(invoke: (_, _) async => throw error);
      await expectLater(repository.read('company'), throwsA(same(error)));
    }
  });

  test('pending writes require exact ID version origin and values, including zero', () {
    final requested = value('health_insurance', employee: 0, employer: 0);
    final pending = PayrollRatePendingWrite(companyId: 'company', itemId: 'health_insurance',
      expectedVersion: 2, value: requested, origin: 'manual');
    CompanyPayrollRatesData data(String id, int version, String origin, Map<String, dynamic> v) =>
      CompanyPayrollRatesData(items: [CompanyPayrollRateItem(id: id, version: version,
        origin: origin, value: v)], candidates: [], history: []);
    expect(pending.matches(data('health_insurance', 2, 'manual', requested)), isFalse);
    expect(pending.matches(data('health_insurance', 4, 'manual', requested)), isFalse);
    expect(pending.matches(data('other', 3, 'manual', requested)), isFalse);
    expect(pending.matches(data('health_insurance', 3, 'official_candidate', requested)), isFalse);
    expect(pending.matches(data('health_insurance', 3, 'manual', value('health_insurance'))), isFalse);
    expect(pending.matches(data('health_insurance', 3, 'manual', requested)), isTrue);
    final scope = PayrollRatePendingWrite(companyId: 'company', expectedVersion: 1,
      value: {'insurer': 'unconfigured', 'prefecture': null, 'employment_business': null});
    expect(scope.matches(const CompanyPayrollRatesData(items: [], candidates: [], history: [])), isFalse);
    expect(scope.matches(CompanyPayrollRatesData(items: [], candidates: [], history: [],
      companyScope: CompanyPayrollRateScope(version: 2, value: scope.value,
        updatedBy: null, updatedAt: 'now'))), isTrue);
  });

  testWidgets('missing RPC explains unavailable without displaying unset editable inputs', (tester) async {
    final repository = FakeRatesRepository()..unavailable = true;
    await openPage(tester, repository);
    expect(find.text('準備中：この会社では料率設定をまだ利用できません。'), findsOneWidget);
    expect(find.text('編集'), findsNothing);
    expect(find.text('未設定'), findsNothing);
    repository.unavailable = false;
    await tester.tap(find.text('確認値を再読み込み'));
    await tester.pumpAndSettle();
    expect(find.text('未設定'), findsWidgets);
  });

  testWidgets('scope response loss gates all writes and exact read restores viewer only', (tester) async {
    final repository = FakeRatesRepository()..failAfterSend = true;
    await openPage(tester, repository);
    await tester.tap(find.text('会社の適用条件を編集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('会社条件を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認して保存'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '会社の適用条件を編集')).onPressed, isNull);
    repository.data = CompanyPayrollRatesData(canEdit: false, items: [],
      candidates: [], history: [], companyScope: repository.data.companyScope);
    await tester.tap(find.text('確認値を再読み込み'));
    await tester.pumpAndSettle();
    expect(find.text('保存済みの設定を確認しました'), findsOneWidget);
    expect(find.text('会社の適用条件を編集'), findsNothing);
    expect(find.text('編集'), findsNothing);
    expect(repository.scopes, hasLength(1));
  });

  test('restarted durable store keeps ID and isolates actor/company; old actor cannot clear', () async {
    final directory = await Directory.systemTemp.createTemp('sko-rate-pending-');
    addTearDown(() => directory.delete(recursive: true));
    var actor = 'actor-a';
    final initial = FilePayrollRatePendingStore(actorId: () => actor, directory: () async => directory);
    final operation = PayrollRatePendingWrite(companyId: 'company', expectedVersion: 0,
      itemId: 'original-uuid', origin: 'manual', value: value('custom'));
    await initial.write(operation);
    final restarted = FilePayrollRatePendingStore(actorId: () => actor, directory: () async => directory);
    expect((await restarted.read('company'))!.itemId, 'original-uuid');
    expect(await restarted.read('other-company'), isNull);
    actor = 'actor-b';
    await expectLater(initial.clear(operation), throwsStateError);
    expect(await FilePayrollRatePendingStore(actorId: () => actor, directory: () async => directory).read('company'), isNull);
    actor = 'actor-a';
    expect((await FilePayrollRatePendingStore(actorId: () => actor, directory: () async => directory).read('company'))!.itemId, 'original-uuid');
    await restarted.clear(operation);
    expect(await restarted.read('company'), isNull);
  });

  testWidgets('restored unknown custom stays blocked on reopening and old read', (tester) async {
    final repository = FakeRatesRepository();
    repository.pendingStore.pending = PayrollRatePendingWrite(companyId: 'company',
      expectedVersion: 0, itemId: 'original-uuid', origin: 'manual', value: value('custom'));
    await openPage(tester, repository);
    await reveal(tester, find.text('料率項目を追加'));
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '料率項目を追加')).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    await openPage(tester, repository);
    await reveal(tester, find.text('料率項目を追加'));
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '料率項目を追加')).onPressed, isNull);
    expect(repository.saved, isEmpty);
    repository.data = CompanyPayrollRatesData(canEdit: true, items: [
      CompanyPayrollRateItem(id: 'original-uuid', version: 1, origin: 'manual', value: value('custom')),
    ], candidates: [], history: []);
    await reveal(tester, find.text('確認値を再読み込み'));
    await tester.tap(find.text('確認値を再読み込み'));
    await tester.pumpAndSettle();
    expect(repository.pendingStore.pending, isNull);
  });

  testWidgets('failed durable record prevents scope RPC transmission', (tester) async {
    final repository = FakeRatesRepository();
    repository.pendingStore.failWrite = true;
    await openPage(tester, repository);
    await tester.tap(find.text('会社の適用条件を編集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('会社条件を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認して保存'));
    await tester.pumpAndSettle();
    expect(repository.scopes, isEmpty);
    expect(repository.saved, isEmpty);
  });

  testWidgets('old-company delayed cleanup cannot unlock new-company pending write', (tester) async {
    final oldRepository = FakeRatesRepository();
    final gate = Completer<void>();
    oldRepository.pendingStore.clearGate = gate;
    await openPage(tester, oldRepository);
    await tester.tap(find.text('会社の適用条件を編集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('会社条件を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認して保存'));
    await tester.pumpAndSettle();
    final newRepository = FakeRatesRepository();
    newRepository.pendingStore.pending = PayrollRatePendingWrite(companyId: 'new-company',
      expectedVersion: 0, itemId: 'pending-new', origin: 'manual', value: value('custom'));
    await tester.pumpWidget(MaterialApp(home: CompanyPayrollRatesPage(companyId: 'new-company',
      repository: newRepository, pendingStore: newRepository.pendingStore)));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('保存結果が不明です。設定を再読み込みして確認するまで、変更操作を停止しています。'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '会社の適用条件を編集')).onPressed, isNull);
    expect(newRepository.pendingStore.pending!.itemId, 'pending-new');
    expect(newRepository.scopes, isEmpty);
  });

  test('two store instances serialize writes and cleanup rejects a different operation', () async {
    final directory = await Directory.systemTemp.createTemp('sko-rate-pending-');
    addTearDown(() => directory.delete(recursive: true));
    final a = FilePayrollRatePendingStore(actorId: () => 'actor', directory: () async => directory);
    final b = FilePayrollRatePendingStore(actorId: () => 'actor', directory: () async => directory);
    final first = PayrollRatePendingWrite(companyId: 'company', expectedVersion: 0,
      itemId: 'first-id', origin: 'manual', value: value('custom'));
    final second = PayrollRatePendingWrite(companyId: 'company', expectedVersion: 0,
      itemId: 'second-id', origin: 'manual', value: value('custom'));
    var successfulWrites = 0;
    Future<void> attempt(FilePayrollRatePendingStore store, PayrollRatePendingWrite record) async {
      try {
        await store.write(record);
        successfulWrites++;
      } on StateError {
        // Caller must not send its RPC if durable preparation is rejected.
      }
    }
    await Future.wait([attempt(a, first), attempt(b, second)]);
    expect(successfulWrites, 1);
    final stored = (await a.read('company'))!;
    expect(stored.itemId, 'first-id');
    await expectLater(b.clear(second), throwsStateError);
    expect((await b.read('company'))!.itemId, 'first-id');
    await a.clear(stored);
    expect(await b.read('company'), isNull);
  });

  test('only fully received explicit SQL rejection codes release a pending write', () async {
    for (final code in ['22023', '40001', '23505', '42501']) {
      final repository = SupabaseCompanyPayrollRatesRepository(invoke: (_, _) async =>
        throw PostgrestException(message: 'transaction rejected', code: code));
      await expectLater(repository.saveManual(companyId: 'company', itemId: 'health_insurance',
        expectedVersion: 0, value: value('health_insurance')),
        throwsA(isA<PayrollRateWriteRejected>().having((e) => e.code, 'code', code)));
    }
    for (final error in [
      const PostgrestException(message: 'unknown error', code: 'XX000'),
      const PostgrestException(message: 'API timeout', code: 'PGRST003'),
      TimeoutException('offline'), const FormatException('unreadable response'),
    ]) {
      final repository = SupabaseCompanyPayrollRatesRepository(invoke: (_, _) async => throw error);
      await expectLater(repository.saveManual(companyId: 'company', itemId: 'health_insurance',
        expectedVersion: 0, value: value('health_insurance')), throwsA(same(error)));
    }
  });

  testWidgets('duplicate label SQL rejection reloads and permits a corrected new label', (tester) async {
    final repository = FakeRatesRepository()..rejectManual = true;
    await openPage(tester, repository);
    Future<void> submit(String label) async {
      await reveal(tester, find.text('料率項目を追加'));
      await tester.tap(find.text('料率項目を追加'));
      await tester.pumpAndSettle();
      for (final entry in {
        'label': label, 'total': '1.3', 'employee': '0.5', 'employer': '0.8',
        'insurance_month': '2026-10', 'payroll_month': '2026-11', 'payment_month': '2026-11',
        'publisher': '管理者設定', 'url': 'https://example.org/rates',
      }.entries) {
        final field = find.byKey(ValueKey('rate-field-${entry.key}'));
        await reveal(tester, field);
        await tester.enterText(field, entry.value);
      }
      await reveal(tester, find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('入力内容を確認'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認して適用'));
      await tester.pumpAndSettle();
    }
    await submit('重複名称');
    expect(repository.manualAttempts, 1);
    expect(repository.saved, isEmpty);
    expect(repository.pendingStore.pending, isNull);
    await reveal(tester, find.text('料率項目を追加'));
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '料率項目を追加')).onPressed, isNotNull);
    repository.rejectManual = false;
    await submit('修正した名称');
    expect(repository.manualAttempts, 2);
    expect(repository.saved.single['value']['label'], '修正した名称');
    expect(repository.pendingStore.pending, isNull);
  });

  test('flushed temporary record recovers after restart; malformed record stays closed', () async {
    final directory = await Directory.systemTemp.createTemp('sko-rate-pending-crash-');
    addTearDown(() => directory.delete(recursive: true));
    FilePayrollRatePendingStore create() => FilePayrollRatePendingStore(
      actorId: () => 'actor', directory: () async => directory);
    final operation = PayrollRatePendingWrite(companyId: 'company', expectedVersion: 0,
      itemId: 'original-id', origin: 'manual', value: value('custom'));
    await create().write(operation);
    final record = (await Directory('${directory.path}/payroll-rate-pending-v1').list().toList())
      .whereType<File>().singleWhere((file) => file.path.endsWith('.json'));
    final temporary = await record.rename('${record.path}.tmp');
    expect((await create().read('company'))!.itemId, 'original-id');
    expect(await temporary.exists(), isFalse);
    expect(await record.exists(), isTrue);
    await record.rename(temporary.path);
    await temporary.writeAsString('{"incomplete":', flush: true);
    await expectLater(create().read('company'), throwsFormatException);
    await expectLater(create().write(operation), throwsFormatException);
    expect(await temporary.exists(), isTrue);
    expect(await record.exists(), isFalse);
  });

  test('file flush preparation failure cannot produce a recovery record', () async {
    final directory = await Directory.systemTemp.createTemp('sko-rate-pending-failure-');
    addTearDown(() => directory.delete(recursive: true));
    final blocked = File('${directory.path}/not-a-directory');
    await blocked.writeAsString('occupied', flush: true);
    final store = FilePayrollRatePendingStore(actorId: () => 'actor',
      directory: () async => Directory(blocked.path));
    await expectLater(store.write(PayrollRatePendingWrite(companyId: 'company',
      expectedVersion: 0, itemId: 'one', origin: 'manual', value: value('custom'))),
      throwsA(isA<FileSystemException>()));
  });

}
