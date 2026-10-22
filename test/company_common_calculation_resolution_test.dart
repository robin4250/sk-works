import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/company_common_calculation_resolution.dart';
import 'package:sk_works/features/payroll/payroll_company_common_card.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_repository.dart';

void main() {
  Map<String, dynamic> state({Object? resolution}) => {
    'version': 1, 'month': '2026-10-01', 'can_edit': true, 'items': [],
    'company_common': {'contract_version': 1, 'source': {}, 'items': [],
      if (resolution != null) 'resolution': resolution},
  };
  test('old reader response remains compatible and optional reasons are preserved', () {
    expect(PayrollUnitConditions.fromJson(state()).companyCommonResolution, isNull);
    final result = PayrollUnitConditions.fromJson(state(resolution: {
      'blocked': true, 'reasons': [{'code': 'individual_override_unresolved', 'name': '合成手当'}],
      'selection_classification': [],
    }));
    expect(result.companyCommonResolution!.blocked, true);
    expect(CompanyCommonCalculationResolution.reasonLabel(result.companyCommonResolution!.reasons.single),
      '合成手当：会社共通と個別設定の単価が異なります');
  });
  test('malformed reasons never become a successful zero', () {
    for (final bad in [
      {'blocked': 'true', 'reasons': []},
      {'blocked': true, 'reasons': 'bad'},
      {'blocked': false, 'reasons': [{'code': 'individual_override_unresolved'}]},
    ]) {
      expect(() => PayrollUnitConditions.fromJson(state(resolution: bad)), throwsStateError);
    }
  });
  testWidgets('a blocked common setting with no computed rows remains visible with folded reasons', (tester) async {
    final resolution = CompanyCommonCalculationResolution.parse({
      'blocked': true, 'reasons': [{'code': 'individual_override_unresolved', 'name': '合成手当'}],
      'selection_classification': [],
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PayrollCompanyCommonCard(
      items: const [], canEdit: false, resolution: resolution,
      onSave: (_) async {}, onReload: () {},
    ))));
    expect(find.text('共通手当の設定を確認してください'), findsOneWidget);
    await tester.tap(find.text('社内共通手当'));
    await tester.pumpAndSettle();
    expect(find.textContaining('計算を保留しています'), findsOneWidget);
    expect(find.textContaining('合成手当：').hitTestable(), findsNothing);
    await tester.tap(find.byKey(const ValueKey('common-resolution-reasons')));
    await tester.pumpAndSettle();
    expect(find.textContaining('合成手当：').hitTestable(), findsOneWidget);
  });
}
