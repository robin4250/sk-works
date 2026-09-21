import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('invite stores requested role and approval-assignee intent', () {
    final sql = read(
      'supabase/migrations/20260922024000_add_invite_role_and_approver_selection.sql',
    );

    expect(sql, contains('requested_role'));
    expect(sql, contains('requested_approval_assignee'));
    expect(sql, contains('replace_approval_assignee_user_id'));
    expect(sql, contains("requested_role in ('viewer','manager')"));
    expect(sql, contains('approval_assignee_limit_reached'));
    expect(sql, contains('approval_assignee_replacement_invalid'));
    expect(sql, contains('pg_advisory_xact_lock'));
  });

  test('only full admins can request sub-admin or approver at invite time', () {
    final edge = read('supabase/functions/create-employee-invite/index.ts');

    expect(edge, contains('callerRole === "owner" || callerRole === "admin"'));
    expect(edge, contains('requestedRole'));
    expect(edge, contains('requestedApprovalAssignee'));
    expect(
      edge,
      contains('サブ管理者・承認担当者の指定は管理者だけが行えます。'),
    );
    expect(edge, contains('approval_assignee_limit_reached'));
  });

  test('admin invite UI supports fourth-approver replacement popup', () {
    final page = read('lib/features/people/employee_invite_page.dart');

    expect(page, contains('サブ管理者にする'));
    expect(page, contains('承認担当者にする'));
    expect(page, contains('承認担当者は最大3名です'));
    expect(page, contains('この人を外す'));
    expect(page, contains("child: const Text('閉じる')"));
    expect(page, contains('_makeSubAdmin = true'));
  });

  test('home only exposes invite role controls to full admins', () {
    final app = read('lib/app_v2.dart');

    expect(
      app,
      contains('canAssignManagementRole: _identity.isAdmin'),
    );
  });

  test('manuals describe invite-time role and approver selection', () {
    final manual = read('lib/features/help/manual_content.dart');

    expect(manual, contains('従業員登録時に必要なら「サブ管理者にする」をON'));
    expect(manual, contains('4人目なら現在の3名から外す人を選ぶ'));
    expect(
      manual,
      contains('役割・承認担当者の指定は管理者だけが行えます'),
    );
  });
}
