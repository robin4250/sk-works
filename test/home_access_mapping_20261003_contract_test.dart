import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home access map matches the fixed four-level button specification', () {
    final app = File('lib/app_v2.dart').readAsStringSync();

    for (final key in const [
      'help',
      'appearance',
      'albums',
      'notes',
      'daily_report',
      'profile',
    ]) {
      expect(app, contains("'$key'"));
    }

    for (final key in const [
      'people',
      'company_deliveries',
      'vehicle_routes',
      'employee_register',
      'approvals',
      'employee_onboarding_approvals',
      'documents',
      'employee_qualifications',
      'signatures',
    ]) {
      expect(app, contains("'$key'"));
    }

    for (final key in const [
      'invoices',
      'payroll_settings',
      'payroll_adjustments',
      'attendance_list',
    ]) {
      expect(app, contains("'$key'"));
    }

    for (final key in const [
      'admin_sites',
      'company_documents',
      'site_map',
      'today_line',
    ]) {
      expect(app, contains("'$key'"));
    }

    expect(app, contains("label: SkoLanguageController.tr('出勤表一覧')"));
    expect(app, contains("label: SkoLanguageController.tr('社員データ')"));
    expect(app, contains("label: SkoLanguageController.tr('車両ルート')"));
    expect(app, contains("label: SkoLanguageController.tr('本日のLINE')"));
    expect(app, contains("label: SkoLanguageController.tr('背景')"));
    expect(app, contains("label: SkoLanguageController.tr('資格登録')"));
    expect(app, contains("label: SkoLanguageController.tr('従業員資格')"));
    expect(app, contains("key: 'settings'"));
    expect(app, contains('homeEligible: false'));
  });
}
