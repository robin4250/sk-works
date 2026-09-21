import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('employee registration is available to every company member', () {
    final edge = read('supabase/functions/create-employee-invite/index.ts');
    final app = read('lib/app_v2.dart');

    expect(edge, contains('company_members?user_id=eq.'));
    expect(edge, isNot(contains('can_manage_people')));
    expect(app, contains("key: 'employee_register'"));
    expect(app, contains("label: '従業員登録'"));
  });

  test('employee invite supports temporary password share and QR', () {
    final edge = read('supabase/functions/create-employee-invite/index.ts');
    final page = read('lib/features/people/employee_invite_page.dart');
    final scanner =
        read('lib/features/auth/employee_invite_scanner_page.dart');

    expect(edge, contains('temporaryPassword'));
    expect(edge, contains('qrPayload'));
    expect(page, contains('SMS・メッセージなどで共有'));
    expect(page, contains('QrImageView'));
    expect(scanner, contains('sko_employee_invite'));
    expect(scanner, contains('MobileScanner'));
  });

  test('invited user must change primary password before profile', () {
    final gate = read('lib/features/auth/auth_gate.dart');
    final pages = read('lib/features/auth/employee_onboarding_pages.dart');
    final repo = read('lib/features/auth/secure_onboarding_repository.dart');

    expect(gate, contains('_GateStatus.employeePassword'));
    expect(gate, contains('_GateStatus.employeeProfile'));
    expect(repo, contains('mark_employee_initial_password_changed'));
    expect(pages, contains('本パスワードを設定して次へ'));
  });

  test('employee profile requires identity and emergency information', () {
    final sql = read(
      'supabase/migrations/20260922004500_add_employee_onboarding_profile_and_approval.sql',
    );
    final pages = read('lib/features/auth/employee_onboarding_pages.dart');

    for (final field in [
      'address',
      'blood_type',
      'family_composition',
      'emergency_relation',
      'emergency_name',
      'emergency_phone',
      'emergency_address',
      'portrait_path',
      'my_number_front_path',
      'my_number_back_path',
    ]) {
      expect(sql, contains(field));
    }

    expect(pages, contains('マイナンバーカード 表面'));
    expect(pages, contains('マイナンバーカード 裏面'));
    expect(pages, contains('本人の写真'));
    expect(pages, contains('家族構成'));
    expect(pages, contains('緊急連絡先'));
  });

  test('one reviewer approval completes employee registration', () {
    final sql = read(
      'supabase/migrations/20260922004500_add_employee_onboarding_profile_and_approval.sql',
    );
    final page =
        read('lib/features/auth/employee_onboarding_approvals_page.dart');

    expect(sql, contains('approve_employee_onboarding'));
    expect(sql, contains("values(v_invite.company_id, v_invite.auth_user_id, 'viewer')"));
    expect(sql, contains("set status = 'approved'"));
    expect(sql, contains("action_key = 'employee_onboarding_approval'"));
    expect(page, contains("child: const Text('本登録')"));
  });

  test('employee onboarding documents remain private', () {
    final sql = read(
      'supabase/migrations/20260922004500_add_employee_onboarding_profile_and_approval.sql',
    );

    expect(sql, contains("'employee-onboarding-documents'"));
    expect(sql, contains('false'));
    expect(sql, contains('employee_onboarding_documents_read'));
    expect(sql, contains('private.can_review_employee_onboarding_user'));
  });

  test('unused temporary invite expires but started onboarding does not', () {
    final sql = read(
      'supabase/migrations/20260922002000_add_employee_invite_foundation.sql',
    );

    expect(sql, contains("v_row.status = 'invited'"));
    expect(sql, contains("set status = 'cancelled'"));
    expect(sql, contains("interval '14 days'"));
  });
}
