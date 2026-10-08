import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily report supports either one site or one route destination', () {
    final repo = File(
      'lib/features/daily_reports/daily_report_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/daily_reports/daily_report_page.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20261003004500_complete_route_daily_report_flow.sql',
    ).readAsStringSync();

    expect(repo, contains("'daily_report_clocked_in_destinations'"));
    expect(repo, contains("'save_daily_report_destination_draft'"));
    expect(repo, contains("'p_route_assignment_id': routeAssignmentId"));
    expect(repo, contains("'route_assignment_id'"));
    expect(page, contains("'現場／ルート'"));
    expect(
      RegExp(
        r"group\.routeAssignmentId\s*==\s*null\s*\?\s*group\.siteName\s*:\s*SkoLanguageController\.trParams\(\s*'ルート：\{name\}',\s*\{\s*'name':\s*group\.siteName\s*,?\s*\}\s*,?\s*\)",
      ).hasMatch(page),
      isTrue,
      reason: 'Only route destinations receive the translated route prefix; the registered destination name is passed unchanged.',
    );
    expect(page, contains('_routeAssignmentId = group.routeAssignmentId'));
    expect(page, contains('initialRouteAssignmentId'));

    expect(
      migration,
      contains('daily_reports_company_route_date_uq'),
    );
    expect(
      migration,
      contains("((p_site_id is null) = (p_route_assignment_id is null))"),
    );
    expect(
      migration,
      contains(
        'a.route_assignment_id is not distinct from v_route',
      ),
    );
    expect(
      migration,
      contains(
        'ae.route_assignment_id is not distinct from v_route_id',
      ),
    );
  });

  test('dual signatures remain the only daily-report finalization path', () {
    final repo = File(
      'lib/features/daily_reports/daily_report_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/daily_reports/daily_report_page.dart',
    ).readAsStringSync();

    expect(repo, contains("'save_daily_report_signature'"));
    expect(repo, contains("'p_role': 'representative'"));
    expect(repo, contains("'p_role': 'supervisor'"));
    expect(page, contains("'報告者サイン'"));
    expect(page, contains("'責任者サイン'"));
    expect(
      RegExp(r'Future<void> _signReporter').allMatches(page).length,
      1,
    );
  });
}
