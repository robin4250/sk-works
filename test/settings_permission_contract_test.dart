import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remaining company setting navigation retains owner/admin gates without company writes', () {
    final source = File('lib/features/settings/settings_page.dart')
        .readAsStringSync();
    expect(
      source,
      contains("_canManageCompany = role == 'owner' || role == 'admin';"),
    );
    expect(source, contains('if (_canManageCompany)'));
    expect(
      source,
      contains(
        'CompanyAllowanceIdentityEntry(companyId: _companyId!, canManageCompany: _canManageCompany)',
      ),
    );
    expect(source, isNot(contains(".from('companies').update(")));
    expect(source, isNot(contains('settings_company_name')));
    expect(source, isNot(contains('settings_invoice_detail_mode')));
  });
  test('company data remains the company name authority for new document settings', () {
    final sql = File(
      'supabase/migrations/20261003003500_add_company_data_profile.sql',
    ).readAsStringSync();
    expect(sql, contains("'name',coalesce(v.name,'')"));
    expect(sql, contains("set name=nullif(trim(coalesce(p_name,'')),'')"));
    final repository = File(
      'lib/features/people/company_submitted_document_repository.dart',
    ).readAsStringSync();
    expect(repository, contains("rpc('company_data_state')"));
    expect(repository, contains("'save_company_data'"));
    final invoice = File(
      'lib/features/invoices/invoice_settings_repository.dart',
    ).readAsStringSync();
    expect(invoice, contains(".from('companies')"));
    expect(invoice, contains("companyName: company['name']?.toString() ?? ''"));
    final payment = File(
      'lib/features/payroll/payment_certificate_repository.dart',
    ).readAsStringSync();
    expect(payment, contains(".from('companies')"));
    expect(
      payment,
      contains("payerCompanyName: company['name']?.toString() ?? ''"),
    );
    // Saved invoice/payroll snapshots remain authoritative for existing reports;
    // this change neither replaces those values nor backfills historical data.
    expect(
      invoice,
      contains("companyName: row['company_name']?.toString() ?? ''"),
    );
  });
}
