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

class FakeRatesRepository implements CompanyPayrollRatesRepository {
  CompanyPayrollRatesData data = const CompanyPayrollRatesData(items: [], candidates: [], history: []);
  final List<Map<String, dynamic>> scopes = [];
  final List<String> applied = [];
  final List<Map<String, dynamic>> saved = [];
  bool failRead = false;
  bool failSave = false;
  @override
  Future<CompanyPayrollRatesData> read(String companyId) async {
    if (failRead) throw StateError('offline');
    return data;
  }
  @override
  Future<void> saveScope({required String companyId, required int expectedVersion, required Map<String, dynamic> value}) async {
    if (failSave) throw StateError('conflict');
    scopes.add(value);
    data = CompanyPayrollRatesData(items: data.items, candidates: data.candidates, history: data.history,
      companyScope: CompanyPayrollRateScope(version: expectedVersion + 1, value: value, updatedBy: 'admin', updatedAt: '2026-10-09'));
  }
  @override
  Future<void> applyCandidate({required String companyId, required String itemId,
    required String candidateId, required int expectedVersion}) async {
    if (failSave) throw StateError('conflict');
    applied.add(candidateId);
  }
  @override
  Future<void> saveManual({required String companyId, required String itemId,
    required int expectedVersion, required Map<String, dynamic> value}) async {
    if (failSave) throw StateError('conflict');
    saved.add({'item_id': itemId, 'value': value});
  }
}

Future<void> openPage(WidgetTester tester, FakeRatesRepository repository) async {
  await tester.pumpWidget(MaterialApp(home: CompanyPayrollRatesPage(companyId: 'company', repository: repository)));
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
    repository.data = CompanyPayrollRatesData(items: [], candidates: [
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
    repository.data = CompanyPayrollRatesData(items: [], candidates: [
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
    repository.data = CompanyPayrollRatesData(items: [], candidates: [
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
    repository.data = CompanyPayrollRatesData(items: [
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
}
