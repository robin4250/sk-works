import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/resident_tax_repository.dart';
import 'package:sk_works/features/payroll/resident_tax_section.dart';

class FakeResidentTaxRepository implements ResidentTaxRepository {
  ResidentTaxState? state;
  bool failRead = false;
  bool loseReply = false;
  int saves = 0;
  final legacy = 4000;
  @override
  Future<ResidentTaxData> read(String workerId, String month, {String? companyId}) async {
    if (failRead) {
      throw StateError('offline');
    }
    final current = state;
    final eligible = current?.entries.where((entry) => entry.month.compareTo(month) <= 0).toList() ?? [];
    final timeline = current?.mode == 'timeline' && eligible.isNotEmpty;
    return ResidentTaxData(companyId: 'worker-company', state: current, mode: timeline ? 'timeline' : 'legacy',
      amount: timeline ? eligible.last.amount : legacy, effectiveMonth: timeline ? eligible.last.month : null, history: []);
  }
  @override
  Future<ResidentTaxState> save({required String companyId, required String workerId, required int expectedVersion,
    required String mode, required String? cutover, required List<ResidentTaxEntry> entries}) async {
    saves++;
    state = ResidentTaxState(version: expectedVersion + 1, mode: mode, cutover: cutover, entries: entries, updatedBy: 'editor', updatedAt: '2030-05-01');
    if (loseReply) {
      throw StateError('reply lost');
    }
    return state!;
  }
}

Future<void> open(WidgetTester tester, FakeResidentTaxRepository repository, {bool canEdit = true}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16),
    child: ResidentTaxSection(workerId: 'worker', legacyAmount: 4000, canEdit: canEdit, month: '2030-05-01', repository: repository))))));
  await tester.pumpAndSettle();
}
Future<void> futureAmount(WidgetTester tester, String amount) async {
  await tester.enterText(find.byKey(const ValueKey('resident-amount')), amount);
  await tester.enterText(find.byKey(const ValueKey('resident-start')), '2030-06');
  await tester.tap(find.text('住民税だけ保存'));
  await tester.pumpAndSettle();
}

void main() {
  test('future schedule resolves legacy before cutover and preserves explicit zero afterward', () {
    final state = {'version': 1, 'mode': 'timeline', 'cutover_month': '2030-06-01',
      'entries': [{'effective_month': '2030-06-01', 'amount_yen': 0}], 'updated_by': 'editor', 'updated_at': '2030-05-01'};
    final before = ResidentTaxData.fromJson({'state': state, 'resolved': {'mode': 'legacy', 'amount_yen': 4000}, 'history': []}, 'company', '2030-05-01');
    final after = ResidentTaxData.fromJson({'state': state, 'resolved': {'mode': 'timeline', 'effective_month': '2030-06-01', 'amount_yen': 0}, 'history': []}, 'company', '2030-06-01');
    expect(before.amount, 4000);
    expect(after.amount, 0);
    expect(after.mode, 'timeline');
    expect(() => ResidentTaxData.fromJson({'state': state, 'resolved': {'mode': 'legacy', 'amount_yen': 4000}, 'history': []}, 'company', '2030-06-01'), throwsFormatException);
  });
  test('same-month update retains other scheduled months and sorts the schedule', () {
    final entries = residentTaxEntriesWithMonth([const ResidentTaxEntry(month: '2030-06-01', amount: 0), const ResidentTaxEntry(month: '2031-06-01', amount: 9000)],
      const ResidentTaxEntry(month: '2030-06-01', amount: 5000));
    expect(entries.map((entry) => entry.amount), [5000, 9000]);
    expect(entries.map((entry) => entry.month), ['2030-06-01', '2031-06-01']);
  });
  test('worker-company resolution is independent of first company membership', () async {
    final repository = SupabaseResidentTaxRepository(resolveCompany: (workerId) async {
      expect(workerId, 'specialist-visible-worker'); return 'worker-company';
    }, rpc: (_, parameters) async {
      expect(parameters['p_company_id'], 'worker-company');
      return {'state': null, 'resolved': {'mode': 'legacy', 'amount_yen': 4000}, 'history': []};
    });
    final data = await repository.read('specialist-visible-worker', '2030-05-01');
    expect(data.companyId, 'worker-company');
    expect(data.state, isNull);
  });
  test('version or amount mismatch from save never becomes success', () async {
    final repository = SupabaseResidentTaxRepository(rpc: (_, parameters) async => {'version': 1, 'mode': 'timeline', 'cutover_month': '2030-06-01',
      'entries': [{'effective_month': '2030-06-01', 'amount_yen': 8000}], 'updated_by': 'editor', 'updated_at': '2030-05-01'});
    await expectLater(repository.save(companyId: 'company', workerId: 'worker', expectedVersion: 0, mode: 'timeline', cutover: '2030-06-01',
      entries: [const ResidentTaxEntry(month: '2030-06-01', amount: 5000)]), throwsFormatException);
  });
  testWidgets('cancel writes nothing and future registration leaves current resolved amount unchanged', (tester) async {
    final repository = FakeResidentTaxRepository();
    await open(tester, repository);
    await futureAmount(tester, '0');
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repository.saves, 0);
    await futureAmount(tester, '0');
    await tester.tap(find.text('確認して保存'));
    await tester.pumpAndSettle();
    expect(repository.saves, 1);
    expect(repository.state!.entries.single.amount, 0);
    expect(find.text('2030-05の住民税：4000円'), findsOneWidget);
    expect(repository.legacy, 4000);
  });
  testWidgets('121st start month is an input error with no RPC or confirmation', (tester) async {
    final entries = List<ResidentTaxEntry>.generate(120, (index) {
      final year = 2031 + index ~/ 12;
      final month = (index % 12 + 1).toString().padLeft(2, '0');
      return ResidentTaxEntry(month: '$year-$month-01', amount: 5000);
    });
    final repository = FakeResidentTaxRepository()..state = ResidentTaxState(version: 1, mode: 'timeline', cutover: entries.first.month,
      entries: entries, updatedBy: 'editor', updatedAt: '2030-05-01');
    await open(tester, repository);
    await tester.enterText(find.byKey(const ValueKey('resident-amount')), '5000');
    await tester.enterText(find.byKey(const ValueKey('resident-start')), '2030-06');
    await tester.tap(find.text('住民税だけ保存'));
    await tester.pumpAndSettle();
    expect(find.text('開始年月は120件まで登録できます'), findsOneWidget);
    expect(find.text('確認して保存'), findsNothing);
    expect(repository.saves, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('view-only permissions disable both monthly save and restore', (tester) async {
    final repository = FakeResidentTaxRepository()..state = const ResidentTaxState(version: 1, mode: 'timeline', cutover: '2030-06-01',
      entries: [ResidentTaxEntry(month: '2030-06-01', amount: 5000)], updatedBy: 'editor', updatedAt: '2030-05-01');
    await open(tester, repository, canEdit: false);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '住民税だけ保存')).onPressed, isNull);
    await tester.tap(find.text('予約・履歴・従来設定'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '従来の固定額に戻す')).onPressed, isNull);
    expect(repository.saves, 0);
  });
  testWidgets('read error shows retry rather than zero or editable default', (tester) async {
    final repository = FakeResidentTaxRepository()..failRead = true;
    await open(tester, repository);
    expect(find.textContaining('設定を取得できません'), findsOneWidget);
    expect(find.byKey(const ValueKey('resident-amount')), findsNothing);
    repository.failRead = false;
    await tester.ensureVisible(find.text('住民税を再読み込み'));
    await tester.tap(find.text('住民税を再読み込み'));
    await tester.pumpAndSettle();
    expect(find.text('2030-05の住民税：4000円'), findsOneWidget);
  });
  testWidgets('restore confirms preserved old fixed amount and target month', (tester) async {
    final repository = FakeResidentTaxRepository()..state = const ResidentTaxState(version: 1, mode: 'timeline', cutover: '2030-04-01',
      entries: [ResidentTaxEntry(month: '2030-04-01', amount: 6000)], updatedBy: 'editor', updatedAt: '2030-05-01');
    await open(tester, repository);
    await tester.tap(find.text('予約・履歴・従来設定'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('従来の固定額に戻す'));
    await tester.tap(find.text('従来の固定額に戻す'));
    await tester.pumpAndSettle();
    expect(find.textContaining('従来の月額4000円'), findsOneWidget);
    expect(find.textContaining('確認対象年月は2030-05'), findsOneWidget);
    await tester.tap(find.text('確認して保存'));
    await tester.pumpAndSettle();
    expect(repository.state!.mode, 'legacy');
    expect(repository.state!.entries, isEmpty);
    expect(repository.legacy, 4000);
  });
  testWidgets('lost reply blocks save until same version and schedule are confirmed by read', (tester) async {
    final repository = FakeResidentTaxRepository()..loseReply = true;
    await open(tester, repository);
    await futureAmount(tester, '5000');
    await tester.tap(find.text('確認して保存'));
    await tester.pumpAndSettle();
    expect(find.text('住民税を保存しました'), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '住民税だけ保存')).onPressed, isNull);
    await tester.ensureVisible(find.text('住民税を再読み込み'));
    await tester.tap(find.text('住民税を再読み込み'));
    await tester.pumpAndSettle();
    expect(find.text('住民税の保存を確認しました'), findsOneWidget);
    expect(repository.saves, 1);
  });
}
