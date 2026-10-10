import 'dart:async';
import 'package:sk_works/features/settings/payroll_rate_month_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_payroll_rates_repository.dart';
import 'company_payroll_rates_page_test.dart' as fixture;

class FetchRepository extends fixture.FakeRatesRepository implements OfficialCompanyPayrollRateFetcher {
  @override
  String officialFetchActor = 'actor';
  int fetches = 0;
  bool failFetch = false;
  Completer<List<String>>? gate;
  Map<String,String>? months;
  FetchRepository({bool canEdit = true}) {
    data = CompanyPayrollRatesData(canEdit: canEdit,
      items: [CompanyPayrollRateItem(id:'health_insurance', version:1, value:fixture.value('health_insurance'), origin:'manual')],
      candidates:[],history:[],companyScope:const CompanyPayrollRateScope(version:1,value:{'insurer':'kyokai','prefecture':'東京都','employment_business':'general'},updatedBy:'admin',updatedAt:'2026-10-10'));
  }
  @override
  Future<List<String>> fetchOfficial(String companyId, Map<String,String> requestedMonths) async {
    fetches++; months = requestedMonths;
    if (failFetch) throw StateError('network');
    if (gate != null) return gate!.future;
    data = CompanyPayrollRatesData(canEdit:data.canEdit,items:data.items,
      candidates:[CompanyPayrollRateCandidate(id:'official',itemId:'health_insurance',value:fixture.value('health_insurance',employee:600000),checkedAt:'2026-10-10',scopeVersion:1)],history:[],companyScope:data.companyScope);
    return [];
  }
}
Future<void> fetch(WidgetTester tester) async {
  final button = find.text('最新の公式料率を取得');
  await fixture.reveal(tester,button);
  await tester.tap(button); await tester.pumpAndSettle();
  for (final field in ['insurance_month','payroll_month','payment_month']) {
    await tester.enterText(find.byKey(ValueKey('official-$field')),'2026-10');
  }
  await tester.tap(find.text('取得して比較')); await tester.pumpAndSettle();
}
void main() {
  testWidgets('registration months are prefilled and calendar choice reaches fetch', (tester) async {
    final repository = FetchRepository();
    await fixture.openPage(tester, repository);
    await tester.tap(find.text('最新の公式料率を取得'));
    await tester.pumpAndSettle();
    for (final entry in payrollRateStartingMonths(DateTime.now()).entries) {
      expect(tester.widget<TextFormField>(find.byKey(ValueKey('official-${entry.key}'))).controller!.text, entry.value);
    }
    final field = find.byKey(const ValueKey('official-payment_month'));
    await tester.tap(find.descendant(of: field, matching: find.byTooltip('年月を選択')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2月'));
    await tester.pumpAndSettle();
    final chosen = tester.widget<TextFormField>(field).controller!.text;
    expect(chosen.endsWith('-02'), isTrue);
    await tester.tap(find.text('取得して比較'));
    await tester.pumpAndSettle();
    expect(repository.months!['payment_month'], '$chosen-01');
    expect(repository.saved, isEmpty);
  });

  testWidgets('iPhone width shows saved and fetched rates side by side', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FetchRepository();
    await fixture.openPage(tester,repository);
    await fetch(tester);
    await fixture.reveal(tester,find.byKey(const ValueKey('apply-official')));
    final card = find.ancestor(of: find.byKey(const ValueKey('apply-official')), matching:find.byType(Card));
    final current = find.descendant(of:card,matching:find.text('現在設定値'));
    final candidate = find.descendant(of:card,matching:find.text('登録済みの確認値'));
    expect(tester.getTopLeft(current).dy,tester.getTopLeft(candidate).dy);
    expect(tester.getTopLeft(current).dx,lessThan(tester.getTopLeft(candidate).dx));
    expect(tester.takeException(),isNull);
  });

  testWidgets('fetch publishes a comparison without applying or saving company rates', (tester) async {
    final repository = FetchRepository();
    await fixture.openPage(tester,repository);
    await fetch(tester);
    expect(repository.fetches,1);
    expect(repository.months!['payment_month'],'2026-10-01');
    expect(repository.saved,isEmpty); expect(repository.applied,isEmpty);
    expect(repository.data.items.single.version,1);
    await fixture.reveal(tester,find.byKey(const ValueKey('apply-official')));
    expect(find.byKey(const ValueKey('apply-official')),findsOneWidget);
  });
  testWidgets('failed official fetch keeps current rate and can retry', (tester) async {
    final repository = FetchRepository()..failFetch = true;
    await fixture.openPage(tester,repository);
    await fetch(tester);
    expect(repository.data.items.single.version,1);
    expect(repository.saved,isEmpty); expect(repository.applied,isEmpty);
    expect(find.textContaining('公式料率を取得できませんでした。'),findsOneWidget);
    repository.failFetch=false;
    await fetch(tester);
    expect(repository.fetches,2);
  });
  testWidgets('viewer can read current settings without a publication button', (tester) async {
    final repository = FetchRepository(canEdit:false);
    await fixture.openPage(tester,repository);
    expect(find.text('最新の公式料率を取得'),findsNothing);
    expect(repository.fetches,0);
  });
}
