import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payroll rates entry retains its access and route with one outline', () {
    final source = File('lib/features/settings/settings_page.dart').readAsStringSync();
    final start = source.indexOf('if (_canReadPayrollRates && _companyId != null)');
    expect(start, greaterThanOrEqualTo(0));
    final end = source.indexOf('const SizedBox(height: 16)', start);
    expect(end, greaterThan(start));
    final entry = source.substring(start, end);
    expect(entry, contains('会社共通の税率・保険料率'));
    expect(entry, contains('CompanyPayrollRatesPage('));
    expect(entry, contains('companyId: _companyId!'));
    expect(RegExp(r'side:\s*BorderSide\(').allMatches(entry), hasLength(1));
    expect(entry, isNot(contains('border: Border.all(')));
  });
  test('company data retains rates but common allowances live in payroll entry', () {
    final source = File('lib/features/settings/settings_page.dart').readAsStringSync();
    expect(source, isNot(contains("title: const Text('会社共通手当')")));
    expect(source, isNot(contains('CompanyCommonAllowanceEntryPage(')));
    expect(source, isNot(contains('CompanyAllowanceIdentityPage(')));
    expect(source, contains('CompanyRateSettingsPage(companyId: _companyId)'));
    expect(source, contains('消費税・福利厚生費・旧単価'));
    final entry = File('lib/features/payroll/company_common_allowance_entry_page.dart').readAsStringSync();
    expect(entry, contains('CompanyAllowanceIdentityPage(companyId: selected.companyId)'));
    expect(entry, contains('登録済み項目管理'));
    expect(source, contains("_canManageCompany = role == 'owner' || role == 'admin';"));
    expect(source, contains("_canReadPayrollRates = _canManageCompany || role == 'viewer';"));
  });
}
