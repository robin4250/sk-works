import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_insurance_evidence_card.dart';
import 'fixtures/payroll_insurance_evidence_fixture.dart';

void main() {
  testWidgets('payslip exposes the same stored period, independent bases and rates on demand', (t) async {
    final detail = insuranceEvidenceFixture(); final before = jsonEncode(detail);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: PayrollInsuranceEvidenceCard(detail: detail, month: '2026-10-01')))));
    expect(find.text('保険料の計算根拠'), findsOneWidget);
    expect(find.textContaining('R8.4〜R8.6'), findsNothing);
    await t.tap(find.text('保険料の計算根拠')); await t.pumpAndSettle();
    expect(find.textContaining('R8.4〜R8.6'), findsOneWidget);
    expect(find.text('標準報酬月額 ¥320,000 × 4.925% ＝ ¥15,760'), findsOneWidget);
    expect(find.text('標準報酬月額 ¥340,000 × 9.15% ＝ ¥31,110'), findsOneWidget);
    expect(find.text('当月対象賃金 ¥340,000 × 0.5% ＝ ¥1,700'), findsOneWidget);
    expect(find.textContaining('採用関係は未記録'), findsOneWidget);
    expect(jsonEncode(detail), before);
    expect(t.takeException(), isNull);
  });
  testWidgets('unregistered evidence is not displayed as a zero-premium calculation', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body:
      PayrollInsuranceEvidenceCard(detail: {}, month: '2026-10-01'))));
    expect(find.text('保険料の計算根拠'), findsNothing);
    expect(find.textContaining('¥0'), findsNothing);
  });
  testWidgets('minimum and maximum saved equations remain collapsed until tapped', (t) async {
    for (final values in [
      (58000, 88000, '標準報酬月額 ¥58,000 × 5% ＝ ¥2,900',
        '標準報酬月額 ¥88,000 × 9.15% ＝ ¥8,052'),
      (1390000, 650000, '標準報酬月額 ¥1,390,000 × 5% ＝ ¥69,500',
        '標準報酬月額 ¥650,000 × 9.15% ＝ ¥59,475'),
    ]) {
      final detail = insuranceBoundaryEvidenceFixture(healthBase: values.$1, pensionBase: values.$2);
      final before = jsonEncode(detail);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: PayrollInsuranceEvidenceCard(key: ValueKey(values.$1), detail: detail, month: '2026-10-01')))));
      await t.pumpAndSettle();
      expect(find.text(values.$3), findsNothing);
      expect(find.text(values.$4), findsNothing);
      await t.tap(find.text('保険料の計算根拠')); await t.pumpAndSettle();
      expect(find.text(values.$3), findsOneWidget);
      expect(find.text(values.$4), findsOneWidget);
      expect(jsonEncode(detail), before);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }
  });

}
