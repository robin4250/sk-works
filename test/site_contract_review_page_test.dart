import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/site_contract_review_page.dart';

Map<String, dynamic> proposal(int revision, List<String> companies,
    {String start = '2026-10-01', bool seals = true}) => {
  'id': 'proposal-$revision', 'revision': revision,
  'terms': {'effective_from': start, 'period_start': '2026-10-01',
    'period_end': '2026-11-30', 'final_amount_yen': revision * 10000,
    'base_amount_yen': revision * 10000, 'tax_amount_yen': 0},
  'confirmations': [for (final company in companies) {'company_id': company}],
  'seals': [if (seals) for (final company in companies) {
    'company_id': company, 'actor_id': 'actor-$company',
    'action': company == 'a' ? 'sent' : 'approved',
    'recorded_at': '2026-10-15T01:00:00Z', 'seal_snapshot': {'version': 1},
  }],
};

Future<void> show(WidgetTester tester, List<Map<String, dynamic>> proposals,
    {String viewer = 'a'}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SiteContractReviewContent(
    workspace: {'parent_company_id': 'a', 'child_company_id': 'b', 'proposals': proposals},
    companyId: viewer, today: DateTime(2026, 10, 15),
  ))));
}

void main() {
  testWidgets('pending candidate retains the actual current amount', (tester) async {
    await show(tester, [proposal(2, ['a']), proposal(1, ['a', 'b'])]);
    expect(find.text('契約中・変更承認待ち'), findsOneWidget);
    expect(find.text('第1版・10000円'), findsOneWidget);
    expect(find.text('第2版・20000円'), findsOneWidget);
    expect(find.text('相手会社：押印記録未確認'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
  testWidgets('future approval stays separate until its start date', (tester) async {
    await show(tester, [proposal(2, ['a', 'b'], start: '2026-11-01'),
      proposal(1, ['a', 'b'])]);
    expect(find.text('契約中・変更適用待ち'), findsOneWidget);
    expect(find.text('次回の合意・適用開始待ち'), findsOneWidget);
    expect(find.text('第1版・10000円'), findsOneWidget);
  });
  testWidgets('both saved seals move the approved revision into current agreement', (tester) async {
    await show(tester, [proposal(2, ['a', 'b']), proposal(1, ['a', 'b'])]);
    expect(find.text('契約中'), findsOneWidget);
    expect(find.text('第2版・20000円'), findsOneWidget);
    expect(find.text('契約候補・承認待ち'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
  testWidgets('legacy confirmations never count as immutable seals', (tester) async {
    await show(tester, [proposal(1, ['a', 'b'], seals: false)]);
    expect(find.text('承認待ち'), findsOneWidget);
    expect(find.text('双方の押印記録が揃った現行の合意はありません。'), findsOneWidget);
    expect(find.text('契約中'), findsNothing);
    expect(find.text('自社：押印記録未確認'), findsOneWidget);
  });
  testWidgets('unrelated viewer sees no contract amount or actor', (tester) async {
    await show(tester, [proposal(1, ['a', 'b'])], viewer: 'unrelated');
    expect(find.text('契約当事者を確認できません。'), findsOneWidget);
    expect(find.textContaining('10000'), findsNothing);
    expect(find.textContaining('actor-'), findsNothing);
  });
}
