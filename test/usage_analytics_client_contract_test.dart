import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usage analytics client is non-blocking and uses fixed product keys', () {
    final repository = File(
      'lib/features/analytics/usage_analytics_repository.dart',
    ).readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(repository, contains("'record_usage_event'"));
    expect(repository, contains("'p_event_key': eventKey"));
    expect(repository, contains('catch (_)'));
    expect(repository, contains('Analytics must never block normal SKO operation'));

    expect(app, contains('UsageAnalyticsRepository.maybeCreate()'));
    expect(app, contains("_recordCloudUsageForAction(key);"));
    expect(app, contains("eventKey: 'page_open'"));
    expect(app, contains("'clock_in' => 'clock_in'"));
    expect(app, contains("'clock_out' => 'clock_out'"));
    expect(app, contains("'vehicle_routes' => 'vehicle_routes'"));
    expect(app, contains("'company_deliveries' || 'trade_companies' || 'subcontractors'"));
    expect(app, contains("'company_connection'"));

    final permissionCheck = app.indexOf(
      "if (permission != null && !_identity.can(permission))",
    );
    final usageRecord = app.indexOf('_recordCloudUsageForAction(key);');
    expect(permissionCheck, greaterThanOrEqualTo(0));
    expect(usageRecord, greaterThan(permissionCheck));
  });
}
