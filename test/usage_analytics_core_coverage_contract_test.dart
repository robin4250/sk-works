import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core SKO usage analytics coverage stays privacy-bounded', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final migration = File(
      'supabase/migrations/20260930102000_add_master_usage_event_ingestion.sql',
    ).readAsStringSync();

    for (final key in <String>[
      "'home'",
      "'attendance'",
      "'attendance_sheet'",
      "'daily_report'",
      "'payroll'",
      "'invoice'",
      "'chat'",
    ]) {
      expect(migration, contains(key));
    }

    for (final feature in <String>[
      "'clock_in'",
      "'clock_out'",
      "'attendance'",
      "'daily_report'",
      "'payroll'",
      "'invoice'",
      "'chat'",
      "'print'",
      "'company_connection'",
    ]) {
      expect(migration, contains(feature));
    }

    for (final action in <String>[
      "'footer_home' => 'home'",
      "'attendance' || 'attendance_list' => 'attendance_sheet'",
      "'clock_in' || 'clock_out' || 'attendance_verify' || 'workplace_select' || 'attendance_method_vehicle' => 'attendance'",
      "'daily_report' || 'approvals' => 'daily_report'",
      "'payroll' || 'payroll_adjustments' => 'payroll'",
      "'invoices' => 'invoice'",
      "'chat' => 'chat'",
      "'company_deliveries' || 'trade_companies' || 'subcontractors' =>\n        'company_connection'",
    ]) {
      expect(app, contains(action));
    }

    for (final forbidden in <String>[
      'p_metadata',
      'latitude',
      'longitude',
      'phone_number',
      'chat_message',
      'file_contents',
    ]) {
      expect(migration, isNot(contains(forbidden)));
    }
  });
}
