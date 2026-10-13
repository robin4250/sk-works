import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_payroll_rates_repository.dart';
import 'company_payroll_rates_page_test.dart' as fixture;

class InitialRepository extends fixture.FakeRatesRepository {
  bool stopAfterSecond = false;
  InitialRepository({bool canEdit = true}) {
    data = CompanyPayrollRatesData(canEdit: canEdit, items: [
      CompanyPayrollRateItem(id: 'health_insurance', version: 3,
        value: fixture.value('health_insurance'), origin: 'manual'),
    ], candidates: [], history: [], companyScope: const CompanyPayrollRateScope(
      version: 1, value: {'insurer': 'kyokai', 'prefecture': '東京都', 'employment_business': 'construction'},
      updatedBy: 'admin', updatedAt: '2026-10-10'));
  }
  @override
  Future<void> saveManual({required String companyId, required String itemId,
    required int expectedVersion, required Map<String, dynamic> value}) async {
    expect(expectedVersion, 0);
    validatePayrollRateValue(value);
    await super.saveManual(companyId: companyId, itemId: itemId, expectedVersion: expectedVersion, value: value);
    data = CompanyPayrollRatesData(canEdit: data.canEdit,
      items: [...data.items, CompanyPayrollRateItem(id: itemId, version: 1, value: value, origin: 'manual')],
      candidates: [], history: [], companyScope: data.companyScope);
    if (stopAfterSecond && saved.length == 2) throw StateError('response lost');
  }
}

Future<void> openInitial(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('save-starting-rates'));
  await fixture.reveal(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('save missing initial rates without typing preserves existing health', (tester) async {
    final repository = InitialRepository();
    final health = repository.data.items.single;
    await fixture.openPage(tester, repository);
    await openInitial(tester);
    expect(repository.saved, isEmpty);
    await tester.tap(find.text('確認して保存'));
    await tester.pumpAndSettle();
    expect(repository.saved.map((entry) => entry['item_id']),
      ['nursing_insurance', 'pension_insurance', 'employment_insurance', 'child_support']);
    expect(repository.data.items.first, same(health));
    expect(repository.data.items.last.value['employee'], 115000);
    expect(repository.data.items.last.value['employer'], 115000);
    expect(repository.pendingStore.pending, isNull);
    expect(find.byKey(const ValueKey('save-starting-rates')), findsNothing);
  });

  testWidgets('cancel and viewer never write initial rates', (tester) async {
    final repository = InitialRepository();
    await fixture.openPage(tester, repository);
    await openInitial(tester);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repository.saved, isEmpty);
    await fixture.openPage(tester, InitialRepository(canEdit: false));
    expect(find.byKey(const ValueKey('save-starting-rates')), findsNothing);
  });

  testWidgets('lost response stops remaining writes and reload resumes only missing', (tester) async {
    final repository = InitialRepository()..stopAfterSecond = true;
    await fixture.openPage(tester, repository);
    await openInitial(tester);
    await tester.tap(find.text('確認して保存'));
    await tester.pumpAndSettle();
    expect(repository.saved.length, 2);
    expect(repository.pendingStore.pending, isNotNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('save-starting-rates'))).onPressed, isNull);
    await fixture.reveal(tester, find.text('確認値を再読み込み'));
    await tester.tap(find.text('確認値を再読み込み'));
    await tester.pumpAndSettle();
    expect(repository.pendingStore.pending, isNull);
    await openInitial(tester);
    await tester.tap(find.text('確認して保存'));
    await tester.pumpAndSettle();
    expect(repository.saved.map((entry) => entry['item_id']).toSet().length, 4);
    expect(repository.saved.length, 4);
  });
}
