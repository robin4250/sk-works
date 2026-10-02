import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('help catalog covers restored menu and role visibility', () {
    final catalog =
        File('lib/features/help/menu_help_catalog.dart').readAsStringSync();
    final page = File('lib/features/help/help_page.dart').readAsStringSync();
    final manual =
        File('lib/features/help/manual_content.dart').readAsStringSync();

    for (final key in [
      'attendance',
      'daily_report',
      'chat',
      'site_register',
      'people',
      'employee_register',
      'payroll',
      'payroll_settings',
      'payroll_adjustments',
      'qualifications',
      'documents',
      'company_documents',
      'company_deliveries',
      'invoices',
      'admin_sites',
      'site_map',
      'vehicle_routes',
      'profile',
      'appearance',
      'settings',
      'help',
    ]) {
      expect(catalog, contains("key: '$key'"));
    }

    expect(catalog, contains('visibleKeys == null || visibleKeys.contains'));
    expect(page, contains('利用権限：'));
    expect(page, contains('visibleFeatureKeys'));
    expect(manual, isNot(contains('現場と人員・請求・権限')));
  });
}
