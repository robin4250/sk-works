import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('site information requests notify reviewers and route from notifications', () {
    final migration = read(
      'supabase/migrations/20261006204659_site_information_request_notifications.sql',
    );
    final notifications =
        read('lib/features/notifications/notifications_page.dart');
    final approvals =
        read('lib/features/sites/site_information_approvals_page.dart');

    expect(migration, contains('site_information_request_notify_insert'));
    expect(migration, contains("'site_information_request'"));
    expect(migration, contains('site_information_request_notify_result'));
    expect(migration, contains("'site_information_request_result'"));

    expect(notifications, contains("item.actionKey == 'site_information_request'"));
    expect(
      notifications,
      contains("item.actionKey == 'site_information_request_result'"),
    );
    expect(notifications, contains('initialRequestId: item.actionId'));

    expect(approvals, contains('this.initialRequestId'));
    expect(approvals, contains("status == 'pending'"));
    expect(approvals, contains("id == targetId"));
    expect(approvals, contains("status == 'approved'"));
    expect(approvals, contains("status == 'rejected'"));
  });
}
