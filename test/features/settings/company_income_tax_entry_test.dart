import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_income_tax_page.dart';
import 'package:sk_works/features/settings/company_payroll_rates_page.dart';
import 'package:sk_works/features/settings/company_payroll_rates_repository.dart';

class EntryRatesRepository implements CompanyPayrollRatesRepository {
  int writes = 0;
  @override
  Future<CompanyPayrollRatesData> read(String companyId) async =>
      const CompanyPayrollRatesData(items: [], candidates: [], history: []);
  @override
  Future<void> saveScope({required String companyId, required int expectedVersion, required Map<String, dynamic> value}) async { writes++; }
  @override
  Future<void> applyCandidate({required String companyId, required String itemId, required String candidateId, required int expectedVersion}) async { writes++; }
  @override
  Future<void> saveManual({required String companyId, required String itemId, required int expectedVersion, required Map<String, dynamic> value}) async { writes++; }
}

void main() {
  testWidgets('income entry preserves company and does not apply or share documents', (tester) async {
    final repository = EntryRatesRepository();
    await tester.pumpWidget(MaterialApp(home: CompanyPayrollRatesPage(companyId: 'selected-company', repository: repository)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('所得税'), 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('所得税'));
    await tester.pumpAndSettle();
    final entry = find.text('年度・PDF資料を管理');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(tester.widget<CompanyIncomeTaxPage>(find.byType(CompanyIncomeTaxPage)).companyId, 'selected-company');
    expect(repository.writes, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CompanyPayrollRatesPage), findsOneWidget);
    expect(repository.writes, 0);
  });
}
