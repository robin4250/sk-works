import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('personnel change approvals are reachable from hub and notifications', () {
    final hub = read('lib/features/approvals/approvals_hub_page.dart');
    final notifications =
        read('lib/features/notifications/notifications_page.dart');
    final approvals =
        read('lib/features/people/worker_personnel_change_approvals_page.dart');
    final migration = read(
      'supabase/migrations/20261006192517_worker_personnel_approvers_one_to_three.sql',
    );

    expect(hub, contains('WorkerPersonnelChangeApprovalsPage'));
    expect(hub, contains("'社員個人情報の変更承認'"));
    expect(hub, contains('_personnelChangeCount'));

    expect(notifications, contains("item.actionKey == 'worker_personnel_change'"));
    expect(
      notifications,
      contains("item.actionKey == 'worker_personnel_change_completed'"),
    );
    expect(notifications, contains('initialRequestId: item.actionId'));
    expect(notifications, contains('PeopleCloudPage'));

    expect(approvals, contains('this.initialRequestId'));
    expect(approvals, contains("a['id']?.toString() == targetId"));
    expect(approvals, contains("'承認 \$approvalCount/\$required 名'"));

    expect(migration, contains("'worker_personnel_change'"));
    expect(migration, contains("'worker_personnel_change_completed'"));
    expect(migration, contains('required_approvals'));
  });
}
