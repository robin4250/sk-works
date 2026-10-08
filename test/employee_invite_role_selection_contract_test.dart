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
    final policy = read('supabase/functions/_shared/employee_invite_policy.mjs');

    expect(
      edge,
      contains(
        "import { employeeInvitePolicy } from '../_shared/employee_invite_policy.mjs'",
      ),
    );
    expect(edge, contains('employeeInvitePolicy(payload, callerRole)'));
    expect(
      edge,
      contains(
        "if ('error' in policy) return json({ error: policy.error }, policy.status)",
      ),
    );
    expect(edge, contains('requestedRole'));
    expect(edge, contains('requestedApprovalAssignee'));
    expect(policy, contains("!['owner', 'admin'].includes(callerRole)"));
    expect(
      policy,
      contains("requestedRole !== 'viewer' || requestedApprovalAssignee ||"),
    );
    expect(policy, contains('replaceApprovalAssigneeUserId !== null'));
    expect(
      policy,
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
    expect(page, contains("child: Text(_tr('閉じる', 'Close'))"));
    expect(page, contains('_currentApprovalAssignees.length >= 3'));
    expect(page, contains('_replaceApprovalAssigneeUserId = replacement'));
    expect(page, contains("requestedRole: _makeSubAdmin ? 'manager' : 'viewer'"));
    final approvalSelection = page.substring(
      page.indexOf('Future<void> _setApprovalAssignee(bool value)'),
      page.indexOf('Future<void> _create()'),
    );
    expect(approvalSelection, contains('if (replacement == null)'));
    expect(approvalSelection, contains('_makeApprovalAssignee = false'));
    expect(approvalSelection, contains('_makeApprovalAssignee = true'));
    expect(approvalSelection, isNot(contains('_makeSubAdmin =')));
  });

  test('onboarding reviewers can see requested role and replacement', () {
    final migration = read(
      'supabase/migrations/20260922024000_add_invite_role_and_approver_selection.sql',
    );
    final page = read(
      'lib/features/auth/employee_onboarding_approvals_page.dart',
    );
    final repository = read(
      'lib/features/auth/employee_onboarding_repository.dart',
    );

    expect(migration, contains('pending_employee_onboarding_review_rows'));
    expect(repository, contains('pending_employee_onboarding_review_rows'));
    expect(page, contains('本登録後の役割'));
    expect(page, contains('承認担当者'));
    expect(page, contains('入れ替え対象'));
  });

  test('home separates employee preregistration from admin initial registration', () {
    final app = read('lib/app_v2.dart');

    expect(app, contains("key: 'employee_register'"));
    expect(app, contains('EmployeeRegistrationPage'));
    expect(app, contains("key: 'initial_registration'"));
    expect(app, contains('EmployeeInitialRegistrationPage'));
    expect(app, contains('if (_isAdmin)'));
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
