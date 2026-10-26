import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_official_remuneration_table.dart';
import 'package:sk_works/features/payroll/payroll_standard_remuneration.dart';

import 'fixtures/payroll_official_remuneration_fixture.dart';

void main() {
  test('retrieved health and pension tables agree with every conversion boundary', () {
    for (final pension in [false, true]) {
      final table = PayrollOfficialRemunerationTable.fromRate(officialTableRate(pension: pension))!;
      expect(table.bases.length, pension ? 32 : 50);
      expect(table.minimumYen, pension ? 88000 : 58000);
      expect(table.maximumYen, pension ? 650000 : 1390000);
      expect(table.minimumIncomeExclusiveYen, pension ? 93000 : 63000);
      expect(table.maximumIncomeInclusiveYen, pension ? 635000 : 1355000);
      for (var i = 0; i < table.bases.length; i++) {
        for (final income in [table.lowerBounds[i], if (i > 0) table.lowerBounds[i] - 1]) {
          final actual = PayrollStandardRemuneration.fromMonthlyIncome(income, '2026-10');
          final index = table.lowerBounds.lastIndexWhere((bound) => bound <= income);
          expect(pension ? actual.pensionYen : actual.healthYen, table.bases[index]);
        }
      }
    }
  });
  test('old rates without table metadata remain readable without a retrieval claim', () {
    expect(PayrollOfficialRemunerationTable.fromRate({'source': {'applicability': {'year': '2026'}}}), isNull);
  });
  test('partial, altered, unknown and untrusted official table evidence is rejected', () {
    for (final change in <void Function(Map)>[
      (app) => app.remove('remuneration_bases_csv'),
      (app) => app['remuneration_table_version'] = 'jp-general-2027-v1',
      (app) => app['remuneration_source_url'] = 'https://example.org/table.pdf',
      (app) => app['remuneration_document_hash'] = 'invalid',
      (app) => app['remuneration_effective_from'] = '2026-13-01',
      (app) => app['remuneration_lower_bounds_csv'] = (app['remuneration_lower_bounds_csv'] as String).replaceFirst('63000', '64000'),
      (app) => app['remuneration_bases_csv'] = (app['remuneration_bases_csv'] as String).replaceFirst('1390000', '1355000'),
      (app) => app['remuneration_bases_csv'] = '058000,68000',
      (app) => app['remuneration_extra'] = 'unexpected',
    ]) {
      final rate = officialTableRate();
      change((rate['source'] as Map)['applicability'] as Map);
      expect(() => PayrollOfficialRemunerationTable.fromRate(rate), throwsFormatException);
    }
  });
}
