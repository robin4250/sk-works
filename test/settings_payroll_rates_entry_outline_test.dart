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
  test('common allowance entry preserves scoped legacy management and related rates', () {
    final source = File('lib/features/settings/settings_page.dart').readAsStringSync();
    expect(source, isNot(contains("title: const Text('消費税・会社手当設定')")));
    final start = source.indexOf('if (_canManageCompany && _companyId != null && _companyId!.trim().isNotEmpty)');
    final end = source.indexOf('if (_canReadPayrollRates', start);
    final allowance = source.substring(start, end);
    expect(allowance, contains("title: const Text('会社共通手当')"));
    expect(allowance, contains('SecondaryProtectedPage('));
    expect(allowance, contains('CompanyCommonAllowanceEntryPage('));
    expect(allowance, contains('CompanyAllowanceIdentityPage('));
    expect(allowance, contains("child: const Text('登録済み項目管理')"));
    expect(RegExp(r'companyId: _companyId!').allMatches(allowance), hasLength(2));
    final related = source.substring(source.indexOf('child: ExpansionTile('), start);
    expect(related, contains("title: const Text('関連設定')"));
    expect(related, contains('CompanyRateSettingsPage()'));
    expect(related, contains('消費税・福利厚生費・旧単価'));
    expect(source, contains("_canManageCompany = role == 'owner' || role == 'admin';"));
    expect(source, contains("_canReadPayrollRates = _canManageCompany || role == 'viewer';"));
  });

}
