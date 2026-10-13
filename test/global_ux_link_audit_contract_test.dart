import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu actions keep a route or explicit tab handler', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final menuStart = app.indexOf('List<_MenuAction> get _menuItems');
    final menuEnd = app.indexOf('Widget _homeDashboard');
    final routeStart = app.indexOf('Future<void> _openHomeAction');
    final routeEnd = menuStart;

    expect(menuStart, greaterThan(0));
    expect(menuEnd, greaterThan(menuStart));
    expect(routeStart, greaterThan(0));
    expect(routeEnd, greaterThan(routeStart));

    final menu = app.substring(menuStart, menuEnd);
    final routes = app.substring(routeStart, routeEnd);

    final menuKeys = RegExp(r"key:\s*'([^']+)'")
        .allMatches(menu)
        .map((m) => m.group(1)!)
        .toSet();

    final directCases = RegExp(r"case\s+'([^']+)'")
        .allMatches(routes)
        .map((m) => m.group(1)!)
        .toSet();

    final explicitHandlers = RegExp(r"key\s*==\s*'([^']+)'")
        .allMatches(routes)
        .map((m) => m.group(1)!)
        .toSet();

    final legacyFallback = <String>{
      'invoices',
    };

    final routed = <String>{
      ...directCases,
      ...explicitHandlers,
      ...legacyFallback,
    };

    final missing = menuKeys.difference(routed);
    expect(
      missing,
      isEmpty,
      reason: 'Menu items without an explicit route or documented fallback: $missing',
    );
  });

  test('completed onboarding flow stays localization-aware', () {
    final pages =
        File('lib/features/auth/employee_onboarding_pages.dart').readAsStringSync();
    final scanner =
        File('lib/features/auth/employee_invite_scanner_page.dart').readAsStringSync();

    expect(pages, contains('SkoLanguageController'));
    expect(scanner, contains('SkoLanguageController'));
    expect(pages, contains('Icons.help_outline'));
    expect(scanner, contains('Icons.help_outline'));
  });

  test('high-priority pages remain registered for global UX audit', () {
    const audited = <String>[
      'lib/features/invoices/invoice_cloud_page.dart',
      'lib/features/payroll/payroll_statements_page.dart',
      'lib/features/payroll/payroll_review_page.dart',
      'lib/features/payroll/payment_certificates_page.dart',
      'lib/features/attendance/today_attendance_page.dart',
      'lib/features/attendance/attendance_management_page.dart',
      'lib/features/people/employee_invite_page.dart',
      'lib/features/sites/site_detail_page.dart',
    ];

    for (final path in audited) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}
